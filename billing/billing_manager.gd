extends Node

## VR-07a（ALTA-285）：Play Billing「去廣告」IAP 包裝層。包一層
## res://addons/GodotGooglePlayBilling（Godot Engine 官方維護嘅 Play
## Billing plugin，BillingClient.gd）。Product id 見 AdConfig.
## BILLING_PRODUCT_REMOVE_ADS（"remove_ads"）。
##
## 沙盒未有真 Play Console product（留返 ALTA-154，用戶）：query_product_
## details 查唔到就當「原生 billing 唔可用」，purchase_remove_ads() 落
## mock 分支——本機即刻當購買成功，emit 嗰個 signal 同真購買一樣形狀，等
## 「購買 → 本機存檔 → 兩個廣告位停用 → 恢復購買」成條流程喺冇真
## Console product 之前都測得到（issue 原文：「沙盒未有真 product 就 mock
## 一層，介面一樣」）。用戶開好真 product 之後，_product_ready 會自然變
## true，自動轉用真購買流程，呢層 code 唔使郁。
##
## 喺 Godot editor／GUT 測試（冇 GodotGooglePlayBilling 原生 singleton）
## 一樣安全：_client 留 null，purchase_remove_ads()／restore_purchases()
## 全部行 mock／no-owned 分支，唔會噴錯。

signal remove_ads_purchase_completed(success: bool)
signal remove_ads_restore_completed(owned: bool)

var _client: BillingClient
var _connected := false
var _product_ready := false
var _pending_purchase := false


func _ready() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		return
	_client = BillingClient.new()
	add_child(_client)
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(_on_disconnected)
	_client.query_product_details_response.connect(_on_query_product_details_response)
	_client.query_purchases_response.connect(_on_query_purchases_response)
	_client.on_purchase_updated.connect(_on_purchase_updated)
	_client.start_connection()


func _on_connected() -> void:
	_connected = true
	_client.query_product_details(
		PackedStringArray([AdConfig.BILLING_PRODUCT_REMOVE_ADS]), BillingClient.ProductType.INAPP
	)


func _on_disconnected() -> void:
	_connected = false
	_product_ready = false


func _on_query_product_details_response(response: Dictionary) -> void:
	var details: Array = response.get("product_details", [])
	var ok: bool = int(response.get("response_code", -1)) == BillingClient.BillingResponseCode.OK
	_product_ready = ok and not details.is_empty()


## 購買「去廣告」。真 product 未查到（沙盒未開 Console product，或者
## 呢個環境冇原生 billing plugin）就即刻 mock 成功——見檔頭註解。
func purchase_remove_ads() -> void:
	if _connected and _product_ready:
		_pending_purchase = true
		_client.purchase(AdConfig.BILLING_PRODUCT_REMOVE_ADS)
		return
	remove_ads_purchase_completed.emit(true)


## 恢復購買：查詢現有 owned 嘅 inapp 購買，睇下有冇 remove_ads。連唔到
## 原生 billing 就冇嘢好查——本機存檔本身已經記低 ads_removed，回傳
## false 唔會冚走本機已有嘅狀態（呼叫方只喺 owned=true 先 set，見
## scenes/field.gd _on_remove_ads_restore_completed()）。
func restore_purchases() -> void:
	if _connected:
		_client.query_purchases(BillingClient.ProductType.INAPP)
		return
	remove_ads_restore_completed.emit(false)


func _on_purchase_updated(response: Dictionary) -> void:
	if not _pending_purchase:
		return
	_pending_purchase = false
	if int(response.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		remove_ads_purchase_completed.emit(false)
		return
	remove_ads_purchase_completed.emit(_acknowledge_and_check(response.get("purchases", [])))


func _on_query_purchases_response(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		remove_ads_restore_completed.emit(false)
		return
	remove_ads_restore_completed.emit(_acknowledge_and_check(response.get("purchases", [])))


## 揾返 remove_ads 呢粒 purchase：未 acknowledge 就補做（一次性購買唔
## acknowledge，Google 會自動退款收返），回傳係咪已經擁有（PURCHASED 狀態）。
func _acknowledge_and_check(purchases: Array) -> bool:
	var owned := false
	for purchase: Dictionary in purchases:
		var product_ids: Array = purchase.get("product_ids", [])
		if AdConfig.BILLING_PRODUCT_REMOVE_ADS not in product_ids:
			continue
		if int(purchase.get("purchase_state", -1)) != BillingClient.PurchaseState.PURCHASED:
			continue
		owned = true
		if not bool(purchase.get("is_acknowledged", false)):
			_client.acknowledge_purchase(String(purchase.get("purchase_token", "")))
	return owned

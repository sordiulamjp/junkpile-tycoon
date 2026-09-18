extends Control
## VR-07 驗證用嘅簡單畫面（ALTA-154）：初始化 AdMob → 攞一個測試 rewarded
## 廣告 → 撳掣播並顯示有冇拎到獎勵。用嚟證明 Poing Studios AdMob plugin 出到
## 嘅 Android APK（Godot 4.7.2）用得。
##
## 唔係正式遊戲畫面；`project.godot` 嘅 run/main_scene 平時指住
## res://main.tscn（VR-03 嗰個），淨係出呢個驗證 APK 嗰陣先臨時改。

@onready var _status_label: Label = %StatusLabel
@onready var _load_button: Button = %LoadButton
@onready var _show_button: Button = %ShowButton


func _ready() -> void:
	_load_button.disabled = true
	_show_button.disabled = true
	_load_button.pressed.connect(_on_load_pressed)
	_show_button.pressed.connect(_on_show_pressed)

	AdManager.ad_initialized.connect(_on_ad_initialized)
	AdManager.rewarded_ad_ready.connect(_on_rewarded_ad_ready)
	AdManager.rewarded_ad_load_failed.connect(_on_rewarded_ad_load_failed)
	AdManager.rewarded_ad_earned_reward.connect(_on_rewarded_ad_earned_reward)
	AdManager.rewarded_ad_dismissed.connect(_on_rewarded_ad_dismissed)

	_set_status("初始化緊 AdMob…")
	AdManager.request_consent_and_initialize()


func _on_ad_initialized() -> void:
	_set_status("AdMob 已初始化。撳「攞廣告」試載測試 rewarded 位。")
	_load_button.disabled = false


func _on_load_pressed() -> void:
	_load_button.disabled = true
	_set_status("載入緊測試 rewarded 廣告…")
	AdManager.load_rewarded_ad(AdConfig.PLACEMENT_OFFLINE_X2)


func _on_rewarded_ad_ready(_placement: String) -> void:
	_set_status("廣告已載入。撳「播廣告」。")
	_show_button.disabled = false


func _on_rewarded_ad_load_failed(_placement: String, message: String) -> void:
	_set_status("廣告載入失敗：%s" % message)
	_load_button.disabled = false


func _on_show_pressed() -> void:
	_show_button.disabled = true
	AdManager.show_rewarded_ad(AdConfig.PLACEMENT_OFFLINE_X2)


func _on_rewarded_ad_earned_reward(_placement: String, amount: int, type: String) -> void:
	_set_status("✅ 已發獎：%d %s" % [amount, type])


func _on_rewarded_ad_dismissed(_placement: String) -> void:
	_load_button.disabled = false


func _set_status(text: String) -> void:
	_status_label.text = text
	print("[AdTest] ", text)

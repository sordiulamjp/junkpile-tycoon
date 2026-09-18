extends Node
## VR-07a 商業化實作（ALTA-285）：包一層 Poing Studios AdMob plugin
## （res://addons/admob，Google Mobile Ads SDK wrapper）：UMP 同意表格 →
## child-directed = false → MobileAds 初始化 → rewarded 廣告位。前身係
## VR-07 第一步（ALTA-154）「只得一個 rewarded 位」嘅空 APK 驗證，證實
## plugin 對準 Godot 4.7.2 可用之後，呢度擴到兩個正式位（離線收入 ×2／
## 免費狂熱一次，額度見 GameConstants.rewarded_offline_x2_per_day／
## rewarded_extra_frenzy_per_day，用量狀態機見 systems/monetization_state.gd）。
##
## 廣告單元 id 集中喺 AdConfig（ads/ad_config.gd），呢度淨係負責同 AdMob
## SDK 溝通，唔識任何遊戲數值／每日額度邏輯（嗰啲留返俾呼叫方
## scenes/field.gd + MonetizationState）。
##
## 用法：autoload 單例。App 開頭（例如主場景 _ready）call 一次
## request_consent_and_initialize()，等 ad_initialized 之後先可以
## load_rewarded_ad(placement)（placement 用 AdConfig.PLACEMENT_*）。
## 呢個 SDK 同一時間淨係揸得住一個 rewarded 廣告個體，一個位載緊／播緊
## 嗰陣唔好同時載第二個位——呼叫方（field.gd）負責一次淨處理一個 pending
## placement，唔喺呢層做排隊。

signal ad_initialized
signal rewarded_ad_ready(placement: String)
signal rewarded_ad_load_failed(placement: String, message: String)
signal rewarded_ad_earned_reward(placement: String, amount: int, type: String)
signal rewarded_ad_dismissed(placement: String)

var _rewarded_ad: RewardedAd
var _rewarded_loader: RewardedAdLoader
var _ready_placement: String = ""


## 入口：UMP 同意 → 初始化 SDK。跟足 plugin 官方 sample 嘅 fallback 規則——
## 唔理同意結果係咩（包括查詢失敗），最終都要行到 _initialize_ads()。
func request_consent_and_initialize() -> void:
	var params := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(
		params,
		func() -> void:
			if UserMessagingPlatform.consent_information.get_is_consent_form_available():
				_load_and_show_consent_form()
			else:
				_initialize_ads(),
		func(error: FormError) -> void:
			push_warning("AdManager: UMP consent info update failed: %s" % error.message)
			_initialize_ads()
	)


func _load_and_show_consent_form() -> void:
	UserMessagingPlatform.load_consent_form(
		func(consent_form: ConsentForm) -> void:
			consent_form.show(
				func(error: FormError) -> void:
					if error:
						push_warning(
							"AdManager: consent form dismissed with error: %s" % error.message
						)
					_initialize_ads()
			),
		func(error: FormError) -> void:
			push_warning("AdManager: consent form failed to load: %s" % error.message)
			_initialize_ads()
	)


func _initialize_ads() -> void:
	var request_config := RequestConfiguration.new()
	# 合規清單：child-directed = false
	request_config.tag_for_child_directed_treatment = (
		RequestConfiguration.TagForChildDirectedTreatment.FALSE
	)
	MobileAds.set_request_configuration(request_config)

	var init_listener := OnInitializationCompleteListener.new()
	init_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		ad_initialized.emit()
	MobileAds.initialize(init_listener)


## 載入指定位置嘅 rewarded 廣告（placement 用 AdConfig.PLACEMENT_*）。兩個
## 位而家共用 AdConfig.rewarded_ad_unit_id()（沙盒測試單元），真帳戶到手
## 之後喺 AdConfig 分開填正式單元 id，呢度唔使改。
func load_rewarded_ad(placement: String) -> void:
	_rewarded_loader = RewardedAdLoader.new()

	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded_ad = ad
		_ready_placement = placement
		_setup_rewarded_callbacks(placement)
		rewarded_ad_ready.emit(placement)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		rewarded_ad_load_failed.emit(placement, error.message)

	_rewarded_loader.load(AdConfig.rewarded_ad_unit_id(), AdRequest.new(), callback)


func _setup_rewarded_callbacks(placement: String) -> void:
	var content_callback := FullScreenContentCallback.new()
	content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		_rewarded_ad.destroy()
		_rewarded_ad = null
		_ready_placement = ""
		rewarded_ad_dismissed.emit(placement)
	content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		push_warning("AdManager: rewarded ad failed to show: %s" % error.message)
		_rewarded_ad.destroy()
		_rewarded_ad = null
		_ready_placement = ""
	_rewarded_ad.full_screen_content_callback = content_callback


func has_rewarded_ad_ready(placement: String) -> bool:
	return _rewarded_ad != null and _ready_placement == placement


func show_rewarded_ad(placement: String) -> void:
	if not has_rewarded_ad_ready(placement):
		push_warning("AdManager: no rewarded ad loaded yet for placement %s" % placement)
		return
	var reward_listener := OnUserEarnedRewardListener.new()
	reward_listener.on_user_earned_reward = func(item: RewardedItem) -> void:
		rewarded_ad_earned_reward.emit(placement, item.amount, item.type)
	_rewarded_ad.show(reward_listener)

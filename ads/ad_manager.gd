extends Node
## VR-07 商業化第一階段：AdMob rewarded 廣告驗證（ALTA-154）。
##
## 包一層 Poing Studios AdMob plugin（res://addons/admob，Google Mobile Ads SDK
## wrapper）：UMP 同意表格 → child-directed = false → MobileAds 初始化 → 一個
## rewarded 廣告位（Google 官方公開測試單元）。用嚟驗證 plugin 對準 Godot 4.7.2
## 可用（"先做「只得一個 rewarded 位」嘅空 APK 驗證...先繼續"）。
##
## 兩個正式 rewarded 位（離線收入 ×2 / 免費狂熱一次，額度見
## GameConstants.rewarded_offline_x2_per_day / rewarded_extra_frenzy_per_day）
## 同 Google Play Billing 去廣告 IAP，留返呢步驗證通過、用戶提供真 AdMob／
## Play Console 帳戶到手先接（見 ALTA-154 留言）。
##
## 用法：autoload 單例。App 開頭（例如主選單 _ready）call 一次
## request_consent_and_initialize()，等 ad_initialized 之後先可以
## load_test_rewarded_ad()。

signal ad_initialized
signal rewarded_ad_ready
signal rewarded_ad_load_failed(message: String)
signal rewarded_ad_earned_reward(amount: int, type: String)
signal rewarded_ad_dismissed

## Google 官方公開嘅測試 rewarded 廣告單元 ID（唔屬於任何 AdMob 帳戶）。
## 上架前一定要換成真 AdMob 帳戶開嘅正式單元，唔准帶呢個 ID 落 Play 正式版。
const TEST_REWARDED_AD_UNIT_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_AD_UNIT_IOS := "ca-app-pub-3940256099942544/1712485313"

var _rewarded_ad: RewardedAd
var _rewarded_loader: RewardedAdLoader


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


## 攞得一個位嘅測試廣告（ALTA-154 第一步驗證用；唔係正式嘅離線 ×2／免費狂熱位）。
func load_test_rewarded_ad() -> void:
	var ad_unit_id := (
		TEST_REWARDED_AD_UNIT_ANDROID if OS.get_name() == "Android" else TEST_REWARDED_AD_UNIT_IOS
	)
	_rewarded_loader = RewardedAdLoader.new()

	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded_ad = ad
		_setup_rewarded_callbacks()
		rewarded_ad_ready.emit()
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		rewarded_ad_load_failed.emit(error.message)

	_rewarded_loader.load(ad_unit_id, AdRequest.new(), callback)


func _setup_rewarded_callbacks() -> void:
	var content_callback := FullScreenContentCallback.new()
	content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		_rewarded_ad.destroy()
		_rewarded_ad = null
		rewarded_ad_dismissed.emit()
	content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		push_warning("AdManager: rewarded ad failed to show: %s" % error.message)
		_rewarded_ad.destroy()
		_rewarded_ad = null
	_rewarded_ad.full_screen_content_callback = content_callback


func has_rewarded_ad_ready() -> bool:
	return _rewarded_ad != null


func show_rewarded_ad() -> void:
	if not _rewarded_ad:
		push_warning("AdManager: no rewarded ad loaded yet")
		return
	var reward_listener := OnUserEarnedRewardListener.new()
	reward_listener.on_user_earned_reward = func(item: RewardedItem) -> void:
		rewarded_ad_earned_reward.emit(item.amount, item.type)
	_rewarded_ad.show(reward_listener)

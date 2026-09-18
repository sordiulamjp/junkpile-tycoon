extends RefCounted
class_name AdConfig

## VR-07a：全部 AdMob／Play Billing id 集中喺呢度——用戶攞到真帳戶之後
## （ALTA-154 剩低嗰步：「填真 AdMob／Play Billing id」）淨係改呢份常數，
## ads/ad_manager.gd／billing/billing_manager.gd／scenes/field.gd 嗰堆
## 連接邏輯完全唔使郁。
##
## 而家全部用 Google 官方公開測試 id（唔屬於任何 AdMob／Play Console
## 帳戶），上架前一定要換晒做真帳戶開嘅正式 id。

## -- AdMob：Google 官方公開測試 rewarded 廣告單元 --
const REWARDED_AD_UNIT_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const REWARDED_AD_UNIT_IOS := "ca-app-pub-3940256099942544/1712485313"

## 兩個 rewarded 位（離線收入 ×2／免費狂熱一次）。Google 冇提供第二個
## 公開測試 rewarded 單元 id，沙盒階段兩個位共用返同一個測試單元；上架前
## 要喺 AdMob 開兩個獨立單元，分別覆寫呢兩個 key 對應嘅 id。
const PLACEMENT_OFFLINE_X2 := "offline_x2"
const PLACEMENT_EXTRA_FRENZY := "extra_frenzy"

static func rewarded_ad_unit_id() -> String:
	return REWARDED_AD_UNIT_ANDROID if OS.get_name() == "Android" else REWARDED_AD_UNIT_IOS

## -- Play Billing：去廣告 IAP（HK$38，ALTA-147 決策表）--
const BILLING_PRODUCT_REMOVE_ADS := "remove_ads"

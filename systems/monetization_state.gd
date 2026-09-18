extends RefCounted
class_name MonetizationState

## VR-07a（ALTA-285）：商業化狀態——兩個 rewarded 廣告位（離線收入 ×2／
## 免費狂熱一次）嘅每日額度 + 去廣告 IAP 擁有狀態。純數值，唔掛
## SceneTree，方便 GUT 直接 new() 測試（同 frenzy_state.gd／game_state.gd
## 一樣嘅風格）。AdManager（ads/ad_manager.gd）／BillingManager
## （billing/billing_manager.gd）兩個 autoload 淨係負責同原生 SDK 溝通，
## 「今日仲有幾多次」「去咗廣告未」呢啲判斷邏輯全部喺呢度。
##
## 日界：用 unix 秒 / 86400 取 UTC 日索引，唔理玩家時區——同
## systems/event_log.gd 一致嘅「唔使搞時區」做法，缺點係跨時區玩家嘅
## 「今日」同佢肉眼嗰日唔一定啱，呢個係 TUNE 級功能，接受呢個誤差。

var c: GameConstants

var ads_removed: bool = false
var _quota_day: int = 0
var _offline_x2_used_today: int = 0
var _extra_frenzy_used_today: int = 0


func _init(constants: GameConstants = null) -> void:
	c = constants if constants != null else GameConstants.new()


static func _day_index(now_unix: float) -> int:
	return int(now_unix) / 86400


func _roll_day_if_needed(now_unix: float) -> void:
	var day := _day_index(now_unix)
	if day != _quota_day:
		_quota_day = day
		_offline_x2_used_today = 0
		_extra_frenzy_used_today = 0


func offline_x2_remaining(now_unix: float) -> int:
	_roll_day_if_needed(now_unix)
	return maxi(0, c.rewarded_offline_x2_per_day - _offline_x2_used_today)


func can_use_offline_x2(now_unix: float) -> bool:
	return not ads_removed and offline_x2_remaining(now_unix) > 0


## 用咗一次離線 ×2（額度用晒／已去廣告就唔准用，回傳 false）。
func use_offline_x2(now_unix: float) -> bool:
	if not can_use_offline_x2(now_unix):
		return false
	_roll_day_if_needed(now_unix)
	_offline_x2_used_today += 1
	return true


func extra_frenzy_remaining(now_unix: float) -> int:
	_roll_day_if_needed(now_unix)
	return maxi(0, c.rewarded_extra_frenzy_per_day - _extra_frenzy_used_today)


func can_use_extra_frenzy(now_unix: float) -> bool:
	return not ads_removed and extra_frenzy_remaining(now_unix) > 0


## 用咗一次免費狂熱額外觸發（額度用晒／已去廣告就唔准用，回傳 false）。
func use_extra_frenzy(now_unix: float) -> bool:
	if not can_use_extra_frenzy(now_unix):
		return false
	_roll_day_if_needed(now_unix)
	_extra_frenzy_used_today += 1
	return true


func set_ads_removed(value: bool) -> void:
	ads_removed = value


func to_dict() -> Dictionary:
	return {
		"ads_removed": ads_removed,
		"quota_day": _quota_day,
		"offline_x2_used_today": _offline_x2_used_today,
		"extra_frenzy_used_today": _extra_frenzy_used_today,
	}


func from_dict(data: Dictionary) -> void:
	ads_removed = bool(data.get("ads_removed", false))
	_quota_day = int(data.get("quota_day", 0))
	_offline_x2_used_today = int(data.get("offline_x2_used_today", 0))
	_extra_frenzy_used_today = int(data.get("extra_frenzy_used_today", 0))

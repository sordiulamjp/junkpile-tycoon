extends GutTest

## ALTA-285（VR-07a）：res://systems/monetization_state.gd 單元測試。
## 覆蓋：兩個 rewarded 位每日額度（用盡／跨日重置）、去廣告之後兩個位
## 一齊停用、to_dict()／from_dict() round-trip。

var m: MonetizationState
const EPS := 0.001
const DAY := 86400.0

func before_each() -> void:
	m = MonetizationState.new()


# ── 離線 ×2 額度 ─────────────────────────────────────────────

func test_offline_x2_starts_with_full_daily_quota() -> void:
	assert_eq(m.offline_x2_remaining(0.0), m.c.rewarded_offline_x2_per_day)
	assert_true(m.can_use_offline_x2(0.0))

func test_use_offline_x2_decrements_remaining() -> void:
	assert_true(m.use_offline_x2(0.0))
	assert_eq(m.offline_x2_remaining(0.0), m.c.rewarded_offline_x2_per_day - 1)

func test_offline_x2_blocked_once_quota_exhausted() -> void:
	for _i in range(m.c.rewarded_offline_x2_per_day):
		assert_true(m.use_offline_x2(0.0))
	assert_false(m.can_use_offline_x2(0.0))
	assert_false(m.use_offline_x2(0.0))
	assert_eq(m.offline_x2_remaining(0.0), 0)

func test_offline_x2_quota_resets_on_new_day() -> void:
	for _i in range(m.c.rewarded_offline_x2_per_day):
		m.use_offline_x2(0.0)
	assert_false(m.can_use_offline_x2(0.0))
	assert_true(m.can_use_offline_x2(DAY), "跨咗一個 UTC 日界，額度應該重置")


# ── 免費狂熱額外觸發額度 ──────────────────────────────────────

func test_extra_frenzy_starts_with_full_daily_quota() -> void:
	assert_eq(m.extra_frenzy_remaining(0.0), m.c.rewarded_extra_frenzy_per_day)

func test_extra_frenzy_blocked_once_quota_exhausted() -> void:
	for _i in range(m.c.rewarded_extra_frenzy_per_day):
		assert_true(m.use_extra_frenzy(0.0))
	assert_false(m.can_use_extra_frenzy(0.0))
	assert_false(m.use_extra_frenzy(0.0))

func test_extra_frenzy_and_offline_x2_quotas_are_independent() -> void:
	for _i in range(m.c.rewarded_offline_x2_per_day):
		m.use_offline_x2(0.0)
	assert_false(m.can_use_offline_x2(0.0))
	assert_true(m.can_use_extra_frenzy(0.0), "兩個位額度分開計，唔應該互相影響")


# ── 去廣告 IAP ────────────────────────────────────────────────

func test_ads_removed_disables_both_rewarded_placements() -> void:
	m.set_ads_removed(true)
	assert_false(m.can_use_offline_x2(0.0))
	assert_false(m.can_use_extra_frenzy(0.0))
	assert_false(m.use_offline_x2(0.0))
	assert_false(m.use_extra_frenzy(0.0))

func test_ads_removed_defaults_false() -> void:
	assert_false(m.ads_removed)


# ── 存檔 round-trip ───────────────────────────────────────────

func test_to_dict_from_dict_round_trip() -> void:
	m.set_ads_removed(true)
	m.use_offline_x2(DAY * 3.0)
	m.use_extra_frenzy(DAY * 3.0)

	var restored := MonetizationState.new()
	restored.from_dict(m.to_dict())

	assert_true(restored.ads_removed)
	# 去廣告之後 remaining 判斷會短路做 0，所以直接讀內部欄位（經 to_dict()）
	# 確認額度用量真係跟埋一齊存返，唔係淨係 ads_removed 一個 flag。
	assert_eq(m.to_dict(), restored.to_dict())

func test_from_dict_defaults_missing_fields_to_unused() -> void:
	var restored := MonetizationState.new()
	restored.from_dict({})
	assert_false(restored.ads_removed)
	assert_true(restored.can_use_offline_x2(0.0))
	assert_true(restored.can_use_extra_frenzy(0.0))

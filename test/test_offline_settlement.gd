extends GutTest

## VR-05：res://data/offline_settlement.gd 單元測試。
## 覆蓋：正常離線、時間回撥、超過牆鐘上限、極短空隙、狀態更新正確性。

var c: GameConstants

func before_each() -> void:
	c = GameConstants.new()

const EPS := 0.001

func _state(overrides: Dictionary = {}) -> Dictionary:
	var s := SaveManager.default_state()
	for key in overrides:
		s[key] = overrides[key]
	return s


# ── settle_offline_secs：防回撥 ─────────────────────────────

func test_settle_offline_secs_normal_elapsed() -> void:
	assert_almost_eq(OfflineSettlement.settle_offline_secs(1000.0, 4600.0), 3600.0, EPS)

func test_settle_offline_secs_rollback_is_zero() -> void:
	assert_eq(OfflineSettlement.settle_offline_secs(5000.0, 1000.0), 0.0)

func test_settle_offline_secs_same_instant_is_zero() -> void:
	assert_eq(OfflineSettlement.settle_offline_secs(1000.0, 1000.0), 0.0)


# ── settle()：正常離線 ───────────────────────────────────────

func test_settle_normal_offline_within_first_band() -> void:
	var state := _state({"last_save_unix": 0.0, "cash": 100.0, "lifetime_cash": 100.0})
	var result := OfflineSettlement.settle(c, state, 3600.0, 10.0)
	assert_almost_eq(result["cash_yield"], 36000.0, EPS)
	assert_almost_eq(result["elapsed_secs"], 3600.0, EPS)
	assert_almost_eq(result["state"]["cash"], 100.0 + 36000.0, EPS)
	assert_almost_eq(result["state"]["lifetime_cash"], 100.0 + 36000.0, EPS)
	assert_almost_eq(result["state"]["last_save_unix"], 3600.0, EPS)

func test_settle_normal_offline_crosses_bands() -> void:
	# 3 小時 = 2h(100%) + 1h(70%)
	var state := _state({"last_save_unix": 0.0})
	var result := OfflineSettlement.settle(c, state, 10800.0, 10.0)
	assert_almost_eq(result["cash_yield"], 72000.0 + 25200.0, EPS)


# ── settle()：時間回撥當 0 ───────────────────────────────────

func test_settle_rollback_yields_zero_and_state_unchanged() -> void:
	var state := _state({"last_save_unix": 5000.0, "cash": 42.0, "lifetime_cash": 42.0})
	var result := OfflineSettlement.settle(c, state, 1000.0, 10.0)
	assert_eq(result["cash_yield"], 0.0)
	assert_almost_eq(result["state"]["cash"], 42.0, EPS)
	assert_almost_eq(result["state"]["lifetime_cash"], 42.0, EPS)
	# 就算回撥，last_save_unix 都要更新做而家嘅時間，唔可以卡喺舊時間戳
	assert_almost_eq(result["state"]["last_save_unix"], 1000.0, EPS)


# ── settle()：超過牆鐘上限 ───────────────────────────────────

func test_settle_caps_at_wall_clock_limit() -> void:
	var state := _state({"last_save_unix": 0.0})
	var at_cap := OfflineSettlement.settle(c, state, c.offline_cap_secs, 10.0)
	var far_beyond := OfflineSettlement.settle(c, state, c.offline_cap_secs + 999999.0, 10.0)
	assert_almost_eq(far_beyond["cash_yield"], at_cap["cash_yield"], EPS, "超過上限唔應該再加")
	assert_almost_eq(at_cap["capped_secs"], c.offline_cap_secs, EPS)
	assert_almost_eq(far_beyond["capped_secs"], c.offline_cap_secs, EPS)


# ── settle()：極短空隙當 0 ───────────────────────────────────

func test_settle_very_short_gap_is_zero() -> void:
	var state := _state({"last_save_unix": 0.0})
	var result := OfflineSettlement.settle(c, state, c.offline_min_gap_secs - 1.0, 10.0)
	assert_eq(result["cash_yield"], 0.0)

func test_settle_at_min_gap_threshold_counts() -> void:
	var state := _state({"last_save_unix": 0.0})
	var result := OfflineSettlement.settle(c, state, c.offline_min_gap_secs, 10.0)
	assert_almost_eq(result["cash_yield"], c.offline_min_gap_secs * 10.0, EPS)

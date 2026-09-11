extends GutTest

## VR-02：res://data/constants.gd 單元測試。
## 覆蓋：離線 banded yield 三區間 + 上限、回撥當 0、極短空隙當 0、
## 門倍數乘法、礦工／精煉價格曲線。另加少量 docx 數值 sanity check。

var c: GameConstants

func before_each() -> void:
	c = GameConstants.new()

const EPS := 0.001


# ── 離線 banded yield ────────────────────────────────────────

func test_offline_yield_within_first_band_0_to_2h() -> void:
	# 1h，全數落喺 0–2h（100%）區間
	var got := c.compute_offline_yield(10.0, 3600.0)
	assert_almost_eq(got, 36000.0, EPS)

func test_offline_yield_crosses_into_2_to_6h_band() -> void:
	# 3h = 2h（100%）+ 1h（70%）
	var got := c.compute_offline_yield(10.0, 10800.0)
	assert_almost_eq(got, 72000.0 + 25200.0, EPS)

func test_offline_yield_crosses_into_6_to_8h_band() -> void:
	# 7h = 2h（100%）+ 4h（70%）+ 1h（40%）
	var got := c.compute_offline_yield(10.0, 25200.0)
	assert_almost_eq(got, 72000.0 + 100800.0 + 14400.0, EPS)

func test_offline_yield_caps_at_wall_clock_limit() -> void:
	var at_cap := c.compute_offline_yield(10.0, c.offline_cap_secs)
	var beyond_cap := c.compute_offline_yield(10.0, c.offline_cap_secs + 999999.0)
	assert_almost_eq(beyond_cap, at_cap, EPS, "超過上限唔應該再加")
	assert_almost_eq(at_cap, 72000.0 + 100800.0 + 28800.0, EPS)

func test_offline_yield_rollback_is_zero() -> void:
	assert_eq(c.compute_offline_yield(10.0, -1.0), 0.0)
	assert_eq(c.compute_offline_yield(10.0, -3600.0), 0.0)

func test_offline_yield_very_short_gap_is_zero() -> void:
	assert_eq(c.compute_offline_yield(10.0, 0.0), 0.0)
	assert_eq(c.compute_offline_yield(10.0, c.offline_min_gap_secs - 1.0), 0.0)

func test_offline_yield_at_min_gap_threshold_counts() -> void:
	var got := c.compute_offline_yield(10.0, c.offline_min_gap_secs)
	assert_almost_eq(got, c.offline_min_gap_secs * 10.0, EPS)


# ── 倍數門 ────────────────────────────────────────────────────

func test_gate_multiplier_known_gates() -> void:
	assert_almost_eq(c.gate_multiplier("main"), 2.0, EPS)
	assert_almost_eq(c.gate_multiplier("mid"), 3.0, EPS)
	assert_almost_eq(c.gate_multiplier("west"), 4.0, EPS)
	assert_almost_eq(c.gate_multiplier("peak"), 5.0, EPS)

func test_gate_multiplier_unknown_gate_is_neutral() -> void:
	assert_almost_eq(c.gate_multiplier("does-not-exist"), 1.0, EPS)

func test_combined_gate_multiplier_multiplies() -> void:
	assert_almost_eq(c.combined_gate_multiplier(["main", "mid"]), 6.0, EPS)
	assert_almost_eq(
		c.combined_gate_multiplier(["main", "mid", "west", "peak"]), 120.0, EPS
	)

func test_combined_gate_multiplier_empty_is_identity() -> void:
	assert_almost_eq(c.combined_gate_multiplier([]), 1.0, EPS)


# ── 礦工／精煉價格曲線 ──────────────────────────────────────

func test_miner_summon_cost_curve() -> void:
	assert_almost_eq(c.miner_summon_cost(1), 15.0, EPS)
	assert_almost_eq(c.miner_summon_cost(2), 15.0 * 1.4, EPS)
	assert_almost_eq(c.miner_summon_cost(3), 15.0 * pow(1.4, 2), EPS)

func test_miner_level_cost_curve() -> void:
	assert_almost_eq(c.miner_level_cost(1), 25.0 * 1.20, EPS)
	assert_almost_eq(c.miner_level_cost(2), 25.0 * pow(1.20, 2), EPS)

func test_refine_level_cost_curve() -> void:
	assert_almost_eq(c.refine_level_cost(1), 300.0 * 1.7, EPS)
	assert_almost_eq(c.refine_level_cost(2), 300.0 * pow(1.7, 2), EPS)

func test_belt_upgrade_cost_curve() -> void:
	assert_almost_eq(c.belt_upgrade_cost(1), 60.0, EPS)
	assert_almost_eq(c.belt_upgrade_cost(2), 60.0 * 1.5, EPS)

func test_price_curves_are_strictly_increasing() -> void:
	for n in range(1, 12):
		assert_gt(c.miner_summon_cost(n + 1), c.miner_summon_cost(n))
		assert_gt(c.miner_level_cost(n + 1), c.miner_level_cost(n))
		assert_gt(c.refine_level_cost(n + 1), c.refine_level_cost(n))


# ── docx 定案數值 sanity check ─────────────────────────────

func test_save_key_is_junkpile_v1() -> void:
	assert_eq(GameConstants.SAVE_KEY, "junkpile-save-v1")

func test_ore_tier_values() -> void:
	assert_eq(c.ore_tier_value["stone"], 1)
	assert_eq(c.ore_tier_value["coal"], 2)
	assert_eq(c.ore_tier_value["copper"], 4)
	assert_eq(c.ore_tier_value["gold"], 8)
	assert_eq(c.ore_tier_value["diamond"], 18)
	assert_eq(c.ore_tier_value["crown"], 40)

func test_miner_summon_cap_is_twelve() -> void:
	assert_eq(c.miner_summon_cap, 12)

func test_manager_card_costs() -> void:
	assert_eq(c.manager_card_cost["shaft"], 450)
	assert_eq(c.manager_card_cost["lift"], 900)
	assert_eq(c.manager_card_cost["store"], 1400)

func test_belt_connect_levels() -> void:
	assert_eq(c.belt_connect_lv["east"], 1)
	assert_eq(c.belt_connect_lv["mid"], 5)
	assert_eq(c.belt_connect_lv["west"], 10)

func test_unlock_prices() -> void:
	assert_almost_eq(c.unlock_price("mid"), 2000000.0, EPS)
	assert_almost_eq(c.unlock_price("upper"), 30000000.0, EPS)
	assert_almost_eq(c.unlock_price("nope"), 0.0, EPS)

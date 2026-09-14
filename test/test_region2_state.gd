extends GutTest

## ALTA-229（VR-13）res://regions/region2_outer_path/region2_state.gd
## 單元測試。issue 驗收明文要求：「倍數相乘、木橋限重、磚牆撞爛、礦站
## 賣價寫成單元測試」——四段分別對應底下四組測試。跟
## test/test_mine_state.gd 同一風格：呢個 class 唔擁有 cash，`tick()`／
## `run_convoy_cycle()` 淨係回傳 cash_gain 畀呼叫方自己入帳。

var s: Region2State
const EPS := 0.001

func before_each() -> void:
	s = Region2State.new()


# ── 倍數板：相乘 ─────────────────────────────────────────

func test_no_gates_passed_means_no_multiplier() -> void:
	assert_almost_eq(s.current_multiplier(0), 1.0, EPS)

func test_multiplier_compounds_across_gates_in_order() -> void:
	assert_almost_eq(s.current_multiplier(1), 2.0, EPS, "頭一道門 ×2")
	assert_almost_eq(s.current_multiplier(2), 6.0, EPS, "×2 × ×3")
	assert_almost_eq(s.current_multiplier(3), 24.0, EPS, "×2 × ×3 × ×4")
	assert_almost_eq(s.current_multiplier(4), 120.0, EPS, "×2 × ×3 × ×4 × ×5＝120")

func test_multiplier_does_not_overflow_past_the_last_gate() -> void:
	assert_almost_eq(s.current_multiplier(99), 120.0, EPS, "冚晒 4 道門就封頂，唔會再乘多次")


# ── 灰磚牆：×3 後撞爛先過 ─────────────────────────────────

func test_cannot_break_wall_before_reaching_it() -> void:
	assert_false(s.can_break_wall(0), "未攞過任何門，未夠衝力")
	assert_false(s.can_break_wall(1), "淨攞咗 ×2，仲差 ×3 先夠")

func test_can_break_wall_only_after_gate_two_and_three() -> void:
	assert_true(s.can_break_wall(2), "攞齊 ×2／×3 兩道門，夠衝力撞爛磚牆")
	assert_true(s.can_break_wall(4), "行到路尾梗係已經撞爛咗")


# ── 100 lb 木橋：超重斷橋 ─────────────────────────────────

func test_default_cart_weight_is_within_bridge_limit() -> void:
	assert_true(s.can_cross_bridge(s.cart_weight_lb()), "預設數值下應該過得到木橋，唔係開場就注定斷橋")

func test_cart_exactly_at_limit_can_cross() -> void:
	assert_true(s.can_cross_bridge(s.c.bridge_weight_limit_lb), "啱啱 100 lb（issue 明文限重）應該過得")

func test_cart_over_limit_breaks_the_bridge() -> void:
	assert_false(s.can_cross_bridge(s.c.bridge_weight_limit_lb + 0.01), "超重 0.01 lb 都應該斷橋")

func test_run_convoy_cycle_loses_cargo_when_overloaded() -> void:
	s.c.ore_load_count = 50 # 40 + 6*50 = 340 lb，遠超 100 lb 限重
	var result := s.run_convoy_cycle()
	assert_true(result["bridge_broke"])
	assert_almost_eq(result["cash_gain"], 0.0, EPS, "斷橋貨清零，冇 Cash")
	assert_eq(s.runs_lost_to_bridge, 1)

func test_run_convoy_cycle_succeeds_and_sells_when_within_limit() -> void:
	var result := s.run_convoy_cycle()
	assert_false(result["bridge_broke"])
	assert_gt(result["cash_gain"], 0.0)
	assert_eq(s.runs_completed, 1)


# ── 礦站：賣出倍數後嘅礦，比熔爐賺多 ──────────────────────

func test_station_price_bonus_is_strictly_above_break_even() -> void:
	assert_gt(s.c.station_price_bonus_mult, 1.0, "礦站要賣得比原礦底值貴，先叫「比熔爐賺多」")

## 直接同 regions/region1_mine/mine_constants.gd 嘅熔爐均價（MineState.tick()
## 用嘅 blended value）對比：即使未過任何倍數板（gates_passed=0），礦站
## 都要賣得比熔爐貴——呢個係 issue「礦站…比熔爐賺多」嘅字面判定。
func test_station_price_beats_furnace_blended_value_even_before_any_gate() -> void:
	var mine_c := MineConstants.new()
	var furnace_blended: float = (mine_c.ore_value_silver + mine_c.ore_value_gold) * 0.5
	var station_price := s.sell_at_station(furnace_blended, 0)
	assert_gt(station_price, furnace_blended, "礦站賣同一份原礦嘅底值應該比熔爐嘅均價高")

func test_sell_at_station_scales_with_multiplier_and_shack_tier() -> void:
	var base := 10.0
	var no_gates := s.sell_at_station(base, 0)
	var all_gates := s.sell_at_station(base, 4)
	assert_almost_eq(all_gates, no_gates * 120.0, EPS, "過齊 4 道門應該加成 120 倍")

	s.apply_shack_upgrade()
	var after_shack := s.sell_at_station(base, 0)
	assert_gt(after_shack, no_gates, "買咗 UPGRADE 小屋應該賣得貴啲")


# ── UPGRADE 小屋（200／500）：順序買，扣共用 cash 嘅部分見 test_region2_zone.gd ──

func test_shack_upgrades_in_order_and_caps_at_two_tiers() -> void:
	assert_almost_eq(s.next_shack_cost(), s.c.shack_tier_cost[0], EPS)
	s.apply_shack_upgrade()
	assert_eq(s.shack_tier, 1)
	assert_almost_eq(s.shack_output_mult(), s.c.shack_tier_output_mult[0], EPS)
	s.apply_shack_upgrade()
	assert_eq(s.shack_tier, 2)
	assert_false(s.can_upgrade_shack(), "200／500 兩級買晒就冇下一級")


# ── tick()：自動出貨週期 ──────────────────────────────────

func test_tick_does_nothing_before_cycle_interval_elapses() -> void:
	var result := s.tick(s.c.cycle_interval_secs - 0.01)
	assert_false(result["cycle_completed"])
	assert_almost_eq(result["cash_gain"], 0.0, EPS)

func test_tick_completes_a_cycle_once_interval_elapses() -> void:
	var result := s.tick(s.c.cycle_interval_secs)
	assert_true(result["cycle_completed"])
	assert_gt(result["cash_gain"], 0.0)

func test_tick_accumulates_leftover_time_across_frames() -> void:
	var half := s.c.cycle_interval_secs * 0.5
	assert_false(s.tick(half)["cycle_completed"])
	var second := s.tick(half)
	assert_true(second["cycle_completed"], "兩次半週期加埋應該啱啱夠鐘出一次貨")

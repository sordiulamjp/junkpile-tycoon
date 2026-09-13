extends GutTest

## ALTA-228（VR-12）res://regions/region1_mine/mine_state.gd 單元測試。
## Reviewer round 1 修正：呢個 class 唔再擁有 cash——覆蓋範圍改做層 1
## 開場已開／層 2-3 順序解鎖、三條升級線扣費同封頂（礦車／倉庫 Lv10）、
## 三段管線流量（層台緩衝 → 礦車 → 地面緩衝 → 倉庫，`tick()` 回傳
## cash_gain 唔再自己入帳）、塞爆／礦車停運、瓶頸偵測、地面礦堆 tap
## 收礦（銀多金少 + 鏟斗 tier 倍率 + 狂熱倍率）。

var s: MineState
const EPS := 0.001

func before_each() -> void:
	s = MineState.new()


# ── 層解鎖：1 開場已開，2／3 順序解鎖 ──────────────────────

func test_layer_one_is_open_from_the_start_and_layers_two_three_are_locked() -> void:
	assert_true(s.layer_unlocked[0])
	assert_false(s.layer_unlocked[1])
	assert_false(s.layer_unlocked[2])
	assert_gt(s.layer_rate(0), 0.0)
	assert_eq(s.layer_rate(1), 0.0)
	assert_eq(s.layer_rate(2), 0.0)

func test_layer_one_unlock_cost_is_zero() -> void:
	assert_almost_eq(s.layer_unlock_cost(0), 0.0, EPS)

func test_cannot_unlock_layer_three_before_layer_two() -> void:
	assert_false(s.can_unlock_layer(2), "層 2 未解鎖之前唔可以跳級解鎖層 3")
	assert_true(s.can_unlock_layer(1), "層 2 應該即刻可以解鎖（前一層即層 1 恆常已開）")

func test_unlock_layer_two_then_three_in_order() -> void:
	assert_true(s.can_unlock_layer(1))
	s.apply_layer_unlock(1)
	assert_true(s.layer_unlocked[1])
	assert_gt(s.layer_rate(1), 0.0)
	assert_true(s.can_unlock_layer(2), "層 2 解鎖咗，層 3 而家應該解鎖得")
	s.apply_layer_unlock(2)
	assert_true(s.layer_unlocked[2])

func test_layer_0_cannot_be_unlocked_again() -> void:
	assert_false(s.can_unlock_layer(0), "層 1 恆常已開，唔應該再俾佢『解鎖』一次")


# ── 每層開採速度升級 ─────────────────────────────────────

func test_upgrade_layer_speed_increases_rate() -> void:
	var base_rate := s.layer_rate(0)
	s.apply_layer_speed_upgrade(0)
	assert_eq(s.layer_level[0], 1)
	assert_almost_eq(s.layer_rate(0), base_rate * s.c.layer_level_speed_mult, EPS)

func test_layer_speed_upgrade_has_no_cap() -> void:
	for i in range(50):
		s.apply_layer_speed_upgrade(1)
	assert_eq(s.layer_level[1], 50)


# ── 礦車／倉庫升級線（封頂 Lv10） ────────────────────────

func test_upgrade_cart_increments_level_and_caps_at_ten() -> void:
	for i in range(s.c.cart_level_cap - 1):
		assert_true(s.can_upgrade_cart())
		s.apply_cart_upgrade()
	assert_eq(s.cart_level, s.c.cart_level_cap)
	assert_false(s.can_upgrade_cart())

func test_upgrade_warehouse_increments_level_and_caps_at_ten() -> void:
	for i in range(s.c.warehouse_level_cap - 1):
		assert_true(s.can_upgrade_warehouse())
		s.apply_warehouse_upgrade()
	assert_eq(s.warehouse_level, s.c.warehouse_level_cap)
	assert_false(s.can_upgrade_warehouse())


# ── 推堆墊 tier（150／500／1000） ────────────────────────

func test_push_tier_starts_at_zero_with_no_multiplier() -> void:
	assert_eq(s.push_tier, 0)
	assert_almost_eq(s.scoop_value_mult(), 1.0, EPS)

func test_push_tier_upgrades_in_order_and_increases_scoop_mult() -> void:
	assert_almost_eq(s.next_push_tier_cost(), s.c.push_tier_cost[0], EPS)
	s.apply_push_tier_upgrade()
	assert_eq(s.push_tier, 1)
	assert_almost_eq(s.scoop_value_mult(), s.c.push_tier_scoop_mult[0], EPS)
	s.apply_push_tier_upgrade()
	s.apply_push_tier_upgrade()
	assert_eq(s.push_tier, 3)
	assert_false(s.can_upgrade_push_tier(), "3 級（150／500／1000）買晒就冇下一級")


# ── 地面礦堆：生成 + tap 收礦 ─────────────────────────────

func test_spawn_pile_only_yields_silver_or_gold() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(20):
		var key := s.spawn_pile(rng)
		assert_true(key == "silver" or key == "gold" or key == "", "回傳值一定係 silver／gold／已滿嘅 \"\"")

func test_spawn_pile_stops_at_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in range(s.c.pile_cap):
		s.spawn_pile(rng)
	assert_eq(s.pile_ore.size(), s.c.pile_cap)
	assert_eq(s.spawn_pile(rng), "", "夠 pile_cap 就唔再生")
	assert_eq(s.pile_ore.size(), s.c.pile_cap)

func test_scoop_pile_credits_base_value_and_removes_only_matching_entry() -> void:
	s.pile_ore = ["silver", "gold", "silver"]
	var gained := s.scoop_pile("gold")
	assert_almost_eq(gained, s.c.ore_value_gold, EPS)
	assert_eq(s.pile_ore, ["silver", "silver"])

func test_scoop_pile_missing_key_is_zero() -> void:
	s.pile_ore = ["silver"]
	assert_almost_eq(s.scoop_pile("gold"), 0.0, EPS)
	assert_eq(s.pile_ore, ["silver"])

func test_scoop_pile_value_scales_with_push_tier() -> void:
	s.pile_ore = ["silver"]
	s.apply_push_tier_upgrade() # tier 1，×push_tier_scoop_mult[0]
	var gained := s.scoop_pile("silver")
	assert_almost_eq(gained, s.c.ore_value_silver * s.c.push_tier_scoop_mult[0], EPS)

func test_scoop_pile_value_multiplies_during_frenzy() -> void:
	s.pile_ore = ["gold"]
	var gained := s.scoop_pile("gold", true)
	assert_almost_eq(gained, s.c.ore_value_gold * s.c.frenzy_income_mult, EPS)


# ── 三段管線流量（層台緩衝 → 礦車 → 地面緩衝 → 倉庫） ────

func test_tick_returns_cash_gain_for_caller_to_credit() -> void:
	# MineState 冇自己嘅 cash 欄位（Reviewer round 1 修正）——呼叫方
	# （mine_zone.gd）自己攞 tick() 嘅 cash_gain 加落 GameState.cash。
	var result := s.tick(1.0)
	assert_true(result.has("cash_gain"))
	assert_gt(result["cash_gain"], 0.0)

func test_tick_moves_material_through_the_full_pipeline_once_layer_open() -> void:
	var mine_out := s.total_mine_output()
	var expected_lifted: float = minf(s.cart_capacity(), mine_out)
	var expected_collected: float = minf(s.warehouse_capacity(), expected_lifted)
	var result := s.tick(1.0)
	assert_almost_eq(result["mined"], mine_out, EPS)
	assert_almost_eq(result["jammed"], 0.0, EPS)
	assert_almost_eq(result["lifted"], expected_lifted, EPS)
	assert_almost_eq(result["collected"], expected_collected, EPS)
	assert_gt(result["cash_gain"], 0.0)

func test_tick_jams_underground_when_buffer_cap_too_small() -> void:
	s.c.underground_backlog_cap = 0.01
	var mine_out := s.total_mine_output()
	var result := s.tick(1.0)
	assert_gt(result["jammed"], 0.0)
	assert_almost_eq(result["jammed"], mine_out - minf(mine_out, 0.01), EPS)

func test_tick_cart_goes_idle_when_ground_buffer_is_full() -> void:
	s.c.ground_backlog_cap = 0.0
	var result := s.tick(1.0)
	assert_true(result["cart_idle"])
	assert_almost_eq(result["lifted"], 0.0, EPS)
	assert_almost_eq(result["collected"], 0.0, EPS)


# ── 瓶頸偵測 ─────────────────────────────────────────────

func test_bottleneck_stage_detects_cart_when_far_behind() -> void:
	s.apply_layer_unlock(1)
	s.apply_layer_unlock(2)
	for i in range(6):
		s.apply_layer_speed_upgrade(0)
		s.apply_layer_speed_upgrade(1)
		s.apply_layer_speed_upgrade(2)
	s.warehouse_level = 6
	assert_eq(s.bottleneck_stage(), "cart")

func test_bottleneck_stage_detects_warehouse_when_far_behind() -> void:
	s.apply_layer_unlock(1)
	s.apply_layer_unlock(2)
	for i in range(6):
		s.apply_layer_speed_upgrade(0)
		s.apply_layer_speed_upgrade(1)
		s.apply_layer_speed_upgrade(2)
	s.cart_level = 10
	assert_eq(s.bottleneck_stage(), "warehouse")

func test_bottleneck_shifts_from_layers_to_warehouse_as_more_layers_unlock() -> void:
	# 開場淨層 1 出礦（0.6/s）遠細過礦車／倉庫上限（1.8／1.5），呢一刻
	# 樽頸一定係 "layers"；解鎖埋層 2／3（各 0.6/s，共 1.8/s＝啱啱追平
	# 礦車上限），追過咗倉庫上限 1.5/s，樽頸應該轉去 "warehouse"。
	assert_eq(s.bottleneck_stage(), "layers")
	s.apply_layer_unlock(1)
	s.apply_layer_unlock(2)
	assert_eq(s.bottleneck_stage(), "warehouse")

func test_bottleneck_is_balanced_when_three_stages_are_within_tolerance() -> void:
	s.apply_layer_unlock(1)
	s.apply_layer_unlock(2) # mine_out = cart = 1.8
	s.apply_warehouse_upgrade() # warehouse Lv1→2：1.5×1.22 ≈ 1.83，同其餘兩段相差 < 5%
	assert_eq(s.bottleneck_stage(), "balanced")

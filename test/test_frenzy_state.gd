extends GutTest

## VR-04：res://systems/frenzy_state.gd 單元測試。
## 覆蓋：首次縮短冷卻／一般冷卻、免費觸發、倍數門（單一／連續相乘）、
## FRENZY_MANUAL_EFF 縮放、滾筒藍波→金幣、跟指車夾範圍同速度、
## UPGRADE 墊逐級升同冷卻、窄岩浆溢滿同零掉坑花紅、齒輪、幀數自動降級。

var f: FrenzyState
const EPS := 0.001

func before_each() -> void:
	f = FrenzyState.new()


# ── 觸發／冷卻 ───────────────────────────────────────────

func test_initial_cooldown_is_shortened_first_cooldown() -> void:
	assert_almost_eq(f.cooldown_remaining, f.c.frenzy_first_cooldown_secs, EPS)
	assert_false(f.can_start())

func test_can_start_once_first_cooldown_elapses() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	assert_true(f.can_start())

func test_start_is_free_and_does_not_touch_cash() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	assert_true(f.start(0.0))
	assert_true(f.active)
	assert_almost_eq(f.time_remaining, f.c.frenzy_duration_secs, EPS)

func test_start_fails_while_on_cooldown() -> void:
	assert_false(f.start(0.0))
	assert_false(f.active)

func test_start_fails_while_already_active() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	assert_true(f.start(0.0))
	assert_false(f.start(0.0))

func test_reference_total_uses_income_rate_mult_and_duration() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(10.0)
	assert_almost_eq(f.frenzy_reference_total, 10.0 * f.c.frenzy_mult * f.c.frenzy_duration_secs, EPS)

func test_tick_ends_frenzy_and_applies_normal_cooldown_not_first() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	var events := f.tick(f.c.frenzy_duration_secs + 1.0)
	assert_true(events["ended"])
	assert_false(f.active)
	assert_almost_eq(f.cooldown_remaining, f.c.frenzy_cooldown_secs, EPS)

func test_second_frenzy_needs_full_cooldown_not_first_cooldown() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	f.tick(f.c.frenzy_duration_secs + 1.0)
	assert_false(f.can_start())
	f.tick(f.c.frenzy_cooldown_secs - 1.0)
	assert_false(f.can_start())
	f.tick(1.0)
	assert_true(f.can_start())


# ── 倍數門 + FRENZY_MANUAL_EFF ──────────────────────────

func test_score_item_single_gate_applies_multiplier_and_manual_eff() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	var awarded := f.score_item(f.c.scrap_coin_value, ["main"])
	var expected: float = f.c.scrap_coin_value * f.c.gate_multiplier("main") * f.c.frenzy_manual_eff
	assert_almost_eq(awarded, expected, EPS)
	assert_almost_eq(f.cash_earned, expected, EPS)

func test_score_item_combined_gates_multiply_together() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	var awarded := f.score_item(f.c.scrap_gold_value, ["west", "peak"])
	var expected_mult: float = f.c.gate_multiplier("west") * f.c.gate_multiplier("peak")
	assert_almost_eq(awarded, f.c.scrap_gold_value * expected_mult * f.c.frenzy_manual_eff, EPS)

func test_score_item_does_nothing_when_not_active() -> void:
	assert_almost_eq(f.score_item(f.c.scrap_coin_value, ["main"]), 0.0, EPS)
	assert_almost_eq(f.cash_earned, 0.0, EPS)


# ── 散幣／藍波／刺滾筒 ──────────────────────────────────

func test_base_value_for_kind_matches_constants() -> void:
	assert_almost_eq(f.base_value_for_kind("coin"), f.c.scrap_coin_value, EPS)
	assert_almost_eq(f.base_value_for_kind("barrel"), f.c.scrap_barrel_value, EPS)
	assert_almost_eq(f.base_value_for_kind("gold"), f.c.scrap_gold_value, EPS)

func test_apply_roller_converts_barrel_to_gold_only() -> void:
	assert_eq(f.apply_roller("barrel"), "gold")
	assert_eq(f.apply_roller("coin"), "coin")
	assert_eq(f.apply_roller("gold"), "gold")

func test_roll_spawn_kind_respects_barrel_ratio_with_seeded_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var barrels := 0
	var total := 2000
	for i in range(total):
		if f.roll_spawn_kind(rng) == "barrel":
			barrels += 1
	var ratio := float(barrels) / float(total)
	assert_almost_eq(ratio, f.c.barrel_spawn_ratio, 0.05)


# ── 跟指車 + UPGRADE 墊 ──────────────────────────────────

func test_advance_car_clamps_to_yard_x_range() -> void:
	f.advance_car(1000.0, 99.0)
	assert_almost_eq(f.car_x, f.c.yard_x_range.y, EPS)
	f.advance_car(1000.0, -99.0)
	assert_almost_eq(f.car_x, f.c.yard_x_range.x, EPS)

func test_advance_car_moves_at_most_speed_times_delta() -> void:
	f.car_x = 0.0
	f.advance_car(0.1, 99.0)
	assert_almost_eq(f.car_x, f.c.car_speed * 0.1, EPS)

func test_upgrade_pad_requires_active_frenzy() -> void:
	assert_false(f.try_upgrade_pad())
	assert_eq(f.car_tier, 0)

func test_upgrade_pad_advances_tier_and_caps_at_last() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	var tiers: int = f.c.car_upgrade_tiers.size()
	for i in range(tiers + 2):
		f.pad_cooldown = 0.0 # 每次都即刻重新武裝，測試逐級升到封頂
		f.try_upgrade_pad()
	assert_eq(f.car_tier, tiers - 1)

func test_upgrade_pad_respects_rearm_cooldown() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	assert_true(f.try_upgrade_pad())
	assert_false(f.try_upgrade_pad())
	assert_eq(f.car_tier, 1)

func test_advance_car_speed_scales_with_current_tier() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	f.try_upgrade_pad()
	f.car_x = 0.0
	f.advance_car(0.1, 99.0)
	var expected_mult: float = f.current_tier()["speed_mult"]
	assert_almost_eq(f.car_x, f.c.car_speed * expected_mult * 0.1, EPS)


# ── 窄岩浆 + 木橋 ────────────────────────────────────────

func test_is_bridge_safe_x_matches_safe_range() -> void:
	assert_true(f.is_bridge_safe_x(f.c.lava_bridge_safe_x_range.x))
	assert_true(f.is_bridge_safe_x(f.c.lava_bridge_safe_x_range.y))
	assert_false(f.is_bridge_safe_x(f.c.lava_bridge_safe_x_range.y + 0.5))

func test_lava_fall_adds_overflow_clamped_at_trash_meter_cap() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	for i in range(50):
		f.register_lava_fall()
	assert_almost_eq(f.overflow, float(f.c.trash_meter_cap), EPS)

func test_perfect_sort_bonus_awarded_only_without_a_fall() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	f.tick(f.c.frenzy_duration_secs + 1.0)
	assert_almost_eq(f.eco_bonus_earned, f.c.eco_gain_perfect_sort_bonus, EPS)

	# start() 同 cash_earned／components_earned 一樣，每次狂熱重新計
	# eco_bonus_earned（呢個 session 攞唔攞到），唔係疊加總數。
	f.tick(f.c.frenzy_cooldown_secs)
	f.start(0.0)
	f.register_lava_fall()
	f.tick(f.c.frenzy_duration_secs + 1.0)
	assert_almost_eq(f.eco_bonus_earned, 0.0, EPS, "跌咗一次呢個 session 唔應該攞到零掉坑花紅")


# ── 齒輪 ──────────────────────────────────────────────────

func test_gear_catch_requires_active_frenzy() -> void:
	assert_almost_eq(f.register_gear_catch(), 0.0, EPS)

func test_gear_catch_awards_component_reward() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	var gained := f.register_gear_catch()
	assert_almost_eq(gained, f.c.gear_component_reward, EPS)
	assert_almost_eq(f.components_earned, f.c.gear_component_reward, EPS)

func test_tick_emits_gear_spawn_event_on_interval() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	var events := f.tick(f.c.gear_drop_interval_secs)
	assert_true(events["gear_spawn"])
	var events2 := f.tick(f.c.gear_drop_interval_secs * 0.5)
	assert_false(events2["gear_spawn"])


# ── 幀數自動降級 ─────────────────────────────────────────

func test_sample_fps_ignored_when_not_active() -> void:
	f.sample_fps(1.0)
	assert_eq(f.debris_tier, 0)

func test_sample_fps_degrades_after_consecutive_low_streak() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	for i in range(f.c.frenzy_fps_low_streak_to_degrade - 1):
		f.sample_fps(f.c.frenzy_fps_low_threshold - 1.0)
	assert_eq(f.debris_tier, 0, "未夠連續次數唔應該降級")
	f.sample_fps(f.c.frenzy_fps_low_threshold - 1.0)
	assert_eq(f.debris_tier, 1)

func test_sample_fps_good_frame_resets_streak() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	f.sample_fps(f.c.frenzy_fps_low_threshold - 1.0)
	f.sample_fps(f.c.frenzy_fps_low_threshold + 10.0)
	assert_eq(f.fps_low_streak, 0)
	assert_eq(f.debris_tier, 0)

func test_current_debris_cap_follows_degrade_steps() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	assert_eq(f.current_debris_cap(), f.c.debris_rigidbody_cap)
	for i in range(f.c.frenzy_debris_degrade_steps.size()):
		for j in range(f.c.frenzy_fps_low_streak_to_degrade):
			f.sample_fps(0.0)
		assert_eq(f.current_debris_cap(), f.c.frenzy_debris_degrade_steps[i])

func test_is_fake_physics_true_once_tier_reaches_threshold() -> void:
	f.tick(f.c.frenzy_first_cooldown_secs)
	f.start(0.0)
	f.debris_tier = f.c.frenzy_fake_physics_min_tier - 1
	assert_false(f.is_fake_physics())
	f.debris_tier = f.c.frenzy_fake_physics_min_tier
	assert_true(f.is_fake_physics())

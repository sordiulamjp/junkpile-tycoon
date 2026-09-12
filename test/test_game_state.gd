extends GutTest

## VR-03：res://systems/game_state.gd 單元測試。
## 覆蓋：礦工召喚上限／扣費、三條升級線扣費同封頂（帶 Lv10）、
## 帶產能夾住礦工出礦（overflow）、精煉等級加成 Cash、
## 「已 belted 碎料不可 scoop」（pile_debris 同帶係獨立池）。

var s: GameState
const EPS := 0.001

func before_each() -> void:
	s = GameState.new()


# ── 開場資金（ALTA-150 實機回饋）───────────────────────────

func test_new_game_state_starts_with_starting_cash() -> void:
	assert_almost_eq(s.cash, s.c.starting_cash, EPS)
	assert_true(s.cash >= s.next_miner_cost(), "開場 Cash 應該即刻夠買第一個礦工")


# ── 礦工召喚 ─────────────────────────────────────────────

func test_summon_miner_fails_without_enough_cash() -> void:
	s.cash = 0.0 # 開場 Cash＝starting_cash（ALTA-150），呢度測嘅係「唔夠錢」個案，要手動夾低
	assert_false(s.summon_miner())
	assert_eq(s.miner_count, 0)

func test_summon_miner_charges_cost_and_increments_count() -> void:
	s.cash = s.next_miner_cost()
	assert_true(s.summon_miner())
	assert_eq(s.miner_count, 1)
	assert_almost_eq(s.cash, 0.0, EPS)

func test_summon_miner_stops_at_cap() -> void:
	s.cash = 1000000000.0
	for i in range(s.c.miner_summon_cap):
		assert_true(s.summon_miner())
	assert_eq(s.miner_count, s.c.miner_summon_cap)
	assert_false(s.can_summon_miner())
	assert_false(s.summon_miner())
	assert_eq(s.miner_count, s.c.miner_summon_cap)


# ── 三條升級線 ───────────────────────────────────────────

func test_upgrade_belt_increments_level_and_caps_at_ten() -> void:
	s.cash = 1000000000.0
	for i in range(s.c.belt_level_cap - 1):
		assert_true(s.upgrade_belt())
	assert_eq(s.belt_level, s.c.belt_level_cap)
	assert_false(s.can_upgrade_belt())
	assert_false(s.upgrade_belt())
	assert_eq(s.belt_level, s.c.belt_level_cap)

func test_upgrade_miner_level_has_no_cap() -> void:
	s.cash = 1000000000.0
	for i in range(50):
		assert_true(s.upgrade_miner_level())
	assert_eq(s.miner_level, 50)

func test_upgrade_refine_has_no_cap() -> void:
	# 精煉價曲線（×1.7／級）遠比礦工等級（×1.2／級）陡，一次過畀一舊
	# 大錢唔夠 50 級；逐級補錢先反映「無上限」係「有錢就升得」。
	for i in range(50):
		s.cash = s.next_refine_level_cost()
		assert_true(s.upgrade_refine())
	assert_eq(s.refine_level, 50)

func test_upgrades_fail_without_enough_cash() -> void:
	assert_false(s.upgrade_belt())
	assert_false(s.upgrade_miner_level())
	assert_false(s.upgrade_refine())
	assert_eq(s.belt_level, 1)
	assert_eq(s.miner_level, 0)
	assert_eq(s.refine_level, 0)


# ── 帶產能夾住礦工出礦 ──────────────────────────────────

func test_tick_feeds_all_when_under_belt_capacity() -> void:
	s.miner_count = 1
	var result := s.tick(1.0)
	assert_almost_eq(result["fed"], s.miner_ore_rate(), EPS)
	assert_almost_eq(result["overflow"], 0.0, EPS)

func test_tick_clamps_to_belt_capacity_and_reports_overflow() -> void:
	s.miner_count = 100 # 出礦量遠超 Lv1 帶產能上限
	var result := s.tick(1.0)
	assert_almost_eq(result["fed"], s.belt_capacity(), EPS)
	assert_gt(result["overflow"], 0.0)

func test_tick_increases_cash_and_eco() -> void:
	s.miner_count = 1
	s.cash = 0.0 # 開場 Cash＝starting_cash（ALTA-150），呢度淨係想測 tick() 本身有冇加錢
	s.tick(1.0)
	assert_gt(s.cash, 0.0)
	assert_gt(s.eco, 0.0)

func test_refine_level_multiplies_cash_gain() -> void:
	s.miner_count = 1
	var base: float = s.tick(1.0)["cash_gain"]
	s.cash = 1000000000.0
	s.refine_level = 0
	s.upgrade_refine()
	s.cash = 0.0
	var boosted: float = s.tick(1.0)["cash_gain"]
	assert_almost_eq(boosted, base * s.c.refine_value_mult, EPS)

func test_miner_level_multiplies_ore_rate() -> void:
	var base_rate := s.miner_ore_rate()
	s.miner_level = 3
	assert_almost_eq(s.miner_ore_rate(), base_rate * pow(s.c.miner_level_speed_mult, 3), EPS)


# ── 觸發嗰刻放置收入（VR-04 狂熱收益基準用）───────────────

func test_current_income_rate_is_zero_without_miners() -> void:
	assert_almost_eq(s.current_income_rate(), 0.0, EPS)

func test_current_income_rate_matches_steady_state_tick_rate() -> void:
	s.miner_count = 1
	var per_sec: float = s.tick(1.0)["cash_gain"]
	s.cash = 0.0
	assert_almost_eq(s.current_income_rate(), per_sec, EPS)

func test_current_income_rate_is_clamped_by_belt_capacity() -> void:
	s.miner_count = 100 # 出礦量遠超 Lv1 帶產能上限
	var expected: float = s.belt_capacity() * s.average_ore_value("foothill") * s.refine_multiplier()
	assert_almost_eq(s.current_income_rate(), expected, EPS)


# ── 手動 scoop：已 belted 碎料不可 scoop ────────────────

func test_scoop_first_on_empty_pile_is_zero() -> void:
	s.cash = 0.0 # 開場 Cash＝starting_cash（ALTA-150），呢度淨係想測空 pile 唔應該郁到 cash
	assert_almost_eq(s.scoop_first(), 0.0, EPS)
	assert_eq(s.cash, 0.0)

func test_spawn_pile_debris_then_scoop_first_credits_cash_and_drains_pile() -> void:
	s.cash = 0.0 # 開場 Cash＝starting_cash（ALTA-150），呢度想測 scoop 加嘅金額，夾低方便斷言
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ore_key := s.spawn_pile_debris(rng, "foothill")
	assert_eq(s.pile_debris.size(), 1)
	var expected_value: float = s.c.ore_tier_value[ore_key]
	var gained := s.scoop_first()
	assert_almost_eq(gained, expected_value, EPS)
	assert_almost_eq(s.cash, expected_value, EPS)
	assert_true(s.pile_debris.is_empty(), "剷咗之後個 pile 應該冇返呢粒")

func test_scoop_ore_removes_only_matching_entry() -> void:
	s.pile_debris = ["stone", "gold", "stone"]
	var gained := s.scoop_ore("gold")
	assert_almost_eq(gained, float(s.c.ore_tier_value["gold"]), EPS)
	assert_eq(s.pile_debris, ["stone", "stone"], "淨係走咗嗰粒 gold，兩粒 stone 應該留低")

func test_scoop_ore_missing_key_is_zero() -> void:
	s.pile_debris = ["stone"]
	assert_almost_eq(s.scoop_ore("crown"), 0.0, EPS)
	assert_eq(s.pile_debris, ["stone"])

func test_belted_ore_is_never_added_back_to_pile() -> void:
	# 已經入帶嘅份量（tick() 嘅 fed）由獨立管線兌 Cash，
	# 唔會加返落 pile_debris——即已 belted 碎料唔可能俾人 scoop 到。
	s.miner_count = 1
	for i in range(10):
		s.tick(0.5)
	assert_true(s.pile_debris.is_empty())

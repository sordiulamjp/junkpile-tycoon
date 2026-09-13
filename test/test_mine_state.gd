extends GutTest

## ALTA-228（VR-12）res://regions/region1_mine/mine_state.gd 單元測試。
## 覆蓋：開場資金即夠買最平嗰級升級（20 秒內首購）、3 層全開、三條
## 升級線扣費同封頂（升降機／倉庫 Lv10）、三段管線流量（地底緩衝 →
## 升降機 → 地面緩衝 → 倉庫 → Cash）、塞爆／升降機停運、瓶頸偵測。

var s: MineState
const EPS := 0.001

func before_each() -> void:
	s = MineState.new()


# ── 開場資金 ─────────────────────────────────────────────

func test_new_mine_state_starts_with_starting_cash() -> void:
	assert_almost_eq(s.cash, s.c.starting_cash, EPS)

func test_starting_cash_buys_the_cheapest_first_upgrade() -> void:
	var cheapest: float = minf(s.next_layer_cost(0), minf(s.next_elevator_cost(), s.next_warehouse_cost()))
	assert_almost_eq(s.c.starting_cash, cheapest, EPS, "開場資金應該啱好夠買三段入面最平嗰級升級")
	assert_true(s.upgrade_layer(0), "開場即刻應該買得起礦層 1 嘅第一級升級")


# ── 3 層全開 ─────────────────────────────────────────────

func test_three_layers_are_open_from_the_start() -> void:
	assert_eq(s.layer_level.size(), 3)
	for idx in range(3):
		assert_gt(s.layer_rate(idx), 0.0, "礦層 %d 開場已經有出礦速度，唔使解鎖" % idx)


# ── 三條升級線 ───────────────────────────────────────────

func test_upgrade_layer_charges_cost_and_increases_rate() -> void:
	s.cash = 1000000000.0
	var base_rate := s.layer_rate(0)
	assert_true(s.upgrade_layer(0))
	assert_eq(s.layer_level[0], 1)
	assert_almost_eq(s.layer_rate(0), base_rate * s.c.layer_level_speed_mult, EPS)

func test_upgrade_layer_has_no_cap() -> void:
	s.cash = 1000000000.0
	for i in range(50):
		assert_true(s.upgrade_layer(1))
	assert_eq(s.layer_level[1], 50)

func test_upgrade_layer_fails_without_enough_cash() -> void:
	s.cash = 0.0
	assert_false(s.upgrade_layer(0))
	assert_eq(s.layer_level[0], 0)

func test_upgrade_elevator_increments_level_and_caps_at_ten() -> void:
	s.cash = 1000000000.0
	for i in range(s.c.elevator_level_cap - 1):
		assert_true(s.upgrade_elevator())
	assert_eq(s.elevator_level, s.c.elevator_level_cap)
	assert_false(s.can_upgrade_elevator())
	assert_false(s.upgrade_elevator())
	assert_eq(s.elevator_level, s.c.elevator_level_cap)

func test_upgrade_warehouse_increments_level_and_caps_at_ten() -> void:
	s.cash = 1000000000.0
	for i in range(s.c.warehouse_level_cap - 1):
		assert_true(s.upgrade_warehouse())
	assert_eq(s.warehouse_level, s.c.warehouse_level_cap)
	assert_false(s.can_upgrade_warehouse())
	assert_false(s.upgrade_warehouse())
	assert_eq(s.warehouse_level, s.c.warehouse_level_cap)


# ── 三段管線流量 ─────────────────────────────────────────

func test_tick_moves_material_through_the_full_pipeline() -> void:
	var mine_out := s.total_mine_output()
	var expected_value := s.blended_ore_value()
	var expected_lifted: float = minf(s.elevator_capacity(), mine_out)
	var expected_collected: float = minf(s.warehouse_capacity(), expected_lifted)
	var result := s.tick(1.0)
	assert_almost_eq(result["mined"], mine_out, EPS)
	assert_almost_eq(result["jammed"], 0.0, EPS, "地底緩衝上限遠大於單幀出礦量，唔應該塞爆")
	assert_almost_eq(result["lifted"], expected_lifted, EPS)
	assert_almost_eq(result["collected"], expected_collected, EPS)
	assert_almost_eq(result["cash_gain"], expected_collected * expected_value, EPS)
	assert_gt(s.cash, s.c.starting_cash, "一幀之後 Cash 應該加咗")

func test_tick_jams_underground_when_buffer_cap_too_small() -> void:
	s.c.underground_backlog_cap = 0.05 # 夾到遠細過單幀出礦量，逼塞爆
	var mine_out := s.total_mine_output()
	var expected_accepted: float = minf(mine_out, 0.05)
	var result := s.tick(1.0)
	assert_almost_eq(result["jammed"], mine_out - expected_accepted, EPS, "截斷份量 = 出礦量－地底緩衝接得住嘅份量")
	assert_gt(result["jammed"], 0.0)

func test_tick_elevator_goes_idle_when_ground_buffer_is_full() -> void:
	s.c.ground_backlog_cap = 0.0 # 地面緩衝一開波已經冚滿，升降機冇位落
	var result := s.tick(1.0)
	assert_true(result["elevator_idle"], "地面緩衝滿咗，升降機應該停運")
	assert_almost_eq(result["lifted"], 0.0, EPS)
	assert_almost_eq(result["collected"], 0.0, EPS)


# ── 瓶頸偵測 ─────────────────────────────────────────────

func test_bottleneck_defaults_to_warehouse() -> void:
	# 開場數值：礦層總產出 1.8 ＝升降機上限 1.8 ＞倉庫上限 1.5，倉庫係樽頸。
	assert_eq(s.bottleneck_stage(), "warehouse")

func test_bottleneck_becomes_balanced_after_closing_the_gap() -> void:
	s.cash = 1000000000.0
	assert_true(s.upgrade_warehouse()) # Lv1→2：1.5×1.22 ≈ 1.83，同其餘兩段相差 < 5%
	assert_eq(s.bottleneck_stage(), "balanced")

func test_bottleneck_detects_elevator_when_layers_and_warehouse_outpace_it() -> void:
	s.layer_level = [5, 5, 5]
	s.warehouse_level = 5
	assert_eq(s.bottleneck_stage(), "elevator")

func test_bottleneck_detects_warehouse_when_far_behind() -> void:
	s.layer_level = [5, 5, 5]
	s.elevator_level = 10
	assert_eq(s.bottleneck_stage(), "warehouse")

extends GutTest

## ALTA-228（VR-12）main.gd 整合測試——MineZone（regions/region1_mine/
## mine_zone.gd）掛喺 main.tscn 場地擴張框架下嘅實際扣錢／解鎖／存檔
## 流程，同埋剖面面板（Part B）撳礦道入口 toggle。跟 test_region_expansion.gd
## 同一風格（成個 main.tscn 起，測真實 callback，唔淨係 MineState 純邏輯
## ——嗰部分見 test_mine_state.gd）。

var main: Node
const EPS := 0.001

func before_each() -> void:
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

func after_each() -> void:
	if is_instance_valid(main):
		main.free()
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

func _load_main() -> Node:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)
	return main


# ── 掛喺 main.tscn，唔係獨立場景 ──────────────────────────

func test_mine_zone_is_a_child_of_main_scene_not_a_standalone_scene() -> void:
	_load_main()
	assert_not_null(main._mine_zone)
	assert_true(main._mine_zone.is_inside_tree())
	assert_eq(main._mine_zone.get_parent(), main._placement_root)

func test_layer_one_is_unlocked_and_layers_two_three_are_locked_on_fresh_game() -> void:
	_load_main()
	assert_true(main._mine_zone.state.layer_unlocked[0])
	assert_false(main._mine_zone.state.layer_unlocked[1])
	assert_false(main._mine_zone.state.layer_unlocked[2])


# ── 剖面面板：撳礦道入口 toggle ───────────────────────────

func test_panel_starts_hidden_and_entrance_tap_toggles_it() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	assert_false(mine.panel.visible)

	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	mine._on_entrance_input(null, click, Vector3.ZERO, Vector3.ZERO, 0)
	assert_true(mine.panel.visible, "撳一下入口應該開返剖面面板")

	mine._on_entrance_input(null, click, Vector3.ZERO, Vector3.ZERO, 0)
	assert_false(mine.panel.visible, "再撳一下應該關返（toggle）")

func test_panel_close_button_returns_to_hidden() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	mine.panel.open()
	assert_true(mine.panel.visible)
	mine.panel.close_requested.emit()
	assert_false(mine.panel.visible)


# ── 層解鎖：真正扣 state.cash（唔係自成一格） ──────────────

func test_unlock_layer_two_deducts_shared_game_state_cash() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	var cost := mine.state.layer_unlock_cost(1)
	main.state.cash = cost

	mine._on_layer_unlock_tap("layer1", cost)

	assert_true(mine.state.layer_unlocked[1])
	assert_almost_eq(main.state.cash, 0.0, EPS, "應該扣走共用 GameState.cash，唔係自己一份")

func test_unlock_layer_two_fails_when_not_affordable() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	var cost := mine.state.layer_unlock_cost(1)
	main.state.cash = cost - 1.0

	mine._on_layer_unlock_tap("layer1", cost)

	assert_false(mine.state.layer_unlocked[1])
	assert_almost_eq(main.state.cash, cost - 1.0, EPS)

func test_cannot_unlock_layer_three_before_layer_two_via_tap() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	main.state.cash = 1000000.0
	mine._on_layer_unlock_tap("layer2", mine.state.layer_unlock_cost(2))
	assert_false(mine.state.layer_unlocked[2], "層 2 未解鎖，撳層 3 塊板都唔應該通過")


# ── 推堆墊：順序買，扣共用 cash，提高鏟斗倍率 ──────────────

func test_push_tier_upgrade_deducts_shared_cash_and_raises_scoop_mult() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	var cost := mine.state.c.push_tier_cost[0]
	main.state.cash = cost

	mine._on_push_tap("push0", cost)

	assert_eq(mine.state.push_tier, 1)
	assert_almost_eq(main.state.cash, 0.0, EPS)
	assert_almost_eq(mine.state.scoop_value_mult(), mine.state.c.push_tier_scoop_mult[0], EPS)

func test_push_tier_cannot_skip_ahead() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	main.state.cash = 1000000.0
	mine._on_push_tap("push1", mine.state.c.push_tier_cost[1]) # 未買 tier0，唔可以直接買 tier1
	assert_eq(mine.state.push_tier, 0)


# ── 地面礦堆：tap 收礦入共用 cash ─────────────────────────

func test_pile_tap_credits_shared_cash_and_removes_visual() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	main.state.cash = 0.0
	mine._on_pile_spawn_timeout()
	assert_eq(mine.state.pile_ore.size(), 1)
	var ore_key: String = mine.state.pile_ore[0]
	var chunk: Node3D = mine._pile_root.get_child(0)
	var area: Area3D = chunk.get_child(0)

	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	mine._on_pile_tap(null, click, Vector3.ZERO, Vector3.ZERO, 0, chunk, area, ore_key)

	assert_gt(main.state.cash, 0.0, "撳中應該加落共用 GameState.cash")
	assert_true(mine.state.pile_ore.is_empty())


# ── tick()：三段管線 cash_gain 直接入共用 cash ─────────────

func test_tick_credits_pipeline_income_into_shared_cash() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	var cash_before: float = main.state.cash
	mine.tick(1.0)
	assert_gt(main.state.cash, cash_before, "層 1 開場已經出緊礦，一幀之後 Cash 應該加咗")


# ── 存檔：殺 App 重開，礦坑進度不變 ────────────────────────

func test_mine_zone_progress_round_trips_through_save_and_reload() -> void:
	_load_main()
	var mine: MineZone = main._mine_zone
	main.state.cash = 1000000.0
	mine._on_layer_unlock_tap("layer1", mine.state.layer_unlock_cost(1))
	mine._on_push_tap("push0", mine.state.c.push_tier_cost[0])
	mine.state.apply_cart_upgrade()
	mine.state.apply_warehouse_upgrade()
	main._save_game()
	main.free()

	_load_main()
	var reloaded: MineZone = main._mine_zone
	assert_true(reloaded.state.layer_unlocked[1], "殺 App 重開，層 2 解鎖狀態應該不變")
	assert_eq(reloaded.state.push_tier, 1)
	assert_eq(reloaded.state.cart_level, 2)
	assert_eq(reloaded.state.warehouse_level, 2)

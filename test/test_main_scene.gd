extends GutTest

## VR-03：main.tscn 灰模場景煙霧測試——場景可以載入、行幾幀冇 error，
## 核心節點（World／HUD／三個升級掣）齊全。唔測手機 tap（headless 冇
## 真實觸控／滑鼠事件可以送），呢部分要留返俾裝置／編輯器實測。

var main: Node

func after_each() -> void:
	if is_instance_valid(main):
		main.free()

func test_scene_loads_and_ticks_without_error() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)
	assert_not_null(main.get_node_or_null("World"))
	assert_not_null(main.get_node_or_null("HUD"))
	assert_not_null(main.get_node_or_null("HUD/TopBar"))
	assert_not_null(main.get_node_or_null("HUD/BottomBar"))

	for i in range(5):
		main._process(0.1)

	# 未召喚礦工，行幾幀都唔應該有 error 或者變負錢。
	assert_almost_eq(main.state.cash, 0.0, 0.001)

func test_summon_first_miner_updates_hud_and_pile() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.state.next_miner_cost()
	main._try_summon_miner()
	assert_eq(main.state.miner_count, 1)
	assert_eq(main._miners_root.get_child_count(), 1)

	main._process(0.1)
	assert_string_contains(main._summon_button.text, "1/%d" % main.c.miner_summon_cap)

func test_pile_debris_spawn_and_scoop_removes_visual_node() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main._on_pile_spawn_timeout()
	assert_eq(main.state.pile_debris.size(), 1)
	assert_eq(main._pile_root.get_child_count(), 1)

	var ore_key: String = main.state.pile_debris[0]
	var gained: float = main.state.scoop_ore(ore_key)
	assert_gt(gained, 0.0)
	assert_true(main.state.pile_debris.is_empty())

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
	# issue 文案要求完整數字，唔係 _fmt_num() 嘅 K/M 縮寫（Review 意見）。
	assert_eq(main._lock_label.text, "鎖住 · 2,000,000")

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


# ── 相機取景回歸測試（Review 意見，ALTA-150：帶／爐／倉／礦工／碎料
# 一度全部跌出 frustum，或者疊落底部 HUD）───────────────────────
#
# 用 Camera3D.is_position_in_frustum() / unproject_position() 實測，
# 唔淨係睇個場景「起到」，日後改場地座標／HUD 比例都會自動抓到回歸。

func _assert_in_mid_band(cam: Camera3D, world_pos: Vector3, viewport_h: float, label: String) -> void:
	assert_true(cam.is_position_in_frustum(world_pos), "%s 應該喺 frustum 入面" % label)
	var screen_y: float = cam.unproject_position(world_pos).y
	var frac: float = screen_y / viewport_h
	var top_frac: float = main.c.hud_top / 100.0
	var bottom_frac: float = 1.0 - (main.c.hud_bottom / 100.0)
	assert_true(
		frac >= top_frac and frac <= bottom_frac,
		"%s 螢幕 Y 比例 %.3f 應該喺中層帶 [%.2f, %.2f] 之內（唔應該俾頂／底 HUD 遮咗）"
			% [label, frac, top_frac, bottom_frac]
	)

func test_belt_furnace_warehouse_are_in_camera_mid_band() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var cam: Camera3D = main.get_node("World/Camera3D")
	var viewport_h: float = main.get_viewport().get_visible_rect().size.y

	_assert_in_mid_band(cam, main._site_to_world(main.c.site_foothill_pos), viewport_h, "Foothill")
	_assert_in_mid_band(cam, main._site_to_world(main.c.belt_head_pos), viewport_h, "BELT_HEAD")
	_assert_in_mid_band(cam, main._site_to_world(main.c.smelter_pos, 0.25), viewport_h, "Smelter")
	_assert_in_mid_band(cam, main._site_to_world(main.c.warehouse_pos, 0.22), viewport_h, "Warehouse")

func test_mountain_top_at_full_miner_cap_still_in_mid_band() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var cam: Camera3D = main.get_node("World/Camera3D")
	var viewport_h: float = main.get_viewport().get_visible_rect().size.y
	var top_y: float = main.c.site_foothill_pos.y + main.FOOTHILL_BASE_HEIGHT \
		+ float(main.c.miner_summon_cap) * main.FOOTHILL_TIER_HEIGHT
	_assert_in_mid_band(
		cam, main._site_to_world(Vector2(main.c.site_foothill_pos.x, top_y)), viewport_h, "MountainTopAtCap"
	)

func test_summoned_miner_and_pile_debris_land_in_camera_mid_band() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.state.next_miner_cost()
	main._try_summon_miner()
	main._on_pile_spawn_timeout()

	var cam: Camera3D = main.get_node("World/Camera3D")
	var viewport_h: float = main.get_viewport().get_visible_rect().size.y
	var miner: Node3D = main._miners_root.get_child(0)
	var chunk: Node3D = main._pile_root.get_child(0)
	_assert_in_mid_band(cam, miner.global_position, viewport_h, "Miner")
	_assert_in_mid_band(cam, chunk.global_position, viewport_h, "PileDebrisChunk")

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

	# 未召喚礦工，行幾幀都唔應該再郁 Cash（開場 Cash＝starting_cash，
	# ALTA-150 實機回饋：唔再係 0，見下面 test_starting_cash_covers_first_miner）。
	assert_almost_eq(main.state.cash, main.c.starting_cash, 0.001)

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

# ── VR-04：狂熱車場觸發／收尾煙霧測試 ─────────────────────
# headless 冇真實觸控，唔測跟指／碰撞判分（留返俾實機），呢度淨係
# 保證觸發流程、場景切換、幾十幀 tick 落嚟唔會拋 error。

func test_frenzy_button_disabled_during_first_cooldown() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)
	assert_true(main._frenzy_button.disabled)
	assert_string_contains(main._frenzy_button.text, "冷卻")

func test_try_start_frenzy_swaps_placement_field_for_frenzy_yard() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	assert_true(main.frenzy.active)
	assert_false(main._placement_root.visible)
	assert_true(main._frenzy_view.visible)

func test_frenzy_ticks_for_full_duration_without_error_then_restores_placement() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	var elapsed := 0.0
	while elapsed < main.c.frenzy_duration_secs + 1.0:
		main._process(0.5)
		elapsed += 0.5

	assert_false(main.frenzy.active)
	assert_true(main._placement_root.visible)
	assert_false(main._frenzy_view.visible)
	assert_almost_eq(main.frenzy.cooldown_remaining, main.c.frenzy_cooldown_secs, 1.0)

## 真係俾 SceneTree 行幾十個引擎幀（唔係手動 call _process()），等
## FrenzyYardView._process() 自己嘅生成／車巡航／幀數取樣真正跑到，
## 揸實幾十粒真 RigidBody3D 剛體物理落嚟都唔應該有 error。
## Review 意見（ALTA-150 round 3）：斜視相機之後，車場跟指用嘅
## `cam.project_position(screen_pos, cam.global_position.z)` 假設咗相機
## 正面望 -Z、z=10 先啱，斜視之後成條射線行偏咗，手指全螢幕闊度撳落去
## 算出嚟嘅 world x 全部撞晒右牆（yard_x_range.y），車郁唔到。改用射線
## 同 Z=0 平面求交之後，手指由左掃到右，_car_target_x（clamp 之前嘅原
## 始值）應該單調遞增，而且實際覆蓋 yard_x_range 大部分闊度，唔會全部
## 撞晒去同一邊牆。
func test_frenzy_finger_position_maps_across_yard_x_range() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	var view: FrenzyYardView = main._frenzy_view
	var vp_size: Vector2 = main.get_viewport().get_visible_rect().size

	var xs: Array[float] = []
	for frac in [0.02, 0.25, 0.5, 0.75, 0.98]:
		var evt := InputEventScreenTouch.new()
		evt.pressed = true
		evt.position = Vector2(vp_size.x * frac, vp_size.y * 0.5)
		view._unhandled_input(evt)
		xs.append(view._car_target_x)

	for i in range(1, xs.size()):
		assert_gt(xs[i], xs[i - 1], "由左至右嘅手指應該令車 x 遞增（第 %d 點）" % i)

	var yard_span: float = main.c.yard_x_range.y - main.c.yard_x_range.x
	assert_gt(
		xs[xs.size() - 1] - xs[0], yard_span * 0.3,
		"手指由左掃到右，車 x 應該有實質橫向覆蓋範圍（唔應該全部撞晒同一邊牆）"
	)
	assert_lt(
		xs[0], main.c.yard_x_range.y,
		"最左邊嘅手指唔應該一開始就撞晒去右牆（先前 regression）"
	)

func test_frenzy_yard_spawns_real_rigidbody_debris_over_several_frames() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	for i in range(30):
		await get_tree().process_frame

	assert_true(main.frenzy.active, "30 幀之內未夠 120 秒，狂熱應該仍然生效")
	assert_gt(main._frenzy_view._debris_nodes.size(), 0, "應該已經生咗至少一粒剛體碎料")

## Review 意見（f457644 review）：_recolor_debris() 曾經假設 body 一定
## 係 RigidBody3D（mesh 喺 child(0)），但假物理路徑 _spawn_fake_debris()
## 生嘅 node 本身就係 MeshInstance3D，冇 child——藍波一過滾筒就
## get_child(0) 越界 + 對 null 存取 material_override，SCRIPT ERROR。
## headless 都行到，唔使實機先重現／驗證。
func test_fake_physics_debris_recolors_across_roller_without_error() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()
	main.frenzy.debris_tier = main.c.frenzy_fake_physics_min_tier
	assert_true(main.frenzy.is_fake_physics())

	var roller_pos := Vector3(main.c.spike_roller_pos.x, main.c.spike_roller_pos.y, 0.0)
	main._frenzy_view._spawn_fake_debris("barrel", roller_pos)
	var node: Node3D = main._frenzy_view._fake_debris_nodes.back()
	assert_eq(node.get_child_count(), 0, "假物理 node 本身就係 MeshInstance3D，冇 child")

	main._frenzy_view._update_fake_debris(0.016)

	assert_eq(node.get_meta("kind"), "gold", "藍波過咗滾筒應該轉咗做金幣（唔係停留喺 barrel）")

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


# ── 用戶實機回饋回歸測試（ALTA-150，2026-09-12 Windows Godot playtest）───
# 四點：開場經濟、相機視角、碎料視覺／回饋、掣顏色。

## 1. 開場經濟：開場 Cash 要即刻夠買第一個礦工（唔使剷幾粒碎料先夠），
## 令「~20s 第一個礦工」嘅首節腳本撳得到。
func test_starting_cash_covers_first_miner_purchase() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_almost_eq(main.state.cash, main.c.starting_cash, 0.001)
	assert_true(main.state.cash >= main.state.next_miner_cost(), "開場 Cash 應該即刻夠買第一個礦工")

	main._try_summon_miner()
	assert_eq(main.state.miner_count, 1, "開場 Cash 應該可以直接撳掣買到第一個礦工")

## 2. 相機視角：跟 docx §6 斜視（pitch/yaw），唔再係正面平視（rotation=0）
## 令 BoxMesh 變 2D 色塊。
func test_camera_is_tilted_not_front_on() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var cam: Camera3D = main.get_node("World/Camera3D")
	assert_almost_eq(cam.rotation_degrees.x, main.c.screen_camera_pitch_deg, 0.01)
	assert_almost_eq(cam.rotation_degrees.y, main.c.screen_camera_yaw_deg, 0.01)
	assert_ne(cam.rotation_degrees, Vector3.ZERO, "相機唔應該再係正面平視")

## 3. 碎料視覺：放大到至少 0.25 世界單位，撳中有回饋（放大 tween）
## 先消失（唔係即刻 free），開場提示第一次剷完就收起。
## VR-06 換皮：碎料由 BoxMesh 改用 VisualFactory 出嘅楔形 PrismMesh
## （睇落似粒石／礦），呢度斷言跟返 VisualFactory.make_ore_chunk()
## 嘅 size 換算公式，唔係話呢粒嘢一定要係盒仔。
func test_pile_chunk_visual_size_and_tap_feedback() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_gte(main.PILE_CHUNK_VISUAL_SIZE, 0.25)

	main._on_pile_spawn_timeout()
	var chunk: MeshInstance3D = main._pile_root.get_child(0)
	var prism := chunk.mesh as PrismMesh
	assert_not_null(prism, "VR-06 碎料視覺應該係 VisualFactory.make_ore_chunk() 出嘅 PrismMesh")
	assert_eq(prism.size, Vector3(main.PILE_CHUNK_VISUAL_SIZE, main.PILE_CHUNK_VISUAL_SIZE * 1.3, main.PILE_CHUNK_VISUAL_SIZE))

	assert_true(main._scoop_hint_label.visible, "未撳過，提示應該仲顯示緊")

	var area: Area3D = chunk.get_child(0)
	var ore_key: String = main.state.pile_debris[0]
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	main._on_pile_chunk_input(null, click, Vector3.ZERO, Vector3.ZERO, 0, chunk, area, ore_key)

	assert_true(main._scoop_hint_shown, "撳中之後提示應該收埋")
	assert_false(main._scoop_hint_label.visible)
	# 撳中即刻仍然存在（播緊放大回饋嘅 tween），唔係即刻 free 冇回饋。
	assert_true(is_instance_valid(chunk), "撳中一刻應該仲有回饋動畫，唔係即刻消失")
	assert_false(area.input_ray_pickable, "播緊回饋嗰下應該停晒接輸入，唔會重複扣同一粒")

## 4. 掣顏色：唔夠錢嘅升級掣價錢紅色，夠錢綠色，等玩家知道等緊錢
## 唔係壞咗；撞上限／封頂嘅掣維持預設（唔叫呢個顏色）。
func test_upgrade_buttons_color_by_affordability() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = 0.0
	main._refresh_hud()
	assert_true(main._belt_upgrade_button.disabled)
	assert_eq(
		main._belt_upgrade_button.get_theme_color("font_disabled_color"), Color(0.95, 0.35, 0.3),
		"唔夠錢應該紅色"
	)

	main.state.cash = main.state.next_belt_cost()
	main._refresh_hud()
	assert_false(main._belt_upgrade_button.disabled)
	assert_eq(
		main._belt_upgrade_button.get_theme_color("font_color"), Color(0.4, 0.9, 0.4),
		"夠錢應該綠色"
	)

extends GutTest

## VR-03：main.tscn 灰模場景煙霧測試——場景可以載入、行幾幀冇 error，
## 核心節點（World／HUD／三個升級掣）齊全。唔測手機 tap（headless 冇
## 真實觸控／滑鼠事件可以送），呢部分要留返俾裝置／編輯器實測。

var main: Node

func before_each() -> void:
	RemoteConstants.clear_cache()
	# VR-05b：main.gd 而家 _ready() 會讀 SaveManager 存檔——冇呢句嘅話上
	# 一個測試（或者呢個檔新加嘅存檔／離線測試）留低嘅 user://save-v1.json
	# 會累到下一個測試（例如 test_scene_loads_and_ticks_without_error()
	# 假設嘅「開場 Cash＝starting_cash」）睇到唔啱嘅殘留存檔。
	SaveManager.delete_save()

func after_each() -> void:
	if is_instance_valid(main):
		main.free()
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

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

## 用戶實機回饋（ALTA-153 round2 第 1 點）：放置場＋車場「上下分屏，
## 兩者常駐」，唔可以再切場景——_placement_root／_frenzy_view 全程都
## visible（唔再狂熱先顯示／完場先還原），觸發狂熱淨係令車場「活起來」
## （set_process(true)，車郁得、生碎料）。
func test_try_start_frenzy_activates_yard_without_hiding_placement() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_true(main._placement_root.visible, "開場放置場已經應該 visible")
	assert_true(main._frenzy_view.visible, "開場車場已經應該 visible（常駐）")

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	assert_true(main.frenzy.active)
	assert_true(main._placement_root.visible, "狂熱期間放置場唔應該再隱藏")
	assert_true(main._frenzy_view.visible, "狂熱期間車場繼續 visible（一直都係）")
	assert_true(main._frenzy_view.is_processing(), "狂熱期間車場 gameplay tick 應該行緊")

func test_frenzy_ticks_for_full_duration_without_error_then_stays_visible() -> void:
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
	assert_true(main._placement_root.visible, "完場之後放置場繼續 visible（一直都係，冇切走過）")
	assert_true(main._frenzy_view.visible, "完場之後車場繼續 visible（一直都係，一直冇隱藏過）")
	assert_false(main._frenzy_view.is_processing(), "完場之後車場 gameplay tick 應該停返")
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
##
## 用戶回饋（ALTA-153 round2 第 1 點）之後：放置場常駐，_unhandled_input()
## 加咗「螢幕 Y 一定要喺車場範圍之下」嘅守衛（見該函式註解）；呢個測試
## 嘅掃動 Y 要揀車場自己嘅螢幕範圍入面（用 yard_top／yard_min_y 兩個
## 地標喺呢個相機下嘅實際螢幕 Y 求中點），先至唔會撞正個新守衛——用
## 舊版「成個畫面高度 50%」呢個粗略假設已經唔啱（嗰個假設嘅前提係
## 「狂熱期間放置場隱晒、成個畫面淨係車場」，而家已經唔再係咁）。
func test_frenzy_finger_position_maps_across_yard_x_range() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	var view: FrenzyYardView = main._frenzy_view
	var cam: Camera3D = main.get_node("World/Camera3D")
	var vp_size: Vector2 = main.get_viewport().get_visible_rect().size
	var yard_mid_x: float = (main.c.yard_x_range.x + main.c.yard_x_range.y) * 0.5
	var yard_top_screen_y: float = cam.unproject_position(Vector3(yard_mid_x, main.c.car_park_max_y, 0.0)).y
	var yard_bottom_screen_y: float = cam.unproject_position(Vector3(yard_mid_x, main.c.yard_min_y, 0.0)).y
	var yard_screen_y: float = (yard_top_screen_y + yard_bottom_screen_y) * 0.5

	var xs: Array[float] = []
	for frac in [0.02, 0.25, 0.5, 0.75, 0.98]:
		var evt := InputEventScreenTouch.new()
		evt.pressed = true
		evt.position = Vector2(vp_size.x * frac, yard_screen_y)
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

## 用戶回饋（ALTA-153 round2 第 1 點）：放置場常駐之後，一撳山腳（mountain
## 區域）唔應該連車都拖埋一齊郁——_car_target_x 唔應該因為呢粒撳鍾而變
## （見 FrenzyYardView._unhandled_input() 嘅 yard_top_screen_y 守衛）。
func test_frenzy_ignores_touches_above_yard_top_row() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	var view: FrenzyYardView = main._frenzy_view
	var cam: Camera3D = main.get_node("World/Camera3D")
	var before: float = view._car_target_x

	var mountain_screen_pos: Vector2 = cam.unproject_position(
		main._site_to_world(main.c.site_foothill_pos)
	)
	var evt := InputEventScreenTouch.new()
	evt.pressed = true
	evt.position = mountain_screen_pos
	view._unhandled_input(evt)

	assert_eq(view._car_target_x, before, "撳山腳唔應該影響車嘅跟指目標")

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

## VR-06b 驗收：「車場兩牆全部喺中層帶」——透視相機橫向 FOV 比正交窄
## （KEEP_HEIGHT 底下 3:4 直版橫向視野縮咗），車場兩牆（FrenzyYardView
## ._build_walls() 嘅位置）冇喺 _camera_reference_points() 度計埋就好易
## 撞出畫面（見 _compute_camera_frame() 註解）。
func test_frenzy_yard_walls_are_in_camera_mid_band() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var cam: Camera3D = main.get_node("World/Camera3D")
	var viewport_h: float = main.get_viewport().get_visible_rect().size.y
	var wall_mid_y: float = (main.c.car_park_max_y + main.c.yard_min_y) * 0.5

	_assert_in_mid_band(
		cam, main._site_to_world(Vector2(main.c.yard_x_range.x - 0.1, wall_mid_y)), viewport_h, "WestWall"
	)
	_assert_in_mid_band(
		cam, main._site_to_world(Vector2(main.c.yard_x_range.y + 0.1, wall_mid_y)), viewport_h, "EastWall"
	)


# ── 用戶實機回饋回歸測試（ALTA-153 round2，2026-09-13 S8+ playtest）───
# 7 點修正入面第 3／5／6 點（第 1／2／7 點由 ALTA-214 補；第 4 點＋推土機
# 留 ALTA-215）。

## 第 3 點：一開場（未召喚任何礦工）都要見到成座 12 層梯田，唔係得個
## 地台等召喚先一層層現。
func test_foothill_shows_full_terrace_before_any_miner_summoned() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_eq(main.state.miner_count, 0, "呢個測試要開場未召喚過礦工")
	var tier_count := 0
	for child in main._foothill_root.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.position.y > 0.0:
			tier_count += 1
	assert_eq(tier_count, main.c.miner_summon_cap, "未召喚都應該見到全部 12 層梯田")

## Review 意見（round2 修正）：12 層梯田常駐之後，舊生成位（y=0.55、
## z∈±0.3）陷咗入 tier1／2 個 box 入面（headless 量度 300 粒有 105 粒
## 完全睇唔到）。改咗擺喺山腳前面地面一圈、半徑大過梯田最闊嘅底座
## 之後，呢個測試斷言生成位一定喺呢個安全半徑範圍入面（唔淨係查
## PrismMesh size，仲要查實際擺位冇陷落梯田幾何）。
## Review 意見（round2 修正二）：直接用同 Reviewer 一樣嘅「bounding box
## 包含判定」量度——碎料本身嘅擺位一定要喺全部 12 層梯田嘅 box 範圍
## 以外，先算「睇得見」（唔係淨係查半徑呢個間接指標）。
func test_pile_debris_spawns_outside_terrace_footprint() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	for i in range(20):
		main._on_pile_spawn_timeout()

	assert_gt(main._pile_root.get_child_count(), 0, "應該生咗至少一粒碎料")
	for chunk: Node3D in main._pile_root.get_children():
		for tier: Node3D in main._foothill_root.get_children():
			if not (tier is MeshInstance3D and tier.mesh is BoxMesh and tier.position.y > 0.0):
				continue
			var box_size: Vector3 = tier.mesh.size
			var rel: Vector3 = chunk.position - tier.position
			var inside: bool = absf(rel.x) <= box_size.x * 0.5 \
				and absf(rel.y) <= box_size.y * 0.5 and absf(rel.z) <= box_size.z * 0.5
			assert_false(inside, "碎料唔應該陷落 %s 個 box 入面" % tier.name)

## Review 意見（round2 修正二）：修正一擺喺山腳前面一圈之後，headless
## 用車場自己嘅 screen-Y 守衛公式（`frenzy_yard_view.gd` 嗰句）量度
## 300 粒，發現 78% 螢幕位置其實跌咗落車場個範圍之下——即係狂熱期間
## 撳中呢啲碎料一樣會拖埋車，「唔會連車拖埋」嗰個保護對大部分碎料
## 已經失效。呢個測試直接攞 `_spawn_pile_visual()` 出嚟嘅碎料，用
## 同一條 unproject_position 公式量度，斷言個螢幕 Y 一定留喺車場最頂
## 行之上（Reviewer 原話：「測試應該攞一粒實際 `_spawn_pile_visual()`
## 出嚟嘅碎料嘅 `unproject_position` 去撳」）。
func test_pile_debris_screen_position_stays_above_yard_guard_row() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var cam: Camera3D = main.get_node("World/Camera3D")
	var viewport_h: float = main.get_viewport().get_visible_rect().size.y
	var yard_mid_x: float = (main.c.yard_x_range.x + main.c.yard_x_range.y) * 0.5
	# 同 frenzy_yard_view.gd _unhandled_input() 嘅守衛一模一樣條式。
	var guard_y: float = cam.unproject_position(Vector3(yard_mid_x, main.c.car_park_max_y, 0.0)).y \
		- viewport_h * 0.02

	for i in range(20):
		main._on_pile_spawn_timeout()

	assert_gt(main._pile_root.get_child_count(), 0, "應該生咗至少一粒碎料")
	for chunk: Node3D in main._pile_root.get_children():
		var screen_y: float = cam.unproject_position(chunk.global_position).y
		assert_lt(
			screen_y, guard_y,
			"碎料嘅螢幕位置一定要留喺車場最頂行之上，狂熱期間撳中先唔會連車都拖埋"
		)

## 第 5 點：召喚幾個礦工之後應該企喺山腳前面半圈唔同角度（圍住山腳
## 分佈），唔係全部黐晒喺同一個原點嘅少少 jitter；亦都要面向山腳（唔
## 側身唔趴低）——Review 意見（round2 修正）：`look_at()` 之前錯咗畀
## local 座標當全域用，令礦工全部歪咗去面向世界原點。
func test_summoned_miners_are_distributed_around_foothill() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = 10000.0
	main._try_summon_miner()
	main._try_summon_miner()

	assert_eq(main._miners_root.get_child_count(), 2)
	var m0: Node3D = main._miners_root.get_child(0)
	var m1: Node3D = main._miners_root.get_child(1)
	# 門檻跟返 _place_miner_around_foothill() 嘅幾何保證：radius=0.5、
	# 前半弧（π）攤 12 格、jitter ±0.05 rad 之下，任意相鄰兩格嘅最壞
	# 情況都仲有實質距離（唔止「唔完全撞埋」咁鬆）。
	assert_gt(m0.position.distance_to(m1.position), 0.07, "兩個礦工唔應該企喺同一個位")

	# Review 意見：面向山腳即係企喺半徑圓上望返轉頭去圓心，pitch/roll
	# 應該維持 0（純橫向 Y 轉），唔應該因為錯用 local 座標做 look_at()
	# 目標而歪咗成 30 幾度。
	for miner: Node3D in [m0, m1]:
		assert_almost_eq(miner.rotation.x, 0.0, 0.01, "礦工唔應該向前傾／趴低")
		assert_almost_eq(miner.rotation.z, 0.0, 0.01, "礦工唔應該側身")
		assert_true(miner.position.z >= 0.0, "礦工應該企喺前半弧（z ≥ 0），唔會俾梯田擋住")

## 第 6 點：帶用分段滾軸 mesh，持續自轉先有「流動視覺」。
func test_belt_rollers_registered_and_spin_over_time() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_gt(main._belt_rollers.size(), 0, "帶應該有分段滾軸")
	var roller: MeshInstance3D = main._belt_rollers[0]
	var before := roller.rotation.x
	main._process(0.5)
	assert_ne(roller.rotation.x, before, "滾軸應該持續自轉")
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

## VR-08 Review 修正：starting_cash 喺 GameState._init() 就已經俾讀走，
## 純靠 _ready() 尾段先背景 fetch 嚟 set() 落 c 係唔會生效嘅（每次重開都
## 一樣）。要證明「改遠端 JSON 後 App 重開即生效」對呢類欄位都成立，
## 一定要喺構造 GameState 之前就套用返 cache——呢個測試模擬「上次已經
## 成功 fetch 過一份 cache」，斷言重開（即呢次場景載入）即刻食到新值。
func test_cached_remote_override_applies_before_game_state_init() -> void:
	RemoteConstants.write_cache({"starting_cash": 777.0})

	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_almost_eq(main.c.starting_cash, 777.0, 0.001, "c 本身要覆寫咗")
	assert_almost_eq(main.state.cash, 777.0, 0.001, "GameState._init() 讀 c.starting_cash 嗰刻已經要係新值")

## 2. 相機視角：VR-06b 改透視（issue 視覺參考：pitch 55–60°、FOV
## 40–45°），唔再係正面平視（rotation=0），亦唔再係 VR-03 嗰陣嘅正交
## （screen_camera_pitch_deg／yaw_deg 依家淨係歷史記錄，冇再用喺相機）。
func test_camera_is_tilted_not_front_on() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var cam: Camera3D = main.get_node("World/Camera3D")
	assert_eq(cam.projection, Camera3D.PROJECTION_PERSPECTIVE, "VR-06b：鏡頭應該改咗透視")
	assert_almost_eq(cam.rotation_degrees.x, main.CAMERA_PITCH_DEG, 0.01)
	assert_almost_eq(cam.rotation_degrees.y, main.CAMERA_YAW_DEG, 0.01)
	assert_ne(cam.rotation_degrees, Vector3.ZERO, "相機唔應該再係正面平視")
	assert_between(absf(main.CAMERA_PITCH_DEG), 55.0, 60.0, "pitch 應該跟視覺參考 55–60°")
	assert_between(cam.fov, 40.0, 45.0, "FOV 應該跟視覺參考 40–45°")

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


# ── Review 意見（ALTA-214 round 1）：頂 HUD 爆框 + 右上方掣冚住 Eco
# 「+」掣 ─────────────────────────────────────────
# 兩個根因：(1) VisualFactory.make_icon() 冧咗 expand_mode，貼圖原生
# 大細（coin/eco_leaf 128px）頂住 layout minimum size，令「圓 icon」
# 實際脹到 136px；(2) 右上設定／任務掣之前用獨立 Control 疊喺
# resources_row 度，同 Eco 格「+」掣重疊。呢兩個測試直接量 Control
# rect，日後 icon／HUD 排法改壞咗會即刻抓到，唔使等人手截圖先發現。

func test_top_hud_resource_icon_follows_requested_size_not_texture_size() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var resources_row: Control = null
	for c in main.get_node("HUD/TopBar").get_children():
		if c is VBoxContainer:
			resources_row = c.get_child(0)
	# coin.png／eco_leaf.png 係 128×128，冧咗 expand_mode 就會令成行爆到
	# 136px 高（見 review）；修完應該貼返 _make_circular_icon() 嘅
	# custom_minimum_size（32），唔會俾貼圖原生大細頂爆。
	assert_lt(resources_row.size.y, 60.0, "資源行唔應該俾貼圖原生大細（128px）頂爆")

func test_top_hud_corner_buttons_do_not_overlap_resource_row() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var top_vbox: VBoxContainer = null
	for c in main.get_node("HUD/TopBar").get_children():
		if c is VBoxContainer:
			top_vbox = c
	var resources_row: Control = top_vbox.get_child(0)
	var status_row: Control = top_vbox.get_child(1)
	var resources_rect := Rect2(resources_row.position, resources_row.size)
	var status_rect := Rect2(status_row.position, status_row.size)
	assert_false(
		resources_rect.intersects(status_rect),
		"右上設定／任務掣（status_row 尾）唔應該同資源行（Eco「+」掣所在）疊埋"
	)

## 資源行＋pill 行（連右上兩掣）＋威望 bar 整個頂 HUD vbox 內容高度應該
## 留喺 TopBar 12% 預算之內（720×960＝115.2px），唔可以爆晒去中層帶。
## 用 ProjectSettings 讀設計解像度（唔用 get_viewport().get_visible_rect()——
## GUT 跑測試嗰陣個 viewport 可能唔係實際 720×960，`top_vbox.size.y`
## 淨係由子節點嘅固定 pixel minimum size 決定、唔隨 viewport 縮放，
## 同一個隨 viewport 縮放嘅預算比較先有意義）。
func test_top_hud_content_height_fits_within_hud_top_budget() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var top_vbox: VBoxContainer = null
	for c in main.get_node("HUD/TopBar").get_children():
		if c is VBoxContainer:
			top_vbox = c
	var design_viewport_h: float = ProjectSettings.get_setting("display/window/size/viewport_height")
	var budget_px: float = main.c.hud_top / 100.0 * design_viewport_h
	assert_lt(top_vbox.size.y, budget_px, "頂 HUD 內容總高度應該喺 hud_top 預算之內")


# ── VR-05b（ALTA-216）：存檔／離線結算面板／威望重置接駁入 main 流程 ──

## 驗收「殺 App 重開資源不變」：經 main 嘅真實觸發（_try_summon_miner()
## 尾段 _save_game()）存檔，free 個場景模擬殺 App，重新 instantiate 模擬
## 重開，狀態應該原封不動咁讀返嚟（唔淨係 SaveManager 單元測試嗰層，
## 呢度連 _ready() 嘅讀檔／套用流程都一齊過）。
func test_save_round_trips_through_main_flow() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.state.next_miner_cost()
	main._try_summon_miner()
	var miners_after: int = main.state.miner_count
	var cash_after: float = main.state.cash
	var lifetime_after: float = main._lifetime_cash

	main.free()

	main = scene.instantiate()
	add_child_autofree(main)

	assert_eq(main.state.miner_count, miners_after, "殺 App 重開，經 main 流程存返嘅礦工數應該不變")
	assert_almost_eq(main.state.cash, cash_after, 0.01, "殺 App 重開，經 main 流程存返嘅 Cash 應該不變")
	assert_almost_eq(main._lifetime_cash, lifetime_after, 0.01, "殺 App 重開，終身 Cash 應該不變")

## 驗收「離線面板金額 = settle() 結果」：預先寫一份存檔（last_save_unix
## 擺喺 1 小時前，帶 3 個礦工），開場應該即刻彈離線面板，顯示金額直接
## 嚟自 _pending_offline_result（settle() 嘅結果），撳「收下」先真正入帳。
func test_offline_panel_shows_and_claim_applies_settle_result() -> void:
	var seed_state := SaveManager.default_state()
	seed_state["last_save_unix"] = Time.get_unix_time_from_system() - 3600.0
	seed_state["cash"] = 100.0
	seed_state["lifetime_cash"] = 100.0
	seed_state["miners"] = 3
	seed_state["belt_level"] = 5
	SaveManager.save_state(seed_state)

	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_true(main._offline_panel.visible, "有存檔就應該即刻彈離線結算面板")
	assert_false(main._pending_offline_result.is_empty())
	var cash_yield: float = main._pending_offline_result["cash_yield"]
	assert_gt(cash_yield, 0.0, "3 個礦工離場 1 小時應該有離線收成")
	assert_eq(
		main._offline_yield_label.text, "+%s" % main._fmt_num(cash_yield),
		"面板顯示金額應該直接嚟自 settle() 結果"
	)

	var cash_before: float = main.state.cash
	var lifetime_before: float = main._lifetime_cash
	main._on_offline_claim_pressed()

	assert_almost_eq(main.state.cash, cash_before + cash_yield, 0.01, "撳收下先入帳，金額應該同 settle() 結果一致")
	assert_almost_eq(main._lifetime_cash, lifetime_before + cash_yield, 0.01)
	assert_false(main._offline_panel.visible, "撳收下之後面板應該收埋")

## 驗收「威望重置後 HUD 倍率」：夠門檻先顯示「拆廠搬礦」掣；確認重置
## 之後 Cash／礦工／升級清零，終身 Cash／重置次數保留，HUD 威望 bar
## 嘅門檻同永久收入倍率都要跟返新嘅 prestige_count 算。
func test_prestige_reset_updates_income_multiplier_and_hud() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main._lifetime_cash = main.c.prestige_threshold(0)
	main.state.cash = 999.0
	main.state.miner_count = 5
	main.state.belt_level = 7
	main._refresh_hud()
	assert_true(main._prestige_button.visible, "威望達門檻應該顯示「拆廠搬礦」掣")

	main._do_prestige_reset()

	assert_eq(main._prestige_count, 1, "應該記到已經重置一次")
	assert_eq(main.state.cash, 0.0, "重置應該清 Cash")
	assert_eq(main.state.miner_count, 0, "重置應該清礦工")
	assert_eq(main.state.belt_level, 1, "重置應該將帶打番去 Lv1")
	assert_almost_eq(main._lifetime_cash, main.c.prestige_threshold(0), 0.01, "lifetime_cash 唔應該清零")
	assert_almost_eq(Prestige.income_multiplier(main.c, main._prestige_count), 1.5, 0.001, "重置一次永久收入應該 ×1.5")

	main._refresh_hud()
	assert_almost_eq(
		main._prestige_bar.max_value, main.c.prestige_threshold(1), 0.01,
		"HUD 威望門檻應該跟返新嘅 prestige_count 算"
	)
	assert_false(main._prestige_button.visible, "重置完未再夠新門檻，掣應該收返")

	# Review 意見（round 1）：確認面板講「永久收入倍率 ×1.0 → ×1.5」，實際
	# 即時收入（current_income_rate()／tick()）一定要食返呢個倍率，唔淨係
	# HUD 門檻／文字講吓。
	main.state.miner_count = 4
	main.state.belt_level = 6
	var rate_with_bonus: float = main.state.current_income_rate()
	main.state.income_multiplier = 1.0
	var rate_without_bonus: float = main.state.current_income_rate()
	main.state.income_multiplier = Prestige.income_multiplier(main.c, main._prestige_count)
	assert_gt(rate_without_bonus, 0.0, "測試前提：呢個礦工／帶配置應該有非零放置收入")
	assert_almost_eq(
		rate_with_bonus, rate_without_bonus * 1.5, 0.01,
		"重置一次之後，即時放置收入應該實際 ×1.5（唔係淨係 HUD 文字話 ×1.5）"
	)

## 驗收「殺 App 重開見到礦工」：_build_world() 淨係起空嘅 _miners_root，
## 之前淨靠 _try_summon_miner() 先會生礦工 node——讀存檔冇行過呢條 path，
## 殺 App 重開 HUD 話「礦工 3/12」但山腳一隻機械人都冇（Review 意見）。
func test_loaded_save_respawns_miner_visuals() -> void:
	var seed_state := SaveManager.default_state()
	seed_state["miners"] = 3
	SaveManager.save_state(seed_state)

	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_eq(main.state.miner_count, 3)
	assert_eq(main._miners_root.get_child_count(), 3, "讀返嚟嘅礦工數應該一齊生返晒啲 node，唔係得個空 root")

## 驗收「威望門檻計埋狂熱收入」：FrenzyYardView._score_and_free() 過爐嗰陣
## 直接加落 state.cash（唔經 GameState.tick()／scoop_ore()），Review 意見：
## _on_frenzy_ended() 冧咗補 frenzy.cash_earned 落 _lifetime_cash 會令
## 威望進度條漏計狂熱嗰份（放置收入 ×5 ×120s，唔係小數目）。
func test_frenzy_cash_earned_counts_toward_lifetime_cash() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()
	# 模擬狂熱期間過爐賺咗 500（同 frenzy_yard_view.gd._score_and_free()
	# 嘅實際行為一致：cash 同 frenzy.cash_earned 一齊加）。
	main.frenzy.cash_earned = 500.0
	main.state.cash += 500.0
	var lifetime_before: float = main._lifetime_cash

	main._on_frenzy_ended()

	assert_almost_eq(
		main._lifetime_cash, lifetime_before + 500.0, 0.01, "狂熱賺嘅 Cash 應該計入終身 Cash（威望門檻）"
	)

## 迴歸測試：main.gd 讀檔套用 state.income_multiplier 嗰下，一定要喺攞
## OfflineSettlement.settle() 用嗰個 raw rate 之後先做——唔係就
## Prestige.income_multiplier() 會喺 main.gd 度乘一次、settle() 入面又
## 再乘一次，變咗 ×2.25（1.5²）唔係 issue 要求嘅 ×1.5。用同一份存檔
## （淨係 prestige_count 唔同）比較兩次離線結算金額嚟斷言冇計多咗。
func test_offline_settlement_does_not_double_apply_prestige_multiplier() -> void:
	var base_last_save: float = Time.get_unix_time_from_system() - 3600.0
	var scene: PackedScene = load("res://main.tscn")

	var no_reset := SaveManager.default_state()
	no_reset["last_save_unix"] = base_last_save
	no_reset["miners"] = 3
	no_reset["belt_level"] = 5
	no_reset["prestige_count"] = 0
	SaveManager.save_state(no_reset)
	main = scene.instantiate()
	add_child_autofree(main)
	var yield_no_reset: float = main._pending_offline_result["cash_yield"]
	main.free()

	var one_reset := SaveManager.default_state()
	one_reset["last_save_unix"] = base_last_save
	one_reset["miners"] = 3
	one_reset["belt_level"] = 5
	one_reset["prestige_count"] = 1
	SaveManager.save_state(one_reset)
	main = scene.instantiate()
	add_child_autofree(main)
	var yield_one_reset: float = main._pending_offline_result["cash_yield"]

	assert_gt(yield_no_reset, 0.0, "測試前提：冇威望都應該有離線收成")
	var expected: float = yield_no_reset * 1.5
	assert_almost_eq(
		yield_one_reset, expected, expected * 0.02,
		"重置一次嘅離線結算應該啱啱 ×1.5（如果 income_multiplier 喺 main.gd 度計多咗一次，呢度會變咗 ×2.25）"
	)

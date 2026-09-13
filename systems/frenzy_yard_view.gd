extends Node3D
class_name FrenzyYardView

## VR-04：狂熱車場 3D 表現層。
##
## 純畫面／輸入轉接，核心數值邏輯全部喺 FrenzyState（`frenzy`），方便
## GUT 獨立測試（見 test/test_frenzy_state.gd）；呢個 script 冇任何
## 判分公式，淨係將 frenzy 嘅方法接落 3D 節點同觸控。
##
## 設計取態（docx 淨係質性描述，冇實數，全部 TUNE，見 constants.gd
## D 部）：車唔係留喺頂固定，而係不斷向落巡航（car_descent_speed），
## 玩家淨係跟指控制橫向（x），車去到 yard_min_y 即刻返頂再落，形成
## 「不斷落嚟緊嘅剷斗」。VR-06b 場地攤平之後，呢度嘅 (x, y) 係地面
## 平面（y 係「向落」嘅深度，唔係企起身嘅高度），世界沿用 Godot 3D
## 預設重力（-世界 Y＝-site z，見 main.gd SITE_BASIS 註解），散幣／
## 藍波生成之後自己跌落地面，車負責將佢哋撞去邊條門嘅 x 車道。實際
## 物理表現（跟真係跌成點）留返俾實機／編輯器playtest 微調 TUNE 數值，
## 呢度負責嘅係結構同判分事件接駁啱唔啱。
##
## 場景複用放置場個 camera／world（同一個 3D 座標系，見 constants.gd
## 註解），唔另起爐灶起多個 camera。
##
## 用戶實機回饋（ALTA-153 round2 第 1 點）：車場「上下分屏，兩者常駐」，
## 唔可以再切場景——呢個 node 一直都 visible（見 _ready()），frenzy
## 開始／完場（main.gd _try_start_frenzy()／_on_frenzy_ended()）淨係
## start()／stop() 呢個 gameplay tick（車郁、生碎料、幀數取樣），車／
## 牆／滾筒／門／木橋／UPGRADE 墊呢啲結構性 mesh 全程都喺度，冇嘢跌出
## 又彈返出嚟。

signal debris_scored(amount: float)

const DEBRIS_SIZE := Vector3(0.14, 0.14, 0.14)

var c: GameConstants
var game_state: GameState
var frenzy: FrenzyState
var rng := RandomNumberGenerator.new()

var car: AnimatableBody3D
var _car_mesh: MeshInstance3D
var _car_mat: StandardMaterial3D
var _blade_mesh: MeshInstance3D
var _blade_mat: StandardMaterial3D
var _car_target_x: float = 0.0
var _stun_timer: float = 0.0

var _roller_visual: MeshInstance3D
var _debris_root: Node3D
var _debris_nodes: Array = []
var _fake_debris_nodes: Array = []
var _debris_spawn_accum: float = 0.0
var _gears_active: Array = [] # 每個元素：{"node": Node3D, "timer": float}
var _fps_sample_accum: float = 0.0

## -- VR-06c：波池（見 constants.gd D2 部，純表現層，唔碰判分） --
var _pool_mesh_by_tier: Dictionary = {} # tier(String) -> MultiMeshInstance3D
var _pool_slots: Array = [] # 每個元素：{tier, local_index, pos, scale_mult, color, emissive, active}
var _pool_kick_root: Node3D
var _pool_kicked: Array = [] # 每個元素：{"slot": Dictionary, "node": Node3D, "timer": float}
var _pool_kick_scan_accum: float = 0.0

var _gate_materials: Array[StandardMaterial3D] = [] # ALTA-153 round2：「門亮」——狂熱先實際發光


func _init(constants: GameConstants, gs: GameState, fs: FrenzyState) -> void:
	c = constants
	game_state = gs
	frenzy = fs


func _ready() -> void:
	rng.randomize()
	visible = true # ALTA-153 round2 第 1 點：車場常駐，唔再狂熱先顯示
	set_process(false) # gameplay tick（車郁／生碎料）仍然要 frenzy 先行
	set_process_unhandled_input(true)

	_debris_root = Node3D.new()
	_debris_root.name = "DebrisRoot"
	add_child(_debris_root)

	_pool_kick_root = Node3D.new()
	_pool_kick_root.name = "PoolKickRoot"
	add_child(_pool_kick_root)

	_build_walls()
	_build_ore_pool() # VR-06c：波池——鋪滿地面嘅靜態波，車場常駐，唔跟 start()/stop() 重建
	_build_car()
	_build_roller()
	_build_bridge()
	_build_gates()
	_build_furnace()
	_build_upgrade_pad()
	_set_active_visual(false) # 開場未狂熱，門先暗住


func start() -> void:
	set_process(true)
	_reset_car()
	_clear_debris()
	_clear_gears()
	_reset_pool_kicks()
	_debris_spawn_accum = 0.0
	_fps_sample_accum = 0.0
	_set_active_visual(true) # 用戶回饋：「門亮」——狂熱先落實發光

func stop() -> void:
	set_process(false)
	_clear_debris()
	_clear_gears()
	_reset_pool_kicks() # 波池轉咗做 rigid 嗰啲一律強制轉返靜態，唔留喺車場度懸空
	_reset_car() # 車場常駐，完場車要停返去上面「泊定」，唔好留喺爐口
	_set_active_visual(false)

## ALTA-153 round2：狂熱「活起來」嘅視覺提示——四道倍數門喺唔活躍時色
## 淡樸實，狂熱一觸發即刻發光（「門亮」，issue 視覺參考），等玩家一眼
## 知道車場而家可以推。純表現層，唔影響 _on_gate_entered() 判分。
func _set_active_visual(active: bool) -> void:
	for mat in _gate_materials:
		mat.emission_energy_multiplier = 1.4 if active else 0.0


func _process(delta: float) -> void:
	if not frenzy.active:
		return
	_handle_car_descent(delta)
	_spawn_tick(delta)
	_update_fake_debris(delta)
	_update_gears(delta)
	_pool_kick_tick(delta)
	_update_pool_kicks(delta)
	_fps_sample_tick(delta)
	if _roller_visual:
		_roller_visual.rotate_x(delta * 4.0)


# ══════════════════════ 輸入：跟指 ══════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if not frenzy.active:
		return
	var screen_pos := Vector2.INF
	if event is InputEventScreenDrag:
		screen_pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		screen_pos = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		screen_pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		screen_pos = event.position
	if screen_pos == Vector2.INF:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 用戶回饋（ALTA-153 round2 第 1 點）：放置場常駐之後，山腳／帶／爐
	# 同車場共用埋同一個輸入通道——撳中山腳碎料（tap-to-scoop）都會經
	# 呢個 `_unhandled_input()`。Review 意見（round2 修正）：Godot 4 嘅
	# physics object picking 響 `_unhandled_input` 之後先排隊，喺
	# main.gd `_on_pile_chunk_input()` 度 set_input_as_handled() 完全
	# 攔唔到今次呢個 `_unhandled_input`（已經行緊緊）——真正生效嘅防守
	# 淨係得下面呢句：用「呢個螢幕 Y 有冇喺車場最頂（car_park_max_y）
	# 嗰行之下」判斷，先至當跟指處理，否則撳中山腳碎料會連車都拖埋一齊
	# 郁。刻意唔用射線同 Z=0 平面求交嘅世界 Y 嚟判斷——嗰條反向投影近
	# 畫面邊緣（好斜嘅視角）容易求出好誇張嘅世界 Y（近乎同平面平行嘅
	# 射線，交點會彈得好遠），唔穩陣；呢度用嘅 `unproject_position()`
	# 係正向投影，唔會有呢個問題。
	var yard_mid_x: float = (c.yard_x_range.x + c.yard_x_range.y) * 0.5
	var yard_top_screen_y: float = cam.unproject_position(
		to_global(_site_to_world_yard_ref(Vector2(yard_mid_x, c.car_park_max_y)))
	).y
	# 留返 2% 螢幕高度做呼吸位——用畫面高度嘅比例而唔係固定 px，先啱晒
	# 唔同解像度／DPI（固定 px 喺好細嘅 headless 測試 viewport 度會大到
	# 冚晒個判斷）。
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	if screen_pos.y < yard_top_screen_y - viewport_h * 0.02:
		return
	# 成個世界（放置場＋車場，見 constants.gd／main.gd 註解）都住喺 Z=0
	# 呢個平面，車場物件淨係用 x／y，z 恆等 0（見 _build_car() 等）。
	# 舊式 project_position(screen_pos, cam.global_position.z) 假設咗相機
	# 正面望 -Z、z=10 先啱（Review 意見，ALTA-150）：改咗斜視相機
	# （pitch/yaw）之後呢條式唔再啱——依家改為用射線同 Z=0 平面求交，
	# 唔理相機擺法點都啱（包括未來再調角度）。
	var ray_origin: Vector3 = cam.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = cam.project_ray_normal(screen_pos)
	# VR-06b：場地攤平做地面——用場地自己嘅地面平面（local z=0）求交。
	var ground_plane := Plane(global_transform.basis.z, global_position)
	var hit: Variant = ground_plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return
	_car_target_x = to_local(hit as Vector3).x

func _site_to_world_yard_ref(v: Vector2) -> Vector3:
	return Vector3(v.x, v.y, 0.0)


# ══════════════════════ 車：巡航向落 + 跟指橫向 ══════════════════════

func _reset_car() -> void:
	car.position = Vector3(0.0, c.car_park_max_y, CAR_Z)
	_car_target_x = 0.0
	_stun_timer = 0.0
	_apply_car_tier_visual()

func _handle_car_descent(delta: float) -> void:
	if _stun_timer > 0.0:
		_stun_timer = maxf(_stun_timer - delta, 0.0)
		frenzy.advance_car(delta, _car_target_x)
		car.position.x = frenzy.car_x
		return
	var speed_mult: float = float(frenzy.current_tier().get("speed_mult", 1.0))
	car.position.y -= c.car_descent_speed * speed_mult * delta
	if car.position.y <= c.yard_min_y:
		car.position.y = c.car_park_max_y
	frenzy.advance_car(delta, _car_target_x)
	car.position.x = frenzy.car_x


# ══════════════════════ 建場景（VR-06：美術經 VisualFactory 出，見 CREDITS.md） ══════════════════════

func _make_area(size: Vector3) -> Area3D:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# VR-06b：攤平之後 z 係高度——感應區一律拉高 0.8，地面上嘅碎料／車都撞到。
	shape.size = Vector3(size.x, size.y, maxf(size.z, 0.8))
	col.shape = shape
	area.add_child(col)
	return area

func _build_walls() -> void:
	var height: float = c.car_park_max_y - c.yard_min_y + 1.0
	var mid_y: float = (c.car_park_max_y + c.yard_min_y) * 0.5
	for side_x in [c.yard_x_range.x - 0.1, c.yard_x_range.y + 0.1]:
		var wall := StaticBody3D.new()
		wall.name = "Wall"
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.2, height, 1.0)
		col.shape = shape
		wall.add_child(col)
		wall.position = Vector3(side_x, mid_y, 0.4)
		add_child(wall)

## VR-06c：卡通推土機——車身細、鏟斗大、履帶（issue 視覺參考第 2 點），
## 代替之前純色盒仔＋四粒輪。碰撞盒故意維持原本 Vector3(0.5, 0.22, 0.4)
## 唔改（同木橋／UPGRADE 墊／四道門觸發全部靠呢個 CollisionShape3D 撞
## Area3D，改咗大細會連帶郁哂已經調校好嘅木橋安全闊度等數值）——呢張
## issue 淨係換表現層，唔郁物理／判分，梯形視覺同碰撞盒刻意分開兩件事。
const CAR_BODY_SIZE := Vector3(0.28, 0.16, 0.28)
const CAR_BLADE_SIZE := Vector3(0.6, 0.09, 0.2)
const CAR_TRACK_SIZE := Vector3(0.08, 0.11, 0.32)
const CAR_TRACK_COLOR := Color(0.14, 0.14, 0.15)
const CAR_Z := 0.16 # VR-06b：車身中心離地高度（攤平場地，z 係高度）

func _build_car() -> void:
	car = AnimatableBody3D.new()
	car.name = "Car"
	car.add_to_group("frenzy_car")
	car.sync_to_physics = true

	# 場地規格 v2（ALTA-219）：車身黃 #F2C230／鏟斗紅 #D9432B（issue 色板
	# 「車黃鏟斗紅」），代替之前嘅灰色車身。
	_car_mesh = VisualFactory.make_metal_box(CAR_BODY_SIZE, Color("#F2C230"))
	_car_mat = _car_mesh.material_override # _flash_car() 撞岩浆閃身用
	car.add_child(_car_mesh)

	# 鏟斗擺喺車頭（-Y，車不斷向落嘅方向，見 _handle_car_descent()）、
	# 闊過車身好多先似「鏟」；顏色由 _apply_car_tier_visual() 揸（issue：
	# 「鏟斗鮮色（紅／黃）」，UPGRADE 逐級升先變闊，唔再係成架車等比縮放）。
	# Review 意見（round 1）：舊版擺咗喺 -Z（車尾／背向前進方向），
	# headless unproject_position() 量過鏟斗投影喺車身上方——依家改擺
	# -Y（車身底下，向落嘅方向），Y 係「厚度」（伸出去 body 底之外一截），
	# Z 同車身一樣深，唔再伸出去 Z 方向。
	_blade_mesh = VisualFactory.make_metal_box(CAR_BLADE_SIZE, Color("#D9432B"))
	_blade_mat = _blade_mesh.material_override
	_blade_mesh.position = Vector3(0.0, -(CAR_BODY_SIZE.y * 0.5 + CAR_BLADE_SIZE.y * 0.5 - 0.02), -0.04)
	car.add_child(_blade_mesh)

	# 履帶——兩條低身長盒仔代替四粒輪，卡通推土機必備語言（issue 視覺
	# 參考第 2 點）；純裝飾，唔跟 tier 變（同舊版輪一樣淨係唔郁 _car_mesh
	# 之外嘅嘢）。
	for side_x in [-1.0, 1.0]:
		var track := VisualFactory.make_metal_box(Vector3(CAR_TRACK_SIZE.x, CAR_TRACK_SIZE.z, CAR_TRACK_SIZE.y), CAR_TRACK_COLOR)
		track.position = Vector3(
			side_x * (CAR_BODY_SIZE.x * 0.5 + CAR_TRACK_SIZE.x * 0.5), 0.0, -CAR_BODY_SIZE.z * 0.5 + 0.02
		)
		car.add_child(track)
	# 駕駛室（車身頂細盒）——卡通推土機語言。
	var cab := VisualFactory.make_metal_box(Vector3(0.16, 0.14, 0.12), Color(0.95, 0.78, 0.2))
	cab.position = Vector3(0.0, 0.04, CAR_BODY_SIZE.z * 0.5 + 0.06)
	car.add_child(cab)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.22, 0.4)
	col.shape = shape
	car.add_child(col)
	car.position = Vector3(0.0, c.car_park_max_y, CAR_Z)
	add_child(car)

func _build_roller() -> void:
	var area := _make_area(c.spike_roller_half_extents * 2.0)
	area.name = "RollerArea"
	area.position = Vector3(c.spike_roller_pos.x, c.spike_roller_pos.y, 0.0)
	area.body_entered.connect(_on_roller_entered)
	add_child(area)
	# 圓柱代替盒仔：`_process()` 度嘅 `rotate_x()` 先會睇落似真係喺轉緊
	# 嘅刺滾筒（盒仔轉落嚟成塊嘢喺度打滾，唔似滾筒）。
	var extents := c.spike_roller_half_extents * 2.0
	_roller_visual = VisualFactory.make_low_poly_cylinder(
		maxf(extents.y, extents.z) * 0.5, extents.x, VisualFactory.PALETTE["gear_metal"], 10
	)
	_roller_visual.rotation_degrees.z = 90.0
	_roller_visual.position = area.position + Vector3(0.0, 0.0, maxf(extents.y, extents.z) * 0.5)
	add_child(_roller_visual)

func _build_bridge() -> void:
	var x0: float = c.lava_bridge_x_range.x
	var x1: float = c.lava_bridge_x_range.y
	var width: float = x1 - x0
	var mid_x: float = (x0 + x1) * 0.5
	var area := _make_area(Vector3(width, 0.1, 0.5))
	area.name = "BridgeArea"
	area.position = Vector3(mid_x, c.lava_bridge_y, 0.0)
	area.body_entered.connect(_on_bridge_entered)
	add_child(area)

	var safe_width: float = c.lava_bridge_safe_x_range.y - c.lava_bridge_safe_x_range.x
	var safe_mid: float = (c.lava_bridge_safe_x_range.x + c.lava_bridge_safe_x_range.y) * 0.5
	var lava_mesh := VisualFactory.make_metal_box(
		Vector3(width, 0.5, 0.03), VisualFactory.PALETTE["lava"], VisualFactory.PALETTE["lava"], 1.8
	)
	lava_mesh.position = Vector3(mid_x, c.lava_bridge_y, 0.0)
	add_child(lava_mesh)
	for _i in range(8):
		var crust := VisualFactory.make_flat_box(Vector3(rng.randf_range(0.06, 0.14), rng.randf_range(0.05, 0.1), 0.03), Color(0.3, 0.1, 0.05))
		crust.position = Vector3(rng.randf_range(x0, x1), c.lava_bridge_y + rng.randf_range(-0.2, 0.2), 0.01)
		add_child(crust)
	var bridge_mesh := VisualFactory.make_flat_box(Vector3(safe_width, 0.56, 0.05), VisualFactory.PALETTE["bridge_wood"])
	bridge_mesh.position = Vector3(safe_mid, c.lava_bridge_y, 0.03)
	add_child(bridge_mesh)
	for i in range(5):
		var plank := VisualFactory.make_flat_box(Vector3(safe_width, 0.06, 0.02), VisualFactory.PALETTE["bridge_wood"].darkened(0.25))
		plank.position = Vector3(safe_mid, c.lava_bridge_y - 0.22 + float(i) * 0.11, 0.06)
		add_child(plank)
	# Review（round 1）：呢個 +0.4 本身係想「揚高少少等睇得清楚」，但攤平
	# 之後 y 唔再係高度（係深度）——加落 y 度變咗將個牌推咗出木橋自己個
	# footprint（±0.28）之外，撞正西門（west，x 啱啱好同呢度嘅 safe_mid
	# 同一個 1.85）嘅 y 範圍，實機見到「100 lb」同「x4」疊埋。改用 z（呢
	# 個場地嘅高度軸）揚高，y 留喺木橋自己中心，唔會再撞西門。
	var lb_label := Label3D.new()
	lb_label.text = "100 lb"
	lb_label.font_size = 56
	lb_label.pixel_size = 0.003
	lb_label.position = Vector3(safe_mid, c.lava_bridge_y, 0.3)
	add_child(lb_label)

## 場地規格 v2（ALTA-219）：門改「門框＋兩柱＋頂部數字」語言（issue 視覺
## 參考 k_304：木框＋橫樑），紫色（PALETTE["pad_purple"]，白字），代替
## 之前地上一塊按倍數變色嘅平板。Area3D 觸發區大細／位置完全唔變
## （_on_gate_entered() 判分邏輯淨係睇 body_entered，唔理視覺）。
##
## 闊度／高度跟 issue「闊 2.5 高 1.5」嘅比例，但世界單位縮細——嗰組數
## 係跟 IZM 片「車闊＝1」嘅畫面量度單位，唔係呢個場景嘅世界座標刻度；
## main/mid/west 三道門喺 3.4 闊車場相鄰淨得 1.0~1.4 個世界單位，字面
## 跟 2.5 闊會相鄰門框互撞，所以縮到 GATE_WIDTH 夾實際門距。
const GATE_WIDTH := 0.8
const GATE_POST_HEIGHT := 0.5
const GATE_POST_THICKNESS := 0.06
const GATE_LINTEL_HEIGHT := 0.05

func _build_gates() -> void:
	for gate_id: String in c.gates.keys():
		var gate: Dictionary = c.gates[gate_id]
		var gx: float = gate["x"]
		var gy: float = gate.get("y", c.gate_y)
		var mult: float = float(gate.get("mult", 1.0))
		var gate_pos := Vector3(gx, gy, 0.0)

		var area := _make_area(Vector3(0.5, 0.08, 0.6))
		area.name = "Gate_%s" % gate_id
		area.position = gate_pos
		area.body_entered.connect(_on_gate_entered.bind(gate_id))
		add_child(area)

		# 攤平地面：門柱沿 z（高度）企起，門楣喺頂，地上一塊紫墊 + 大字。
		var half_w: float = GATE_WIDTH * 0.5
		for side in [-1.0, 1.0]:
			var post := VisualFactory.make_flat_box(
				Vector3(GATE_POST_THICKNESS, GATE_POST_THICKNESS * 1.4, GATE_POST_HEIGHT),
				VisualFactory.PALETTE["pad_purple"]
			)
			post.position = gate_pos + Vector3(side * half_w, 0.0, GATE_POST_HEIGHT * 0.5)
			add_child(post)
		var lintel := VisualFactory.make_flat_box(
			Vector3(GATE_WIDTH + GATE_POST_THICKNESS, GATE_POST_THICKNESS * 1.4, GATE_LINTEL_HEIGHT),
			VisualFactory.PALETTE["pad_purple"]
		)
		lintel.position = gate_pos + Vector3(0.0, 0.0, GATE_POST_HEIGHT + GATE_LINTEL_HEIGHT * 0.5)
		add_child(lintel)
		var gate_mat: StandardMaterial3D = lintel.material_override
		gate_mat.emission_enabled = true
		gate_mat.emission = gate_mat.albedo_color
		gate_mat.emission_energy_multiplier = 0.0
		_gate_materials.append(gate_mat)

		# Review round 2：mid 門（x=0.85）同帶（belt_head_pos→smelter_pos
		# 都係 x=0.85）撞正同一條 x 線，帶會切過門楣個「x3」字。門柱／門楣／
		# Area3D 判定完全唔郁，淨係將字揚高（同「100 lb」牌用開嗰個手法：
		# 抬 z 唔改 x／y，避開帶條所在嘅低身高度）就夠清晰，四道門統一
		# 加返呢個高度，唔使淨改 mid 一個造成唔對稱。
		#
		# Review round 2：peak 門（x5）嘅地墊／字跟門本身 y=-1.72 就啱好落
		# 喺木橋 5 條橋板（lava_bridge_y=-1.4，板長靠 y 中心 ±0.22，遠緣
		# 去到 -1.62）同倉（warehouse_pos.y=-2.35，連埋屋頂 half 0.29，
		# 近緣去到 -2.06）夾埋剩返嘅 [-2.06, -1.62] 窄縫之間。門柱／門楣／
		# Area3D 判定仍然企喺 gate_pos（門嘅判分位置唔變），淨係將「地面上
		# 嗰嚿墊同字」呢兩件純視覺嘢擺喺呢條窄縫正中央（-1.84）、順便縮窄
		# 墊高度去 0.3，兩邊各留 0.07 緩衝，同橋板、倉都唔再迫埋。
		var pad_pos := gate_pos
		var pad_height := 0.45
		if gate_id == "peak":
			pad_pos = Vector3(gx, -1.8, 0.0)
			pad_height = 0.26
		var pad := _make_ground_pad(pad_pos, Vector2(GATE_WIDTH, pad_height))
		add_child(pad)
		var label := Label3D.new()
		label.text = "x%d" % int(mult)
		label.font_size = 110
		label.position = pad_pos + Vector3(0.0, 0.0, 0.2)
		label.pixel_size = 0.0035
		label.modulate = Color.WHITE
		add_child(label)

## 場地規格 v2（ALTA-219）：地面墊統一語言——紫色圓角矩形（呢度冇圓角
## mesh 現成用，用扁平盒仔代替，見 _make_ground_pad()）+ 白色大字，
## issue 定義爐前墊即係「SELL」（熔爐入口）。FurnaceArea 觸發判分唔變，
## 呢度加返視覺（之前呢個墊完全冇 mesh，實機淨見到爐本身）。
func _build_furnace() -> void:
	var width: float = c.yard_x_range.y - c.yard_x_range.x
	var mid_x: float = (c.yard_x_range.x + c.yard_x_range.y) * 0.5
	var area := _make_area(Vector3(width, 0.15, 0.6))
	area.name = "FurnaceArea"
	area.position = Vector3(mid_x, c.yard_min_y, 0.0)
	area.body_entered.connect(_on_furnace_entered)
	add_child(area)

	# Review round 2：SELL 墊／字擺喺 yard_min_y（-1.9）就啱好落喺爐身
	# （smelter_pos.y=-2.35，半深 0.3 → 前緣 -2.05）嘅範圍之內 0.1，
	# 實機見到「SELL」俾爐身遮到淨返「SE」。FurnaceArea 判分觸發位置
	# 唔變（車場物理照舊喺 yard_min_y 兌現），淨係將呢嚿墊／字嘅視覺位
	# 挪前少少（更接近車場、遠離爐身），即係 reviewer 建議嘅「擺喺爐前
	# 唔係爐底」。
	#
	# Review round 2 追加：挪前之後量到 mid_x=0.6 同帶（belt_head_pos／
	# smelter_pos 都係 x=0.85）淨相差 0.25，仲喺 SELL 墊闊度（半 0.55）
	# 之內，帶一樣會切到個字——同 mid 門「x3」嗰個根源一樣，用返同一招
	# （揚高 z，見 _build_gates() 註解）。
	var sell_visual_y := c.yard_min_y + 0.2
	var pad := _make_ground_pad(Vector3(mid_x, sell_visual_y, 0.0), Vector2(1.1, 0.5))
	add_child(pad)
	var label := Label3D.new()
	label.text = "SELL"
	label.font_size = 110
	label.position = Vector3(mid_x, sell_visual_y, 0.2)
	label.pixel_size = 0.0035
	label.modulate = Color.WHITE
	add_child(label)

## 場地規格 v2：紫色圓角矩形墊（#5B3A8C，2×1.2 世界單位比例，呢度用一
## 個扁平盒仔近似「圓角」——Godot 冇現成 rounded-box primitive mesh，起
## SurfaceTool 自訂幾何超出呢個純視覺調整嘅範圍，用邊角削細少少嘅扁盒
## 頂替，同其餘 flat-shaded box 手法一致）。
func _make_ground_pad(pos: Vector3, size: Vector2) -> MeshInstance3D:
	var pad := VisualFactory.make_flat_box(Vector3(size.x, size.y, 0.02), VisualFactory.PALETTE["pad_purple"])
	pad.position = pos + Vector3(0.0, 0.0, 0.01)
	return pad

func _build_upgrade_pad() -> void:
	var area := _make_area(Vector3(0.5, 0.3, 0.5))
	area.name = "UpgradePadArea"
	area.position = Vector3(c.upgrade_pad_pos.x, c.upgrade_pad_pos.y, 0.0)
	area.body_entered.connect(_on_upgrade_pad_entered)
	add_child(area)
	var visual := _make_ground_pad(area.position, Vector2(0.9, 0.5))
	add_child(visual)
	var label := Label3D.new()
	label.text = "UPGRADE"
	label.font_size = 80
	label.position = area.position + Vector3(0.0, 0.0, 0.03)
	label.pixel_size = 0.0035
	label.modulate = Color.WHITE
	add_child(label)

# ══════════════════════ Area3D 事件：刺滾筒／窄岩浆／倍數門／爐／UPGRADE 墊 ══════════════════════

func _on_roller_entered(body: Node3D) -> void:
	if not (frenzy.active and body.is_in_group("frenzy_debris")):
		return
	var kind: String = body.get_meta("kind", "coin")
	var new_kind: String = frenzy.apply_roller(kind)
	if new_kind != kind:
		body.set_meta("kind", new_kind)
		_recolor_debris(body, new_kind)
		SfxPlayer.play("roller_hit")

func _on_bridge_entered(body: Node3D) -> void:
	if not frenzy.active or body != car:
		return
	if not frenzy.is_bridge_safe_x(car.position.x):
		frenzy.register_lava_fall()
		_stun_timer = c.lava_fall_stun_secs
		car.position.y = c.lava_bridge_y + 0.05
		_flash_car(Color(1.0, 0.25, 0.2))
		SfxPlayer.play("lava_fall")

func _on_gate_entered(body: Node3D, gate_id: String) -> void:
	if not (frenzy.active and body.is_in_group("frenzy_debris")):
		return
	var passed: Array = body.get_meta("passed_gates", [])
	if gate_id in passed:
		return
	passed.append(gate_id)
	body.set_meta("passed_gates", passed)
	SfxPlayer.play("gate_pass", -6.0)

func _on_furnace_entered(body: Node3D) -> void:
	if not (frenzy.active and body.is_in_group("frenzy_debris")):
		return
	_score_and_free(body)

func _score_and_free(body: Node3D) -> void:
	var kind: String = body.get_meta("kind", "coin")
	var passed: Array = body.get_meta("passed_gates", [])
	var awarded: float = frenzy.score_item(frenzy.base_value_for_kind(kind), passed)
	game_state.cash += awarded
	debris_scored.emit(awarded)
	SfxPlayer.play("furnace_feed", -6.0)
	_debris_nodes.erase(body)
	_fake_debris_nodes.erase(body)
	if is_instance_valid(body):
		body.queue_free()

func _on_upgrade_pad_entered(body: Node3D) -> void:
	if not frenzy.active or body != car:
		return
	if frenzy.try_upgrade_pad():
		_apply_car_tier_visual()

## VR-06c：UPGRADE 墊逐級升淨係換鏟斗（issue：「UPGRADE 墊換模時鏟斗
## 明顯變闊」）——車身／履帶唔郁，鏟斗闊度跟 tier.scale 放大（淨放大
## X，Y／Z 唔變，先睇落係「變闊」唔係「成舊嘢變大」），顏色跟 tier.color
## 換（鮮色紅／黃系，見 car_upgrade_tiers）。
func _apply_car_tier_visual() -> void:
	var tier: Dictionary = frenzy.current_tier()
	var width_mult: float = float(tier.get("scale", 1.0))
	_blade_mesh.scale = Vector3(width_mult, 1.0, 1.0)
	_blade_mat.albedo_color = tier.get("color", Color(0.55, 0.15, 0.15))

func _flash_car(color: Color) -> void:
	var original: Color = _car_mat.albedo_color
	var tw := create_tween()
	tw.tween_property(_car_mat, "albedo_color", color, 0.05)
	tw.tween_property(_car_mat, "albedo_color", original, c.lava_fall_stun_secs)


# ══════════════════════ 散幣／藍波：生成 + 假物理 fallback ══════════════════════

func _debris_color(kind: String) -> Color:
	match kind:
		"barrel": return Color(0.15, 0.35, 0.75)
		"gold": return Color(0.95, 0.8, 0.15)
		_: return Color(0.85, 0.7, 0.2) # coin

## 真剛體嘅 body 係 RigidBody3D，MeshInstance3D 掛喺 child(0)；假物理
## 嗰邊 _spawn_fake_debris() 直接用 VisualFactory 出嘅 MeshInstance3D
## 做 node 本身，冇 child——兩種情況都要兼容（Reviewer 意見：漏咗呢個
## case，藍波喺假物理路徑一過滾筒就 get_child(0) 越界 + null 存取）。
func _recolor_debris(body: Node3D, kind: String) -> void:
	var mesh: MeshInstance3D = body if body is MeshInstance3D else body.get_child(0)
	var mat: StandardMaterial3D = mesh.material_override
	mat.albedo_color = _debris_color(kind)

func _spawn_tick(delta: float) -> void:
	_debris_spawn_accum += delta
	var interval: float = maxf(c.debris_spawn_interval_secs, 0.01)
	var cap: int = frenzy.current_debris_cap()
	while _debris_spawn_accum >= interval and _debris_nodes.size() < cap:
		_debris_spawn_accum -= interval
		_spawn_one_debris()
	if _debris_spawn_accum > interval:
		_debris_spawn_accum = interval # 撞咗 cap 唔好囤住個 accum，等 cap 一鬆就爆生一大舊

func _spawn_one_debris() -> void:
	var kind: String = frenzy.roll_spawn_kind(rng)
	var x: float = rng.randf_range(c.yard_x_range.x, c.yard_x_range.y)
	var pos := Vector3(x, c.yard_spawn_y - rng.randf_range(0.0, 0.6), DEBRIS_SIZE.z * 0.5 + 0.02)
	if frenzy.is_fake_physics():
		_spawn_fake_debris(kind, pos)
	else:
		_spawn_real_debris(kind, pos)

func _spawn_real_debris(kind: String, pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.add_to_group("frenzy_debris")
	body.set_meta("kind", kind)
	body.set_meta("passed_gates", [])
	body.mass = 0.2
	body.gravity_scale = c.debris_gravity_scale
	var mesh := VisualFactory.make_low_poly_cylinder(DEBRIS_SIZE.x * 0.5, DEBRIS_SIZE.y * 0.7, _debris_color(kind))
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = DEBRIS_SIZE
	col.shape = shape
	body.add_child(col)
	body.position = pos
	_debris_root.add_child(body)
	_debris_nodes.append(body)

## 低階機自動降級到底之後嘅假物理：冇 RigidBody3D，位置插值直落，
## 逐幀手動夾門／滾筒／爐嘅範圍（見 _update_fake_debris）。
func _spawn_fake_debris(kind: String, pos: Vector3) -> void:
	var node := VisualFactory.make_low_poly_cylinder(DEBRIS_SIZE.x * 0.5, DEBRIS_SIZE.y * 0.7, _debris_color(kind))
	node.set_meta("kind", kind)
	node.set_meta("passed_gates", [])
	node.position = pos
	_debris_root.add_child(node)
	_debris_nodes.append(node)
	_fake_debris_nodes.append(node)

func _update_fake_debris(delta: float) -> void:
	for node: Node3D in _fake_debris_nodes.duplicate():
		if not is_instance_valid(node):
			_fake_debris_nodes.erase(node)
			continue
		node.position.y -= c.debris_fake_fall_speed * delta

		var kind: String = node.get_meta("kind")
		if kind == "barrel" \
				and absf(node.position.x - c.spike_roller_pos.x) <= c.spike_roller_half_extents.x \
				and absf(node.position.y - c.spike_roller_pos.y) <= c.spike_roller_half_extents.y:
			node.set_meta("kind", "gold")
			_recolor_debris(node, "gold")

		var passed: Array = node.get_meta("passed_gates")
		for gate_id: String in c.gates.keys():
			if gate_id in passed:
				continue
			var gate: Dictionary = c.gates[gate_id]
			if absf(node.position.x - float(gate["x"])) <= 0.3 \
					and absf(node.position.y - float(gate.get("y", c.gate_y))) <= 0.08:
				passed.append(gate_id)

		if node.position.y <= c.yard_min_y:
			_score_and_free(node)

func _clear_debris() -> void:
	for node in _debris_nodes.duplicate():
		if is_instance_valid(node):
			node.queue_free()
	_debris_nodes.clear()
	_fake_debris_nodes.clear()


# ══════════════════════ 波池（VR-06c：靜態 MultiMesh 堆 + 車鏟前方轉真 rigid） ══════════════════════
#
# 純表現層，同上面「散幣／藍波」判分管道（_spawn_tick／_spawn_one_debris／
# frenzy_debris group／score_item()）完全獨立、互不干擾：呢度轉出嚟嘅
# RigidBody3D 唔加入 frenzy_debris group、唔掛 kind／passed_gates meta，
# 所以 _on_gate_entered()／_on_roller_entered()／_on_furnace_entered() 一律
# 唔會理佢哋，frenzy_state.gd 判分邏輯完全冇被呢部分觸碰。設計動機（issue
# 視覺參考第 1 點）：地面成千粒細波係環境「set dressing」，車推過有波散開
# 嘅「推堆」爽感；真正計分嘅散幣／藍波／金幣照舊由頂上落嚟畀車帶去門。

func _build_ore_pool() -> void:
	var weights: Dictionary = c.ore_pool_tier_weights
	var total_weight := 0.0
	for w in weights.values():
		total_weight += float(w)
	if total_weight <= 0.0:
		return
	# 場地規格 v2（ALTA-219）：波池之前鋪滿成條 y 走廊（車頂到爐前），
	# 完全冚住咗滾筒／木橋／岩浆／倍數門（實機截圖見唔到呢幾樣嘢，成幅
	# 畫面淨係一嚿波）。呢啲波池粒本身純粹「set dressing」，冇判分意義
	# （見上面註解），縮到車頭一截（滾筒之前），行返落去嗰截地面淨返
	# 俾滾筒／木橋／岩浆／門呢啲有結構嘅裝置露面，同 issue 視覺參考
	# 「地面墊／門／木橋／岩浆帶要睇得見」對齊。
	var y_min: float = c.gate_y + 0.35
	var y_max: float = c.car_park_max_y - 0.1
	# Review（round 1）：呢個 y 走廊入面本身企住個滾筒（spike_roller_pos），
	# 波池隨機散落成個矩形範圍會將滾筒淹冚返（同波池疊埋，判分冇影響但
	# 睇落實機一嚿波蓋晒個滾筒）。落面 rejection sampling 排除返滾筒個
	# footprint（半徑加返滾筒視覺圓柱嘅半徑 + 少少邊界），數粒 tries 之後
	# 攞唔到就將就攞最後一次（極罕有，唔值得為咗呢幾粒犧牲效能起 while true）。
	var roller_center := c.spike_roller_pos
	var roller_exclude_half := Vector2(
		c.spike_roller_half_extents.x + 0.08, maxf(c.spike_roller_half_extents.y, c.spike_roller_half_extents.z) + 0.08
	)
	# 有機 blob：3 個中心（同 description「2–3 個礦堆 blob」對齊），粒圍住
	# 中心散佈（IZM「堆」語言）；同一個中心組合俾所有礦物階分享，冚一次
	# 就夠——之前呢個 literal 擺咗喺 count 內圈，等於每粒都重建一次陣列。
	var centers := [
		Vector2(c.yard_x_range.x + 0.7, y_min + (y_max - y_min) * 0.6),
		Vector2(c.yard_x_range.x + 1.9, y_min + (y_max - y_min) * 0.25),
		Vector2(c.yard_x_range.y - 0.5, y_min + (y_max - y_min) * 0.7),
	]
	for tier: String in weights.keys():
		var count: int = int(round(float(c.ore_pool_total_count) * float(weights[tier]) / total_weight))
		if count <= 0:
			continue
		var color: Color = VisualFactory.ORE_TIER_COLOR.get(tier, Color(0.7, 0.7, 0.7))
		var emissive: bool = tier in VisualFactory.ORE_TIER_EMISSIVE_TIERS
		var scale_mult: float = c.ore_pool_gold_scale_mult if tier == "gold" else 1.0
		var mmi := VisualFactory.make_ore_pool_multimesh(
			c.ore_pool_ball_radius, color, 0.6 if emissive else 0.0, count
		)
		mmi.name = "OrePool_%s" % tier
		add_child(mmi)
		_pool_mesh_by_tier[tier] = mmi
		for i in range(count):
			var px := 0.0
			var py := 0.0
			for _attempt in range(6):
				var ctr: Vector2 = centers[rng.randi_range(0, centers.size() - 1)]
				var ang: float = rng.randf_range(0.0, TAU)
				var rad: float = sqrt(rng.randf()) * 0.42
				px = clampf(ctr.x + cos(ang) * rad * 1.15, c.yard_x_range.x, c.yard_x_range.y)
				py = clampf(ctr.y + sin(ang) * rad, y_min, y_max)
				if absf(px - roller_center.x) > roller_exclude_half.x or absf(py - roller_center.y) > roller_exclude_half.y:
					break
			var pos := Vector3(px, py, c.ore_pool_ball_radius * float(scale_mult))
			mmi.multimesh.set_instance_transform(
				i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_mult), pos)
			)
			_pool_slots.append({
				"tier": tier, "local_index": i, "pos": pos, "scale_mult": scale_mult,
				"color": color, "emissive": emissive, "active": false,
			})

func _hide_pool_slot(slot: Dictionary) -> void:
	var mmi: MultiMeshInstance3D = _pool_mesh_by_tier[slot["tier"]]
	mmi.multimesh.set_instance_transform(
		slot["local_index"], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	)

## 隔 ore_pool_kick_scan_interval_secs 先掃一次（節流：3000 粒逐幀掃
## 太浪費，車移動慢，10Hz 已經睇唔出滯後）；預算同散幣共用
## frenzy.current_debris_cap()——幀數降級一齊拖埋波池，唔會兩條獨立
## 曲線各顧各。最低幀數階（is_fake_physics()）直接唔轉 rigid，波池淨係
## 保持靜態鋪滿，唔再加物理負擔。
func _pool_kick_tick(delta: float) -> void:
	if frenzy.is_fake_physics():
		return
	_pool_kick_scan_accum += delta
	if _pool_kick_scan_accum < c.ore_pool_kick_scan_interval_secs:
		return
	_pool_kick_scan_accum = 0.0
	var budget: int = frenzy.current_debris_cap() - _debris_nodes.size() - _pool_kicked.size()
	if budget <= 0:
		return
	var radius_sq: float = c.ore_pool_kick_radius * c.ore_pool_kick_radius
	var kicked := 0
	for slot: Dictionary in _pool_slots:
		if kicked >= budget:
			break
		if slot["active"]:
			continue
		if (slot["pos"] as Vector3).distance_squared_to(car.position) > radius_sq:
			continue
		_activate_pool_slot(slot)
		kicked += 1

func _activate_pool_slot(slot: Dictionary) -> void:
	slot["active"] = true
	_hide_pool_slot(slot)

	var body := RigidBody3D.new()
	body.mass = 0.15
	body.gravity_scale = c.debris_gravity_scale
	var radius: float = c.ore_pool_ball_radius * float(slot["scale_mult"])
	var mesh := VisualFactory.make_ore_ball(radius, slot["color"], 0.6 if slot["emissive"] else 0.0)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	body.position = slot["pos"]
	_pool_kick_root.add_child(body) # apply_central_impulse() 要求 body 已經入咗物理空間，一定要先 add_child()

	# Review 意見（round 1）：舊版將 Y 分量夾做「一定向上」，等於將粒波
	# 撞入車自己個碰撞盒（kick_radius 0.15 細過車盒半高／半闊），headless
	# trace 見到個衝力即刻畀 depenetration 食晒。鏟斗擺喺車身底（-Y）之後，
	# 呢度改為向側／向下（遠離車盒），先真係推得開，唔會撞返自己車身。
	var away: Vector3 = (slot["pos"] as Vector3) - car.position
	away.y = -absf(away.y) - 0.3
	away.z = rng.randf_range(0.3, 0.7) # 揚起
	if Vector2(away.x, away.z).length() < 0.001:
		away.x = rng.randf_range(-1.0, 1.0)
		away.z = rng.randf_range(-1.0, 1.0)
	body.apply_central_impulse(away.normalized() * c.ore_pool_kick_impulse)

	_pool_kicked.append({"slot": slot, "node": body, "timer": 0.0})

## 離開車鏟範圍（用一個大過 kick_radius 嘅緩衝半徑，避免啱啱轉完 rigid
## 又即刻轉返靜態嘅閃爍）、活咗夠耐、或者跌到爐口深度，三者其一就強制
## 轉返靜態——確保「懸空」嘅時間有上限，同 _pool_kicked 嘅活躍量有上限。
func _update_pool_kicks(delta: float) -> void:
	var leave_radius: float = c.ore_pool_kick_radius * 1.6
	var leave_radius_sq: float = leave_radius * leave_radius
	for k: Dictionary in _pool_kicked.duplicate():
		var node: Node3D = k["node"]
		if not is_instance_valid(node):
			_pool_kicked.erase(k)
			continue
		k["timer"] += delta
		var out_of_range: bool = node.position.distance_squared_to(car.position) > leave_radius_sq
		var expired: bool = k["timer"] >= c.ore_pool_kick_lifetime_secs
		var past_floor: bool = node.position.y <= c.yard_min_y
		if out_of_range or expired or past_floor:
			_revert_pool_kick(k)

func _revert_pool_kick(k: Dictionary) -> void:
	_pool_kicked.erase(k)
	var slot: Dictionary = k["slot"]
	var node: Node3D = k["node"]
	var settle_pos: Vector3 = node.position if is_instance_valid(node) else (slot["pos"] as Vector3)
	settle_pos.x = clampf(settle_pos.x, c.yard_x_range.x, c.yard_x_range.y)
	settle_pos.y = clampf(settle_pos.y, c.yard_min_y, c.car_park_max_y)
	slot["pos"] = settle_pos
	slot["active"] = false
	var mmi: MultiMeshInstance3D = _pool_mesh_by_tier[slot["tier"]]
	mmi.multimesh.set_instance_transform(
		slot["local_index"],
		Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(slot["scale_mult"])), settle_pos)
	)
	if is_instance_valid(node):
		node.queue_free()

func _reset_pool_kicks() -> void:
	for k: Dictionary in _pool_kicked.duplicate():
		_revert_pool_kick(k)
	_pool_kicked.clear()
	_pool_kick_scan_accum = 0.0


# ══════════════════════ 齒輪（狂熱期間每 gear_drop_interval_secs 一粒） ══════════════════════

func spawn_gear() -> void:
	var x: float = rng.randf_range(c.yard_x_range.x, c.yard_x_range.y)
	var gear := VisualFactory.make_low_poly_cylinder(0.1, 0.1, Color(0.8, 0.85, 0.2), 8, 0.7)
	gear.name = "Gear"
	gear.position = Vector3(x, c.yard_spawn_y - rng.randf_range(0.2, 1.0), 0.12)
	gear.rotation_degrees.x = 90.0
	add_child(gear)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	col.shape = shape
	area.add_child(col)
	gear.add_child(area)
	area.body_entered.connect(_on_gear_caught.bind(gear))

	_gears_active.append({"node": gear, "timer": c.gear_pickup_window_secs})

func _update_gears(delta: float) -> void:
	for g: Dictionary in _gears_active.duplicate():
		if not is_instance_valid(g["node"]):
			_gears_active.erase(g)
			continue
		g["timer"] -= delta
		if g["timer"] <= 0.0:
			g["node"].queue_free()
			_gears_active.erase(g)

func _on_gear_caught(body: Node3D, gear: Node3D) -> void:
	if not frenzy.active or body != car or not is_instance_valid(gear):
		return
	var reward: float = frenzy.register_gear_catch()
	game_state.components += reward
	SfxPlayer.play("gear_catch")
	for g: Dictionary in _gears_active.duplicate():
		if g["node"] == gear:
			_gears_active.erase(g)
	gear.queue_free()

func _clear_gears() -> void:
	for g: Dictionary in _gears_active.duplicate():
		if is_instance_valid(g["node"]):
			g["node"].queue_free()
	_gears_active.clear()


# ══════════════════════ 幀數自動降級（S8+ 實測結果見 constants.gd） ══════════════════════

func _fps_sample_tick(delta: float) -> void:
	_fps_sample_accum += delta
	if _fps_sample_accum < c.frenzy_fps_sample_interval_secs:
		return
	_fps_sample_accum = 0.0
	var prev_tier: int = frenzy.debris_tier
	var fps := Engine.get_frames_per_second()
	frenzy.sample_fps(fps)
	if OS.is_debug_build():
		# VR-04 驗收要求「120 秒狂熱流暢（≥40fps）」實測報告；debug
		# build 先印，adb logcat 攞到就得，release 唔會有呢句。
		print("FRENZY_FPS t=%.1f fps=%.1f debris=%d cap=%d tier=%d" \
			% [c.frenzy_duration_secs - frenzy.time_remaining, fps, _debris_nodes.size(), frenzy.current_debris_cap(), frenzy.debris_tier])
	if frenzy.debris_tier != prev_tier:
		_trim_debris_to_cap()

func _trim_debris_to_cap() -> void:
	var cap: int = frenzy.current_debris_cap()
	while _debris_nodes.size() > cap:
		var node = _debris_nodes.pop_back()
		_fake_debris_nodes.erase(node)
		if is_instance_valid(node):
			node.queue_free()

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
## 「不斷落嚟緊嘅剷斗」；世界沿用 Godot 3D 預設重力（-Y），啱好同
## main.gd 「y 向上」嘅座標系一致，散幣／藍波生成之後自己跌落去，
## 車負責將佢哋撞去邊條門嘅 x 車道。實際物理表現（跟真係跌成點）
## 留返俾實機／編輯器playtest 微調 TUNE 數值，呢度負責嘅係結構同
## 判分事件接駁啱唔啱。
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
var _car_target_x: float = 0.0
var _stun_timer: float = 0.0

var _roller_visual: MeshInstance3D
var _debris_root: Node3D
var _debris_nodes: Array = []
var _fake_debris_nodes: Array = []
var _debris_spawn_accum: float = 0.0
var _gears_active: Array = [] # 每個元素：{"node": Node3D, "timer": float}
var _fps_sample_accum: float = 0.0

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

	_build_walls()
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
	_debris_spawn_accum = 0.0
	_fps_sample_accum = 0.0
	_set_active_visual(true) # 用戶回饋：「門亮」——狂熱先落實發光

func stop() -> void:
	set_process(false)
	_clear_debris()
	_clear_gears()
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
	# 同車場共用埋同一個輸入通道——撳中山腳碎料（tap-to-scoop，見
	# main.gd _on_pile_chunk_input()，已經 set_input_as_handled() 攔咗
	# 一次）嗰粒 InputEventMouseButton 理論上唔應該再行到呢度。加多一重
	# 防守：用「呢個螢幕 Y 有冇喺車場最頂（car_park_max_y）嗰行之下」
	# 判斷，先至當跟指處理。刻意唔用射線同 Z=0 平面求交嘅世界 Y 嚟判斷
	# ——嗰條反向投影近畫面邊緣（好斜嘅視角）容易求出好誇張嘅世界 Y
	# （近乎同平面平行嘅射線，交點會彈得好遠），唔穩陣；呢度用嘅
	# `unproject_position()` 係正向投影，唔會有呢個問題。
	var yard_mid_x: float = (c.yard_x_range.x + c.yard_x_range.y) * 0.5
	var yard_top_screen_y: float = cam.unproject_position(
		_site_to_world_yard_ref(Vector2(yard_mid_x, c.car_park_max_y))
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
	var hit: Variant = Plane(Vector3.BACK, 0.0).intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return # 射線同 Z=0 平面平行（理論上斜視相機唔會撞到，防守性檢查）
	_car_target_x = (hit as Vector3).x

func _site_to_world_yard_ref(v: Vector2) -> Vector3:
	return Vector3(v.x, v.y, 0.0)


# ══════════════════════ 車：巡航向落 + 跟指橫向 ══════════════════════

func _reset_car() -> void:
	car.position = Vector3(0.0, c.car_park_max_y, 0.0)
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
	shape.size = size
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
		var visual := VisualFactory.make_flat_box(Vector3(0.2, height, 1.0), VisualFactory.PALETTE["wall"])
		wall.add_child(visual)
		wall.position = Vector3(side_x, mid_y, 0.0)
		add_child(wall)

func _build_car() -> void:
	car = AnimatableBody3D.new()
	car.name = "Car"
	car.add_to_group("frenzy_car")
	car.sync_to_physics = true
	_car_mesh = VisualFactory.make_metal_box(Vector3(0.5, 0.22, 0.4), Color(0.55, 0.15, 0.15))
	_car_mat = _car_mesh.material_override
	car.add_child(_car_mesh)
	# 四粒低面數輪——純裝飾，唔跟 tier 縮放／變色（見 _apply_car_tier_visual()
	# 淨係改 _car_mesh），先至實機睇落唔會輪同車身一齊怪異咁縮放。
	for wheel_x in [-0.19, 0.19]:
		for wheel_z in [-0.19, 0.19]:
			var wheel := VisualFactory.make_low_poly_cylinder(0.09, 0.06, Color(0.12, 0.12, 0.13))
			wheel.rotation_degrees.z = 90.0
			wheel.position = Vector3(wheel_x, -0.1, wheel_z)
			car.add_child(wheel)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.22, 0.4)
	col.shape = shape
	car.add_child(col)
	car.position = Vector3(0.0, c.car_park_max_y, 0.0)
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
	_roller_visual.position = area.position
	add_child(_roller_visual)

func _build_bridge() -> void:
	var width: float = c.yard_x_range.y - c.yard_x_range.x
	var mid_x: float = (c.yard_x_range.x + c.yard_x_range.y) * 0.5
	var area := _make_area(Vector3(width, 0.1, 0.5))
	area.name = "BridgeArea"
	area.position = Vector3(mid_x, c.lava_bridge_y, 0.0)
	area.body_entered.connect(_on_bridge_entered)
	add_child(area)

	var safe_width: float = c.lava_bridge_safe_x_range.y - c.lava_bridge_safe_x_range.x
	var safe_mid: float = (c.lava_bridge_safe_x_range.x + c.lava_bridge_safe_x_range.y) * 0.5
	var bridge_mesh := VisualFactory.make_flat_box(Vector3(safe_width, 0.05, 0.5), VisualFactory.PALETTE["bridge_wood"])
	bridge_mesh.position = Vector3(safe_mid, c.lava_bridge_y, 0.0)
	add_child(bridge_mesh)

	# 岩浆：加發光，睇落有少少熱感（純裝飾，唔影響 _on_bridge_entered 判定）。
	var lava_mesh := VisualFactory.make_metal_box(
		Vector3(width, 0.04, 0.5), VisualFactory.PALETTE["lava"], VisualFactory.PALETTE["lava"], 0.8
	)
	lava_mesh.position = Vector3(mid_x, c.lava_bridge_y - 0.03, 0.0)
	add_child(lava_mesh)

func _build_gates() -> void:
	for gate_id: String in c.gates.keys():
		var gate: Dictionary = c.gates[gate_id]
		var gx: float = gate["x"]
		var gy: float = gate.get("y", c.gate_y)
		var area := _make_area(Vector3(0.5, 0.08, 0.6))
		area.name = "Gate_%s" % gate_id
		area.position = Vector3(gx, gy, 0.0)
		area.body_entered.connect(_on_gate_entered.bind(gate_id))
		add_child(area)

		var plate := VisualFactory.make_flat_box(Vector3(0.5, 0.04, 0.6), _gate_color(float(gate.get("mult", 1.0))))
		plate.position = area.position
		add_child(plate)

		# ALTA-153 round2：「門亮」——material 一開始已經 emission_enabled，
		# 但 energy 由 _set_active_visual() 揸（開場暗住，見 _ready()）。
		var gate_mat: StandardMaterial3D = plate.material_override
		gate_mat.emission_enabled = true
		gate_mat.emission = gate_mat.albedo_color
		gate_mat.emission_energy_multiplier = 0.0
		_gate_materials.append(gate_mat)

		var label := Label3D.new()
		label.text = "x%s" % str(gate.get("mult", 1.0))
		label.position = area.position + Vector3(0.0, 0.18, 0.0)
		label.pixel_size = 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

func _gate_color(mult: float) -> Color:
	if mult >= 5.0: return Color(0.9, 0.2, 0.9)
	if mult >= 4.0: return Color(0.9, 0.5, 0.1)
	if mult >= 3.0: return Color(0.9, 0.85, 0.1)
	return Color(0.5, 0.8, 0.3)

func _build_furnace() -> void:
	var width: float = c.yard_x_range.y - c.yard_x_range.x
	var mid_x: float = (c.yard_x_range.x + c.yard_x_range.y) * 0.5
	var area := _make_area(Vector3(width, 0.15, 0.6))
	area.name = "FurnaceArea"
	area.position = Vector3(mid_x, c.yard_min_y, 0.0)
	area.body_entered.connect(_on_furnace_entered)
	add_child(area)

func _build_upgrade_pad() -> void:
	var area := _make_area(Vector3(0.5, 0.3, 0.5))
	area.name = "UpgradePadArea"
	area.position = Vector3(c.upgrade_pad_pos.x, c.upgrade_pad_pos.y, 0.0)
	area.body_entered.connect(_on_upgrade_pad_entered)
	add_child(area)
	var visual := VisualFactory.make_metal_box(
		Vector3(0.45, 0.05, 0.45), Color(0.2, 0.8, 0.9), Color(0.2, 0.8, 0.9), 0.8
	)
	visual.position = area.position
	add_child(visual)

	# VR-06b：地上大字代替彈窗——同倍數門嘅 Label3D 一樣做法（issue 視覺
	# 參考：「地上 SELL／UPGRADE 墊…用地上大字 + 價錢，唔用彈窗」；呢個
	# 墊本身冇 Cash 價錢（免費踩過就升級，見 FrenzyState.try_upgrade_pad()），
	# 所以淨顯示墊名）。
	var label := Label3D.new()
	label.text = "UPGRADE"
	label.position = area.position + Vector3(0.0, 0.18, 0.0)
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.75, 0.95, 1.0)
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

func _apply_car_tier_visual() -> void:
	var tier: Dictionary = frenzy.current_tier()
	_car_mesh.scale = Vector3.ONE * float(tier.get("scale", 1.0))
	_car_mat.albedo_color = tier.get("color", Color(0.55, 0.15, 0.15))

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
	var pos := Vector3(x, c.yard_spawn_y, rng.randf_range(-0.1, 0.1))
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


# ══════════════════════ 齒輪（狂熱期間每 gear_drop_interval_secs 一粒） ══════════════════════

func spawn_gear() -> void:
	var x: float = rng.randf_range(c.yard_x_range.x, c.yard_x_range.y)
	var gear := VisualFactory.make_low_poly_cylinder(0.1, 0.1, Color(0.8, 0.85, 0.2), 8, 0.7)
	gear.name = "Gear"
	gear.position = Vector3(x, c.yard_spawn_y, 0.15)
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

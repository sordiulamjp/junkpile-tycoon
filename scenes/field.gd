extends Node3D
## Field v1 (ALTA-228 rebuild by Analyst): ONE flat field in the IG-ad palette
## (purple rock bowl, dark ground), Zone 1 = MineZone core (terraces / rail /
## warehouse / push pads) + free-roaming bulldozer (floating joystick) that
## pushes ore nuggets into the furnace to sell. Replaces main.tscn as the
## entry scene. Site coords: x right, y away from camera, z up.

const SITE_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
const CAM_PITCH_DEG := -60.0
const CAM_FOV := 40.0
const CAM_DIST := 10.5
const CAM_DIST_MIN := 6.5
const CAM_DIST_MAX := 18.0
var _cam_dist := CAM_DIST
var _pinch_last := -1.0
const FIELD_MIN := Vector2(-5.2, -5.4)   # site bounds (x, y) — 用戶：再放大
const FIELD_MAX := Vector2(5.2, 5.6)
const MINE_POS := Vector2(0.0, 3.3)      # MineZone origin (its terraces extend +y)
const FURNACE_POS := Vector2(3.4, -3.2)
const CAR_START := Vector2(0.0, -0.4)
const CAR_Z := 0.14
const JOY_RADIUS_PX := 110.0

# TUNE (IG feel: slow, heavy)
const CAR_SPEED := 1.8
const CAR_ACCEL := 9.0
const CAR_TURN_LERP := 10.0
const CARGO_CAP := [30, 60, 100] # 鏟斗 tier 0/1/2 可以載幾多粒
const CAPTURE_R := 0.9
const PUSH_IMPULSE := 0.35
const ORE_RADIUS := 0.04
const ORE_COUNT := 5600
const KICK_RADIUS := 1.0   # 車前方呢個半徑內嘅礦轉做真剛體，俾鏟斗物理推
const KICK_LIFETIME := 1.0
const KICK_BUDGET := 260
const RESPAWN_PER_SEC := 6.0

var c: GameConstants
var state: GameState
var frenzy: FrenzyState
var mine: MineZone
var rng := RandomNumberGenerator.new()

var _world: Node3D
var _site: Node3D
var _cam: Camera3D
var _car: CharacterBody3D
var _car_body: Node3D
var _blade: MeshInstance3D
var _car_vel := Vector2.ZERO
var _joy_down := false
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _joy_ring: Control
var _joy_knob: Control
var _keys_vec := Vector2.ZERO

var _pool_mmi: Dictionary = {}     # tier -> MultiMeshInstance3D
var _slots: Array = []             # {tier, idx, pos, active, gone}
var _kicked: Array = []            # {slot, node, t}
var _kick_root: Node3D
var _scan_accum := 0.0
var _respawn_accum := 0.0
var _furnace_glow: StandardMaterial3D
var _furnace_flash := 0.0
var _cargo: Array = []            # {tier, node}
var _cargo_root: Node3D
var _furnace_node: Node3D
var _furnace_arrow: Control
var _spill_accum := 0.0
var _bottleneck_icons: Dictionary = {}

var _hud: CanvasLayer
var _cash_label: Label
var _comp_label: Label
var _eco_label: Label
var _status_label: Label
var _frenzy_button: Button
var _save_accum := 0.0
var _autodrive := false
var _autodrive_t := 0.0

# ── VR-16 掛機自動化 ──
# issue 原文「Components 買（第一次 10 粒，之後遞增）或者 Cash 500 解鎖」——
# AI 司機係單次永久解鎖（一個 bool），冇「買完一次再買一次」呢件事，所以
# 「之後遞增」呢句唔適用；實作做「10 Components 或 500 Cash，邊樣夠先扣
# 邊樣（component 平，優先用）」，兩條路都解鎖同一個永久開關。
const AI_COST_CASH := 500.0
const AI_COST_COMPONENTS := 10.0
const MGR_COST := 2000.0
const AI_IDLE_SECS := 3.0 # 放手 3 秒後 AI 接返（用戶隨時可以再接手）
const AI_SPEED_MULT := 0.65
var _ai_unlocked := false
var _ai_on := true
var _ai_active := false
var _idle_t := 0.0
var _ai_mode := "heap"
var _ai_target := Vector2.INF
var _ai_retarget_t := 0.0
var _mgr_unlocked := false
var _mgr_on := true
var _mgr_accum := 0.0
var _team_accum := 0.0
var _ai_button: Button
var _mgr_button: Button
var _offline_panel: PanelContainer
var _offline_label: Label
var _offline_claim_button: Button
var _offline_double_button: Button
var _offline_pending := 0.0


func _ready() -> void:
	rng.randomize()
	c = GameConstants.new()
	state = GameState.new(c)
	frenzy = FrenzyState.new(c)
	_autodrive = "--autodrive" in OS.get_cmdline_user_args()
	var _demo_ai: bool = "--ai" in OS.get_cmdline_user_args() # debug：即刻解鎖 AI 司機 + 經理（渲染示範用）
	# Reviewer round 3：舊碼用私家 field_cash／field_components／field_eco
	# 三個欄位讀寫存檔，繞過 VR-11 嘅 Wallet／Save autoload 同共用嘅
	# "cash"／"components"／"eco" 欄位——同一份存檔兩個錢包。跟返
	# main.gd _ready() 同一套做法：有存檔先讀（冇存檔就維持
	# GameState._init() 啱啱設低嘅 c.starting_cash 開場值，唔會俾
	# default_state() 嘅 cash=0 冚咗），讀完／冇讀都經 _sync_wallet_from_state()
	# 令 Wallet 同 state 一致。
	var save_exists := FileAccess.file_exists(SaveManager.SAVE_PATH)
	var saved: Dictionary = {}
	if save_exists:
		saved = Save.load_and_apply_wallet()
		state.cash = Wallet.cash
		state.components = Wallet.components
		state.eco = Wallet.eco
	_ai_unlocked = bool(saved.get("field_ai_unlocked", false))
	_ai_on = bool(saved.get("field_ai_on", true))
	_mgr_unlocked = bool(saved.get("field_mgr_unlocked", false))
	_mgr_on = bool(saved.get("field_mgr_on", true))
	if _demo_ai:
		_ai_unlocked = true
		_mgr_unlocked = true
	_sync_wallet_from_state()
	_build_world()
	_build_zone1(saved.get("mine_zone", {}))
	_build_car()
	_build_ore_pool()
	_clear_ore_around(Vector2(_car.position.x, _car.position.y), 1.0)
	_build_hud()
	mine.attach_panel(_hud)
	get_viewport().physics_object_picking = true
	_settle_offline(saved)


# ══════════════════════ world / environment ══════════════════════

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2B2233")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#B9A6CC")
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, 28.0, 0.0)
	light.light_color = Color(1.0, 0.95, 0.9)
	light.light_energy = 1.15
	light.shadow_enabled = true
	_world.add_child(light)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.rotation_degrees = Vector3(CAM_PITCH_DEG, 0.0, 0.0)
	_cam.current = true
	_world.add_child(_cam)

	_site = Node3D.new()
	_site.name = "Site"
	_site.basis = SITE_BASIS
	_world.add_child(_site)

	_build_ground()
	_build_rock_bowl()

func _site_to_local(v: Vector2, z: float = 0.0) -> Vector3:
	return Vector3(v.x, v.y, z)

func _build_ground() -> void:
	var w: float = FIELD_MAX.x - FIELD_MIN.x + 4.0
	var h: float = FIELD_MAX.y - FIELD_MIN.y + 4.0
	var mid := (FIELD_MIN + FIELD_MAX) * 0.5
	var slab := VisualFactory.make_flat_box(Vector3(w, h, 0.06), Color(MineConstants.PALETTE["ground"]))
	slab.position = Vector3(mid.x, mid.y, -0.03)
	_site.add_child(slab)
	# tread marks
	for _i in range(18):
		var t := VisualFactory.make_flat_box(Vector3(rng.randf_range(0.5, 1.4), 0.08, 0.005), Color("#4E4352"))
		t.position = Vector3(rng.randf_range(FIELD_MIN.x, FIELD_MAX.x), rng.randf_range(FIELD_MIN.y, FIELD_MAX.y * 0.4), 0.003)
		t.rotation.z = rng.randf_range(-0.6, 0.6)
		_site.add_child(t)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, 0.2)
	col.shape = shape
	floor_body.add_child(col)
	floor_body.position = Vector3(mid.x, mid.y, -0.1)
	_site.add_child(floor_body)

func _rock(size: Vector3, tone: Color) -> Node3D:
	var root := Node3D.new()
	var body := VisualFactory.make_flat_box(Vector3(size.x, size.y, size.z * 0.72), tone)
	body.position = Vector3(0.0, 0.0, size.z * 0.36 - 0.05)
	root.add_child(body)
	var cap := VisualFactory.make_rock_facet(Vector3(size.x, size.z * 0.28, size.y), tone.lightened(0.15), rng.randf_range(0.2, 0.8))
	cap.rotation_degrees.x = 90.0
	cap.position = Vector3(0.0, 0.0, size.z * 0.72 + size.z * 0.14 - 0.05)
	root.add_child(cap)
	return root

func _build_rock_bowl() -> void:
	var walls := Node3D.new()
	walls.name = "RockBowl"
	_site.add_child(walls)
	var tones := [Color(MineConstants.PALETTE["wall"]), Color(MineConstants.PALETTE["wall_light"]), Color(MineConstants.PALETTE["wall_dark"])]
	# left / right columns
	var y: float = FIELD_MIN.y - 0.4
	while y <= FIELD_MAX.y + 0.6:
		for side in [-1.0, 1.0]:
			var base_x: float = (FIELD_MIN.x - 0.5) if side < 0.0 else (FIELD_MAX.x + 0.5)
			for layer in range(2):
				var sz := Vector3(rng.randf_range(0.7, 1.1), rng.randf_range(0.5, 0.8), rng.randf_range(1.0, 1.7) - float(layer) * 0.4)
				var r := _rock(sz, tones[rng.randi_range(0, 2)])
				r.position = Vector3(base_x + side * (0.3 + float(layer) * 0.6) + rng.randf_range(-0.1, 0.1), y + rng.randf_range(-0.1, 0.1), 0.0)
				r.rotation.z = rng.randf_range(-0.3, 0.3)
				walls.add_child(r)
		y += 0.6
	# front row (near camera) low rocks, back row behind the mine
	var x: float = FIELD_MIN.x - 0.4
	while x <= FIELD_MAX.x + 0.4:
		var szf := Vector3(rng.randf_range(0.6, 0.9), rng.randf_range(0.5, 0.7), rng.randf_range(0.5, 0.9))
		var rf := _rock(szf, tones[rng.randi_range(0, 2)])
		rf.position = Vector3(x + rng.randf_range(-0.1, 0.1), FIELD_MIN.y - 0.55 + rng.randf_range(-0.1, 0.1), 0.0)
		walls.add_child(rf)
		var szb := Vector3(rng.randf_range(0.7, 1.0), rng.randf_range(0.6, 0.9), rng.randf_range(1.6, 2.4))
		var rb := _rock(szb, tones[rng.randi_range(0, 2)])
		rb.position = Vector3(x + rng.randf_range(-0.1, 0.1), MINE_POS.y + float(MineConstants.LAYER_COUNT) * MineConstants.LAYER_DEPTH_STEP + 0.7 + rng.randf_range(0.0, 0.3), 0.0)
		walls.add_child(rb)
		x += 0.62
	# invisible colliders on the four edges
	var mid := (FIELD_MIN + FIELD_MAX) * 0.5
	var w: float = FIELD_MAX.x - FIELD_MIN.x
	var h: float = FIELD_MAX.y - FIELD_MIN.y
	for spec in [
		[Vector3(FIELD_MIN.x - 0.15, mid.y, 0.4), Vector3(0.3, h + 1.0, 1.0)],
		[Vector3(FIELD_MAX.x + 0.15, mid.y, 0.4), Vector3(0.3, h + 1.0, 1.0)],
		[Vector3(mid.x, FIELD_MIN.y - 0.15, 0.4), Vector3(w + 1.0, 0.3, 1.0)],
		[Vector3(mid.x, FIELD_MAX.y + 0.15, 0.4), Vector3(w + 1.0, 0.3, 1.0)],
	]:
		var sb := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		col.shape = shape
		sb.add_child(col)
		sb.position = spec[0]
		_site.add_child(sb)


# ══════════════════════ zone 1: MineZone + furnace ══════════════════════

func _build_zone1(saved: Dictionary) -> void:
	mine = MineZone.new()
	mine.name = "MineZone"
	mine.position = _site_to_local(MINE_POS)
	_site.add_child(mine)
	mine.setup(state, frenzy, saved)

	# furnace / sell station: push ore into the fire mouth to sell
	var furnace := Node3D.new()
	furnace.name = "Furnace"
	furnace.position = _site_to_local(FURNACE_POS)
	_site.add_child(furnace)
	_furnace_node = furnace
	var body := VisualFactory.make_metal_box(Vector3(1.1, 0.8, 0.6), Color(MineConstants.PALETTE["furnace"]))
	body.position = Vector3(0.0, 0.2, 0.3)
	furnace.add_child(body)
	# Reviewer round 3：熔爐本體純粹係 mesh，冇 collider，車可以直穿——
	# 加 StaticBody3D 貼實爐身，SellArea（下面）維持獨立 Area3D 唔受影響。
	var body_collider := StaticBody3D.new()
	var body_col := CollisionShape3D.new()
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(0.9, 0.7, 0.55)
	body_col.shape = body_shape
	body_collider.add_child(body_col)
	body_collider.position = body.position
	furnace.add_child(body_collider)
	var chimney := VisualFactory.make_metal_box(Vector3(0.22, 0.22, 0.35), Color(MineConstants.PALETTE["furnace"]).lightened(0.1))
	chimney.position = Vector3(0.28, 0.35, 0.7)
	furnace.add_child(chimney)
	var mouth := VisualFactory.make_metal_box(Vector3(0.6, 0.06, 0.32), Color(MineConstants.PALETTE["furnace_fire"]), Color(MineConstants.PALETTE["furnace_fire"]), 1.8)
	mouth.position = Vector3(0.0, -0.16, 0.2)
	_furnace_glow = mouth.material_override
	furnace.add_child(mouth)
	# 用戶：全方位都可以收碎料——爐四周一圈紫墊，任何方向入到都賣
	var pad := VisualFactory.make_flat_box(Vector3(2.4, 2.2, 0.02), Color(MineConstants.PALETTE["pad"]))
	pad.position = Vector3(0.0, 0.2, 0.01)
	furnace.add_child(pad)
	# 用戶 2026-09-14：圖示代替文字——賣礦墊上放一疊金幣 + 箭嘴指向爐口
	for i in range(3):
		var coin := VisualFactory.make_low_poly_cylinder(0.11, 0.035, Color(MineConstants.PALETTE["ore_gold"]), 10, 0.5)
		coin.rotation_degrees.x = 90.0
		coin.position = Vector3(-0.2, -0.55, 0.03 + float(i) * 0.04)
		furnace.add_child(coin)
	var arrow := VisualFactory.make_flat_box(Vector3(0.3, 0.07, 0.02), Color.WHITE)
	arrow.position = Vector3(0.12, -0.5, 0.03)
	furnace.add_child(arrow)
	var head := VisualFactory.make_rock_facet(Vector3(0.18, 0.02, 0.16), Color.WHITE, 0.5)
	head.rotation_degrees = Vector3(90.0, 0.0, -90.0)
	head.position = Vector3(0.34, -0.5, 0.03)
	furnace.add_child(head)
	var area := Area3D.new()
	area.name = "SellArea"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.2, 1.0)
	col.shape = shape
	area.add_child(col)
	area.position = Vector3(0.0, 0.2, 0.3)
	area.body_entered.connect(_on_sell_area_entered)
	furnace.add_child(area)


# ══════════════════════ car (free roaming) ══════════════════════

func _build_car() -> void:
	_car = CharacterBody3D.new()
	_car.name = "Car"
	_car.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# 用戶：車出世踩住礦會卡——車身碰撞底部抬高到 0.09，礦粒（高 0.08）可以喺車底穿過，
	# 只有鏟斗掂地推礦
	shape.size = Vector3(0.44, 0.36, 0.16)
	col.shape = shape
	col.position = Vector3(0.0, -0.05, 0.06)
	_car.add_child(col)
	_car.position = _site_to_local(CAR_START, CAR_Z)
	_site.add_child(_car)

	_car_body = Node3D.new()
	_car.add_child(_car_body)
	_cargo_root = Node3D.new()
	_cargo_root.name = "Cargo"
	_car.add_child(_cargo_root)
	var body := VisualFactory.make_metal_box(Vector3(0.3, 0.32, 0.16), Color("#F2C230"))
	_car_body.add_child(body)
	var cab := VisualFactory.make_metal_box(Vector3(0.18, 0.16, 0.12), Color("#F7D35A"))
	cab.position = Vector3(0.0, -0.04, 0.13)
	_car_body.add_child(cab)
	for sx in [-1.0, 1.0]:
		var track := VisualFactory.make_metal_box(Vector3(0.09, 0.4, 0.1), Color("#26262B"))
		track.position = Vector3(sx * 0.2, 0.0, -0.05)
		_car_body.add_child(track)
	_rebuild_blade()

## 鏟斗按 tier 變闊變高（升級要「見得到」）：視覺 + 真碰撞一齊重砌
const BLADE_SCALE := [1.0, 1.35, 1.7]
var _blade_nodes: Array = []
var _blade_tier_built := -1
func _blade_w() -> float:
	return float(BLADE_SCALE[clampi(mine.state.push_tier if mine != null else 0, 0, 2)])
func _rebuild_blade() -> void:
	for n in _blade_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_blade_nodes.clear()
	var w: float = _blade_w()
	_blade_tier_built = mine.state.push_tier if mine != null else 0
	var col_tint := Color("#F2C230").darkened(0.1) if w < 1.2 else (Color("#F2A030") if w < 1.6 else Color("#FF8C2A"))
	for i in range(5):
		var a: float = (float(i) - 2.0) * 0.32
		var seg := VisualFactory.make_metal_box(Vector3(0.16 * w, 0.04, 0.16 + 0.05 * (w - 1.0)), col_tint)
		seg.position = Vector3(sin(a) * 0.34 * w, 0.2 + cos(a) * 0.14 * w, 0.0)
		seg.rotation.z = -a
		_car_body.add_child(seg)
		_blade_nodes.append(seg)
		if i == 2:
			_blade = seg
		var bc := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.17 * w, 0.05, 0.22)
		bc.shape = bs
		bc.position = Vector3(sin(a) * 0.34 * w, 0.2 + cos(a) * 0.14 * w, -0.03)
		bc.rotation.z = -a
		_car.add_child(bc)
		_blade_nodes.append(bc)

func _physics_process(delta: float) -> void:
	var input_vec: Vector2 = _joy_vec if _joy_down else _keys_vec
	if input_vec.length() > 0.05 or _joy_down:
		_idle_t = 0.0
		_ai_active = false
	else:
		_idle_t += delta
		if _ai_unlocked and _ai_on and _idle_t >= AI_IDLE_SECS and not _autodrive:
			_ai_active = true
	if _ai_active:
		input_vec = _ai_steer(delta)
	if _autodrive:
		# demo/debug: drive heap -> furnace -> heap ... (waypoints in site coords)
		_autodrive_t += delta
		var wps := [Vector2(-2.2, 0.4), Vector2(1.4, 0.2), FURNACE_POS + Vector2(-0.2, -0.9), Vector2(-0.6, -1.6), FURNACE_POS + Vector2(-0.9, 0.2)]
		var wp: Vector2 = wps[int(_autodrive_t / 3.2) % wps.size()]
		var to: Vector2 = wp - Vector2(_car.position.x, _car.position.y)
		input_vec = to.normalized() if to.length() > 0.15 else Vector2.ZERO
	var speed_mult: float = (1.5 if frenzy.active else 1.0) * (AI_SPEED_MULT if _ai_active else 1.0)
	var target: Vector2 = input_vec.limit_length(1.0) * CAR_SPEED * speed_mult
	_car_vel = _car_vel.move_toward(target, CAR_ACCEL * delta)
	_car.velocity = SITE_BASIS * Vector3(_car_vel.x, _car_vel.y, 0.0)
	_car.move_and_slide()
	# keep on the ground plane
	_car.position.z = CAR_Z
	_rigidize_front_tick()
	# 用戶：推唔郁礦——CharacterBody3D 本身唔會推剛體，要自己傳速度：
	# 撞到嘅礦沿碰撞法線攞到最少同車一樣嘅速度（似真係俾鏟斗推住走）
	var vcar: Vector3 = _car.velocity
	for i in range(_car.get_slide_collision_count()):
		var kc := _car.get_slide_collision(i)
		var body := kc.get_collider()
		if body is RigidBody3D:
			var push_dir: Vector3 = -kc.get_normal()
			push_dir.y = 0.0 # 世界 y 係高度，唔向上推
			if push_dir.length() < 0.01:
				continue
			push_dir = push_dir.normalized()
			var v_need: float = vcar.dot(push_dir) + 0.25
			var v_has: float = (body as RigidBody3D).linear_velocity.dot(push_dir)
			if v_need > v_has:
				(body as RigidBody3D).linear_velocity += push_dir * (v_need - v_has)
	# face movement direction
	if _car_vel.length() > 0.05:
		var ang: float = atan2(_car_vel.y, _car_vel.x) - PI * 0.5
		_car.rotation.z = lerp_angle(_car.rotation.z, ang, CAR_TURN_LERP * delta)
	_pool_tick(delta)

func _unhandled_input(event: InputEvent) -> void:
	# 縮放：滾輪／手勢；用戶要「睇得晒全畫面」就拉遠
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_cam_dist = clampf(_cam_dist - 0.8, CAM_DIST_MIN, CAM_DIST_MAX)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_cam_dist = clampf(_cam_dist + 0.8, CAM_DIST_MIN, CAM_DIST_MAX)
		return
	if event is InputEventMagnifyGesture:
		_cam_dist = clampf(_cam_dist / event.factor, CAM_DIST_MIN, CAM_DIST_MAX)
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
			return
		if pressed:
			_joy_down = true
			_joy_origin = event.position
			_joy_vec = Vector2.ZERO
			_ai_active = false # 用戶隨時接手：一按落即刻停 AI
			_idle_t = 0.0
			_show_joystick(true)
		else:
			_joy_down = false
			_joy_vec = Vector2.ZERO
			_show_joystick(false)
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _joy_down:
		var d: Vector2 = (event.position - _joy_origin) / JOY_RADIUS_PX
		d = d.limit_length(1.0)
		_joy_vec = Vector2(d.x, -d.y) # screen up = site +y (away from camera)
		if _joy_knob:
			_joy_knob.position = _joy_origin + d * JOY_RADIUS_PX - _joy_knob.size * 0.5
	elif event is InputEventKey:
		var v := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1.0
		_keys_vec = v

func _show_joystick(on: bool) -> void:
	if _joy_ring == null:
		return
	_joy_ring.visible = on
	_joy_knob.visible = on
	if on:
		_joy_ring.position = _joy_origin - _joy_ring.size * 0.5
		_joy_knob.position = _joy_origin - _joy_knob.size * 0.5


# ══════════════════════ ore pool (MultiMesh + kick to rigid) ══════════════════════

func _build_ore_pool() -> void:
	_kick_root = Node3D.new()
	_kick_root.name = "KickedOre"
	_site.add_child(_kick_root)
	var tiers := {"silver": [0.85, Color(MineConstants.PALETTE["ore_silver"]), 1.0], "gold": [0.15, Color(MineConstants.PALETTE["ore_gold"]), 1.3]}
	var blobs := [Vector2(-2.6, 0.6), Vector2(1.8, 0.4), Vector2(-0.8, -1.9), Vector2(1.1, 1.8), Vector2(-3.2, -3.0), Vector2(3.0, -0.8), Vector2(-0.2, 0.2)]
	for tier: String in tiers.keys():
		var count: int = int(ORE_COUNT * float(tiers[tier][0]))
		var mmi := VisualFactory.make_ore_pool_multimesh(ORE_RADIUS, tiers[tier][1], 0.35 if tier == "gold" else 0.0, count)
		mmi.name = "Pool_%s" % tier
		_site.add_child(mmi)
		_pool_mmi[tier] = mmi
		for i in range(count):
			var ctr: Vector2 = blobs[rng.randi_range(0, blobs.size() - 1)]
			var a := rng.randf_range(0.0, TAU)
			var r := sqrt(rng.randf()) * 0.8
			var pos := Vector3(ctr.x + cos(a) * r * 1.2, ctr.y + sin(a) * r, ORE_RADIUS * float(tiers[tier][2]))
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(tiers[tier][2])), pos))
			_slots.append({"tier": tier, "idx": i, "pos": pos, "scale": float(tiers[tier][2]), "active": false, "gone": false})

func _clear_ore_around(center: Vector2, radius: float) -> void:
	var r2 := radius * radius
	for s: Dictionary in _slots:
		if s["gone"] or s["active"]:
			continue
		var p: Vector3 = s["pos"]
		if Vector2(p.x, p.y).distance_squared_to(center) < r2:
			s["gone"] = true
			_hide_slot(s)

func _hide_slot(s: Dictionary) -> void:
	(_pool_mmi[s["tier"]] as MultiMeshInstance3D).multimesh.set_instance_transform(s["idx"], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))

func _show_slot(s: Dictionary) -> void:
	(_pool_mmi[s["tier"]] as MultiMeshInstance3D).multimesh.set_instance_transform(s["idx"], Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(s["scale"])), s["pos"]))

## 車前方半徑內嘅靜態礦轉做真剛體（無衝力），俾弧形鏟斗物理推住、堆喺鏟內
func _rigidize_front_tick() -> void:
	_scan_accum += get_physics_process_delta_time()
	if _scan_accum < 0.08:
		return
	_scan_accum = 0.0
	var budget: int = KICK_BUDGET - _kicked.size()
	if budget <= 0:
		return
	var cp: Vector3 = _car.position
	var r2: float = (KICK_RADIUS + 0.4) * (KICK_RADIUS + 0.4)
	var inv: Transform3D = _car.transform.affine_inverse()
	var cands: Array = []
	for s: Dictionary in _slots:
		if s["active"] or s["gone"]:
			continue
		var p: Vector3 = s["pos"]
		if p.distance_squared_to(cp) > r2:
			continue
		var lp: Vector3 = inv * p
		if lp.y < -0.4 or lp.y > 1.2 * _blade_w() or absf(lp.x) > 0.75 * _blade_w():
			continue
		cands.append([lp.y, s])
	cands.sort_custom(func(a, b): return a[0] < b[0]) # 最貼近車頭嘅先轉（佔用預算最有用）
	for c_ in cands:
		if budget <= 0:
			break
		_activate_slot(c_[1])
		budget -= 1

func _pool_tick(delta: float) -> void:
	for k: Dictionary in _kicked.duplicate():
		var node: RigidBody3D = k["node"]
		if not is_instance_valid(node):
			_kicked.erase(k)
			continue
		k["t"] += delta
		var far: bool = node.position.distance_to(_car.position) > KICK_RADIUS * 1.5
		var still: bool = node.linear_velocity.length() < 0.05
		if k["t"] >= KICK_LIFETIME and far and still:
			_settle_kick(k)
	# respawn: ore flows out of the mine over time
	_respawn_accum += delta * RESPAWN_PER_SEC
	while _respawn_accum >= 1.0:
		_respawn_accum -= 1.0
		for _try in range(6):
			var s: Dictionary = _slots[rng.randi_range(0, _slots.size() - 1)]
			if s["gone"] and not s["active"]:
				s["gone"] = false
				_show_slot(s)
				break
	# ore spill: nuggets tumble out of the mine entrance into the heap (visual only)
	_spill_accum += delta * 3.0
	while _spill_accum >= 1.0:
		_spill_accum -= 1.0
		_spawn_spill_nugget()
	if _furnace_flash > 0.0:
		_furnace_flash -= delta
		_furnace_glow.emission_energy_multiplier = 1.8 + 2.5 * clampf(_furnace_flash, 0.0, 1.0)

func _spawn_spill_nugget() -> void:
	var gold: bool = rng.randf() < 0.15
	var n := VisualFactory.make_ore_ball(ORE_RADIUS * (1.3 if gold else 1.0), Color(MineConstants.PALETTE["ore_gold"] if gold else MineConstants.PALETTE["ore_silver"]), 0.3 if gold else 0.0)
	var start := Vector3(MINE_POS.x + rng.randf_range(-0.25, 0.25), MINE_POS.y + 0.1, 0.45)
	var target := Vector3(MINE_POS.x + rng.randf_range(-0.8, 0.8), MINE_POS.y - rng.randf_range(0.7, 1.4), ORE_RADIUS)
	n.position = start
	_site.add_child(n)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "position:x", target.x, 0.7)
	tw.tween_property(n, "position:y", target.y, 0.7)
	tw.tween_property(n, "position:z", target.z, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(n.queue_free).set_delay(0.6)

## 鏟斗前方捕獲：礦粒入到鏟斗前嘅捕獲區就上車（IG 式：車前堆住一堆礦帶走），滿咗就唔再收
func _capture_tick() -> void:
	var cap: int = CARGO_CAP[clampi(mine.state.push_tier, 0, 2)]
	if _cargo.size() >= cap:
		return
	var cp: Vector3 = _car.position
	var r2: float = CAPTURE_R * CAPTURE_R
	var inv: Transform3D = _car.transform.affine_inverse()
	for s: Dictionary in _slots:
		if _cargo.size() >= cap:
			break
		if s["active"] or s["gone"]:
			continue
		var p: Vector3 = s["pos"]
		if p.distance_squared_to(cp) > r2:
			continue
		var lp: Vector3 = inv * p # car-local: +y forward
		if lp.y < 0.05 or lp.y > 0.62 or absf(lp.x) > 0.36:
			continue
		s["gone"] = true
		_hide_slot(s)
		_add_cargo(s["tier"], float(s["scale"]), p)

func _add_cargo(tier: String, sc: float, from_site: Vector3 = Vector3.INF) -> void:
	var i: int = _cargo.size()
	var ball := VisualFactory.make_ore_ball(ORE_RADIUS * sc, Color(MineConstants.PALETTE["ore_gold"] if tier == "gold" else MineConstants.PALETTE["ore_silver"]), 0.3 if tier == "gold" else 0.0)
	var cols := 6
	var layer: int = i / (cols * 3)
	var idx: int = i % (cols * 3)
	var row: int = idx / cols
	var col: int = idx % cols
	var dest := Vector3(-0.22 + float(col) * 0.088 + rng.randf_range(-0.01, 0.01), 0.24 + float(row) * 0.085, 0.02 + float(layer) * 0.07)
	_cargo_root.add_child(ball)
	_cargo.append({"tier": tier, "node": ball})
	# 回收動畫：礦粒由地面「跳」上鏟斗（0.18s 弧線）
	if from_site != Vector3.INF:
		ball.position = _cargo_root.to_local(_site.to_global(from_site))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(ball, "position:x", dest.x, 0.18).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ball, "position:y", dest.y, 0.18).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ball, "position:z", dest.z + 0.12, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(ball, "position:z", dest.z, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		ball.position = dest

func _dump_cargo() -> void:
	if _cargo.is_empty():
		return
	var mult: float = mine.state.c.push_tier_scoop_mult[clampi(mine.state.push_tier, 0, 2)]
	var fmult: float = mine.state.c.frenzy_income_mult if frenzy.active else 1.0
	var mouth_local: Vector3 = _furnace_node.position + Vector3(0.0, 0.2, 0.55) # 爐頂口（site 座標）
	var total := 0.0
	var n: int = _cargo.size()
	for i in range(n):
		var cgo: Dictionary = _cargo[i]
		var ball: Node3D = cgo["node"]
		var value: float = mine.state.c.ore_value(cgo["tier"]) * mult * fmult
		total += value
		# 回收動畫：礦粒逐粒由鏟斗飛入爐口（弧線 + 縮細），每粒落爐即加錢
		var gp: Vector3 = ball.global_position
		_cargo_root.remove_child(ball)
		_site.add_child(ball)
		ball.global_position = gp
		var delay: float = float(i) * 0.025
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.set_parallel(true)
		tw.tween_property(ball, "position:x", mouth_local.x, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ball, "position:y", mouth_local.y, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ball, "position:z", mouth_local.z + 0.45, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(ball, "position:z", mouth_local.z, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(ball, "scale", Vector3.ONE * 0.3, 0.16)
		tw.chain().tween_callback(func() -> void:
			state.cash += value
			_furnace_flash = 1.0
			_spawn_spark(mouth_local)
			ball.queue_free())
	_cargo.clear()
	_spawn_cash_popup(mouth_local, total)
	SfxPlayer.play("pile_mine")

## 車入爐區：鏟斗弧內（車前方）嘅剛體礦全部賣出，逐粒飛入爐口
func _sell_bucket_ore() -> void:
	var inv: Transform3D = _car.transform.affine_inverse()
	var mult: float = mine.state.c.push_tier_scoop_mult[clampi(mine.state.push_tier, 0, 2)]
	var fmult: float = mine.state.c.frenzy_income_mult if frenzy.active else 1.0
	var mouth_local: Vector3 = _furnace_node.position + Vector3(0.0, 0.2, 0.55)
	var total := 0.0
	var i := 0
	for k: Dictionary in _kicked.duplicate():
		var node: RigidBody3D = k["node"]
		if not is_instance_valid(node):
			_kicked.erase(k)
			continue
		var lp: Vector3 = inv * node.position
		if lp.y < -0.1 or lp.y > 0.9 * _blade_w() or absf(lp.x) > 0.6 * _blade_w():
			continue
		var s: Dictionary = k["slot"]
		var value: float = mine.state.c.ore_value(s["tier"]) * mult * fmult
		total += value
		s["gone"] = true
		s["active"] = false
		_kicked.erase(k)
		node.freeze = true
		node.collision_layer = 0
		node.collision_mask = 0
		var tw := create_tween()
		tw.tween_interval(float(i) * 0.02)
		tw.set_parallel(true)
		tw.tween_property(node, "position:x", mouth_local.x, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "position:y", mouth_local.y, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "position:z", mouth_local.z + 0.45, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(node, "position:z", mouth_local.z, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "scale", Vector3.ONE * 0.3, 0.16)
		tw.chain().tween_callback(func() -> void:
			state.cash += value
			_furnace_flash = 1.0
			_spawn_spark(mouth_local)
			node.queue_free())
		i += 1
	if total > 0.0:
		_spawn_cash_popup(mouth_local, total)
		SfxPlayer.play("pile_mine")

func _spawn_spark(at: Vector3) -> void:
	for _i in range(2):
		var sp := VisualFactory.make_metal_box(Vector3(0.04, 0.04, 0.04), Color(MineConstants.PALETTE["furnace_fire"]), Color(MineConstants.PALETTE["furnace_fire"]), 2.0)
		sp.position = at
		_site.add_child(sp)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "position", at + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.15, 0.15), rng.randf_range(0.35, 0.7)), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "scale", Vector3.ZERO, 0.45)
		tw.chain().tween_callback(sp.queue_free)

func _spawn_cash_popup(at: Vector3, amount: float) -> void:
	var lbl := Label3D.new()
	lbl.text = "+%s" % _fmt(amount)
	lbl.font_size = 120
	lbl.pixel_size = 0.004
	lbl.outline_size = 16
	lbl.modulate = Color(1.0, 0.85, 0.3)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = at + Vector3(0.0, 0.0, 0.6)
	_site.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:z", at.z + 1.5, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(lbl.queue_free)

func _activate_slot(s: Dictionary) -> void:
	s["active"] = true
	_hide_slot(s)
	var body := RigidBody3D.new()
	body.mass = 0.15
	body.set_meta("slot", s)
	var radius: float = ORE_RADIUS * float(s["scale"])
	body.add_child(VisualFactory.make_ore_ball(radius, Color(MineConstants.PALETTE["ore_gold"] if s["tier"] == "gold" else MineConstants.PALETTE["ore_silver"]), 0.3 if s["tier"] == "gold" else 0.0))
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	body.position = s["pos"]
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.05
	body.physics_material_override = mat
	body.mass = 0.05
	body.linear_damp = 2.5
	body.angular_damp = 4.0
	body.continuous_cd = true
	body.can_sleep = false
	_kick_root.add_child(body)
	_kicked.append({"slot": s, "node": body, "t": 0.0})

func _settle_kick(k: Dictionary) -> void:
	_kicked.erase(k)
	var s: Dictionary = k["slot"]
	var node: RigidBody3D = k["node"]
	s["active"] = false
	if is_instance_valid(node):
		var p: Vector3 = node.position
		if p.x > FIELD_MIN.x and p.x < FIELD_MAX.x and p.y > FIELD_MIN.y and p.y < FIELD_MAX.y:
			s["pos"] = Vector3(p.x, p.y, ORE_RADIUS * float(s["scale"]))
			_show_slot(s)
		else:
			s["gone"] = true
		node.queue_free()

func _on_sell_area_entered(body: Node3D) -> void:
	if body == _car:
		_sell_bucket_ore()
		return
	if not (body is RigidBody3D) or not body.has_meta("slot"):
		return
	var s: Dictionary = body.get_meta("slot")
	# 舊碼 `push_tier_scoop_mult[clampi(push_tier, 0, 2)]` 錯咗一格——
	# push_tier=1／2 嗰陣攞咗下一級嘅倍率，等同預支未買嘅升級。改用
	# MineState 自己嗰個方法（同礦堆 tap 收礦、mine_zone.gd
	# `_on_pile_tap()` 同一條公式），唔再喺呢度重複一份索引邏輯。
	var mult: float = mine.state.scoop_value_mult()
	var value: float = mine.state.c.ore_value(s["tier"]) * mult * (mine.state.c.frenzy_income_mult if frenzy.active else 1.0)
	state.cash += value
	s["active"] = false
	s["gone"] = true
	for k: Dictionary in _kicked:
		if k["node"] == body:
			_kicked.erase(k)
			break
	body.queue_free()
	_furnace_flash = 1.0
	SfxPlayer.play("pile_mine")


# ══════════════════════ camera / HUD / loop ══════════════════════

func _process(delta: float) -> void:
	state.tick(delta)
	mine.tick(delta)
	var ev: Dictionary = frenzy.tick(delta)
	if ev.get("ended", false):
		SfxPlayer.play("frenzy_start")
	_follow_camera(delta)
	_watch_upgrades()
	_manager_tick(delta)
	_surface_team_tick(delta)
	_refresh_hud()
	_save_accum += delta
	if _save_accum >= 10.0:
		_save_accum = 0.0
		_save_game()

func _follow_camera(delta: float) -> void:
	var target_site := Vector2(_car.position.x, _car.position.y)
	target_site.x = clampf(target_site.x, FIELD_MIN.x + 1.4, FIELD_MAX.x - 1.4)
	target_site.y = clampf(target_site.y + 0.6, FIELD_MIN.y + 1.6, FIELD_MAX.y + 0.2)
	var target_world: Vector3 = _site.to_global(Vector3(target_site.x, target_site.y, 0.0))
	var desired: Vector3 = target_world + _cam.global_transform.basis.z * _cam_dist
	_cam.global_position = _cam.global_position.lerp(desired, 1.0 - exp(-4.0 * delta)) if _cam.global_position.length() > 0.001 else desired

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = 90
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.11, 0.9)
	top.add_theme_stylebox_override("panel", sb)
	_hud.add_child(top)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	top.add_child(row)
	_cash_label = _hud_label(row, "● 0")
	_comp_label = _hud_label(row, "⚙ 0")
	_eco_label = _hud_label(row, "♻ 0")
	# bottleneck as icons: 礦層 ▶ 礦車 ▶ 倉庫 (the slow stage pulses red)
	var brow_top := HBoxContainer.new()
	brow_top.anchor_left = 0.5
	brow_top.anchor_right = 0.5
	brow_top.offset_top = 96
	brow_top.offset_left = -150
	brow_top.offset_right = 150
	brow_top.alignment = BoxContainer.ALIGNMENT_CENTER
	brow_top.add_theme_constant_override("separation", 14)
	_hud.add_child(brow_top)
	for stage in ["layers", "cart", "warehouse"]:
		var ic := _make_stage_icon(stage)
		brow_top.add_child(ic)
		_bottleneck_icons[stage] = ic
		if stage != "warehouse":
			var arrow := TextureRect.new()
			arrow.texture = load("res://assets/icons/arrowRight.png")
			arrow.custom_minimum_size = Vector2(28, 28)
			arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			arrow.modulate = Color(1, 1, 1, 0.6)
			brow_top.add_child(arrow)
	_status_label = Label.new() # kept for tests / debug, hidden
	_status_label.visible = false
	_hud.add_child(_status_label)

	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -120
	bottom.add_theme_stylebox_override("panel", sb)
	_hud.add_child(bottom)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 10)
	bottom.add_child(brow)
	_frenzy_button = Button.new()
	_frenzy_button.icon = load("res://assets/icons/star.png")
	_frenzy_button.expand_icon = false
	_frenzy_button.add_theme_constant_override("icon_max_width", 40)
	_frenzy_button.clip_text = true
	_frenzy_button.text = ""
	_frenzy_button.custom_minimum_size = Vector2(150, 66)
	_frenzy_button.add_theme_font_size_override("font_size", 28)
	_frenzy_button.pressed.connect(_on_frenzy_pressed)
	brow.add_child(_frenzy_button)
	var mine_btn := Button.new()
	mine_btn.icon = load("res://assets/icons/wrench.png")
	mine_btn.expand_icon = false
	mine_btn.add_theme_constant_override("icon_max_width", 40)
	mine_btn.clip_text = true
	mine_btn.text = ""
	mine_btn.custom_minimum_size = Vector2(110, 66)
	mine_btn.add_theme_font_size_override("font_size", 28)
	mine_btn.pressed.connect(func() -> void: if mine.panel.visible: mine.panel.close() else: mine.panel.open())
	brow.add_child(mine_btn)
	_ai_button = Button.new()
	_ai_button.custom_minimum_size = Vector2(130, 66)
	_ai_button.add_theme_font_size_override("font_size", 24)
	_ai_button.pressed.connect(_on_ai_pressed)
	brow.add_child(_ai_button)
	_mgr_button = Button.new()
	_mgr_button.icon = load("res://assets/icons/gear.png")
	_mgr_button.expand_icon = false
	_mgr_button.add_theme_constant_override("icon_max_width", 40)
	_mgr_button.clip_text = true
	_mgr_button.custom_minimum_size = Vector2(110, 66)
	_mgr_button.add_theme_font_size_override("font_size", 24)
	_mgr_button.pressed.connect(_on_mgr_pressed)
	brow.add_child(_mgr_button)
	_build_offline_panel()

	# arrow to the furnace when carrying ore (points along screen edge)
	_furnace_arrow = TextureRect.new()
	_furnace_arrow.texture = load("res://assets/icons/arrowRight.png")
	_furnace_arrow.size = Vector2(56, 56)
	_furnace_arrow.pivot_offset = Vector2(28, 28)
	_furnace_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_furnace_arrow.modulate = Color(1.0, 0.75, 0.3)
	_furnace_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_furnace_arrow.visible = false
	_hud.add_child(_furnace_arrow)
	# floating joystick visuals
	_joy_ring = Panel.new()
	_joy_ring.size = Vector2(JOY_RADIUS_PX * 2.0, JOY_RADIUS_PX * 2.0)
	var ring_sb := StyleBoxFlat.new()
	ring_sb.bg_color = Color(1, 1, 1, 0.08)
	ring_sb.border_color = Color(1, 1, 1, 0.5)
	ring_sb.set_border_width_all(3)
	ring_sb.set_corner_radius_all(int(JOY_RADIUS_PX))
	_joy_ring.add_theme_stylebox_override("panel", ring_sb)
	_joy_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_ring.visible = false
	_hud.add_child(_joy_ring)
	_joy_knob = Panel.new()
	_joy_knob.size = Vector2(60, 60)
	var knob_sb := StyleBoxFlat.new()
	knob_sb.bg_color = Color(1, 1, 1, 0.75)
	knob_sb.set_corner_radius_all(30)
	_joy_knob.add_theme_stylebox_override("panel", knob_sb)
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_knob.visible = false
	_hud.add_child(_joy_knob)

func _hud_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	parent.add_child(l)
	return l

func _refresh_hud() -> void:
	_cash_label.text = "● %s" % _fmt(state.cash)
	_comp_label.text = "⚙ %s" % _fmt(state.components)
	_eco_label.text = "♻ %s" % _fmt(state.eco)
	if frenzy.active:
		_frenzy_button.text = " %ds" % int(ceil(frenzy.time_remaining))
		_frenzy_button.disabled = true
	else:
		var cd: float = frenzy.cooldown_remaining
		_frenzy_button.disabled = cd > 0.0
		_frenzy_button.text = (" %ds" % int(ceil(cd))) if cd > 0.0 else ""
	var stage: String = mine.state.bottleneck_stage()
	_status_label.text = stage
	var pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 180.0)
	for k: String in _bottleneck_icons.keys():
		var ic: Control = _bottleneck_icons[k]
		ic.modulate = Color(1.0, 0.35, 0.3, 1.0) if k == stage else Color(1, 1, 1, 0.85)
		ic.scale = Vector2.ONE * (1.0 + 0.12 * pulse) if k == stage else Vector2.ONE
	mine.refresh_afford_state()
	_update_furnace_arrow()
	_ai_button.text = ("AI " + ("●" if _ai_on else "○")) if _ai_unlocked else "AI ⚙%s|$%s" % [_fmt(AI_COST_COMPONENTS), _fmt(AI_COST_CASH)]
	_ai_button.modulate = Color(0.6, 1.0, 0.6) if _ai_active else Color.WHITE
	_ai_button.disabled = (not _ai_unlocked) and state.components < AI_COST_COMPONENTS and state.cash < AI_COST_CASH
	_mgr_button.text = ("●" if _mgr_on else "○") if _mgr_unlocked else _fmt(MGR_COST)
	_mgr_button.disabled = (not _mgr_unlocked) and state.cash < MGR_COST

func _update_furnace_arrow() -> void:
	if _bucket_count() == 0 or _furnace_node == null:
		_furnace_arrow.visible = false
		return
	var vp := get_viewport().get_visible_rect().size
	var fp: Vector3 = _furnace_node.global_position
	var sp: Vector2 = _cam.unproject_position(fp)
	var inside: bool = not _cam.is_position_behind(fp) and sp.x > 0 and sp.x < vp.x and sp.y > 120 and sp.y < vp.y - 130
	_furnace_arrow.visible = not inside
	if inside:
		return
	var center := vp * 0.5
	var dir: Vector2 = (sp - center).normalized() if not _cam.is_position_behind(fp) else Vector2(0, 1)
	var edge: Vector2 = center + dir * minf(vp.x * 0.42, vp.y * 0.36)
	_furnace_arrow.position = edge - Vector2(28, 28)
	_furnace_arrow.rotation = dir.angle()

## 2D stage icons drawn with ColorRects (no emoji font needed): 礦層＝梯級, 礦車＝車+輪, 倉庫＝屋
func _make_stage_icon(stage: String) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(44, 44)
	root.pivot_offset = Vector2(22, 22)
	var col := Color(0.93, 0.9, 1.0)
	match stage:
		"layers":
			for i in range(3):
				var r := ColorRect.new()
				r.color = col
				r.position = Vector2(4 + i * 6, 30 - i * 10)
				r.size = Vector2(36 - i * 12, 8)
				root.add_child(r)
		"cart":
			var body := ColorRect.new()
			body.color = col
			body.position = Vector2(6, 14)
			body.size = Vector2(32, 16)
			root.add_child(body)
			for x in [10, 28]:
				var w := ColorRect.new()
				w.color = col
				w.position = Vector2(x, 32)
				w.size = Vector2(8, 8)
				root.add_child(w)
		_:
			var house := ColorRect.new()
			house.color = col
			house.position = Vector2(8, 18)
			house.size = Vector2(28, 20)
			root.add_child(house)
			var roof := ColorRect.new()
			roof.color = col.darkened(0.25)
			roof.position = Vector2(4, 10)
			roof.size = Vector2(36, 8)
			root.add_child(roof)
	return root

func _bucket_count() -> int:
	var inv: Transform3D = _car.transform.affine_inverse()
	var n := 0
	for k: Dictionary in _kicked:
		var node: Node3D = k["node"]
		if not is_instance_valid(node):
			continue
		var lp: Vector3 = inv * node.position
		if lp.y > 0.0 and lp.y < 0.7 * _blade_w() and absf(lp.x) < 0.5 * _blade_w():
			n += 1
	return n

# ══════════════════════ VR-16：掛機自動化 ══════════════════════

var _seen_push_tier := -1
var _seen_layer_levels: Array = []
var _seen_cart := -1
var _seen_wh := -1
var _seen_unlocked := -1
## 升級要「見得到」：鏟斗變大、礦車轉快、對應物件彈字＋跳一跳
func _watch_upgrades() -> void:
	var ms := mine.state
	if _seen_push_tier == -1:
		_seen_push_tier = ms.push_tier
		_seen_layer_levels = ms.layer_level.duplicate()
		_seen_cart = ms.cart_level
		_seen_wh = ms.warehouse_level
		_seen_unlocked = ms.layer_unlocked.count(true)
		return
	if ms.push_tier != _seen_push_tier:
		_seen_push_tier = ms.push_tier
		_rebuild_blade()
		_popup_at(Vector3(_car.position.x, _car.position.y, 0.4), "鏟斗 ↑ 載 %d" % CARGO_CAP[clampi(ms.push_tier, 0, 2)], Color(1.0, 0.85, 0.3))
		_bounce(_car_body)
	for idx in range(ms.layer_level.size()):
		if idx < _seen_layer_levels.size() and ms.layer_level[idx] != _seen_layer_levels[idx]:
			_seen_layer_levels[idx] = ms.layer_level[idx]
			var at: Vector3 = mine.position + mine._layer_center(idx) + Vector3(0.0, 0.0, 0.5)
			_popup_at(at, "礦層 %d 速度 ↑ Lv%d" % [idx + 1, ms.layer_level[idx]], Color(0.75, 1.0, 0.75))
	if ms.cart_level != _seen_cart:
		_seen_cart = ms.cart_level
		_popup_at(mine.position + Vector3(mine.LAYER_WIDTH * 0.5 + 0.2, 0.6, 0.5), "礦車 ↑ Lv%d" % ms.cart_level, Color(0.75, 0.9, 1.0))
	if ms.warehouse_level != _seen_wh:
		_seen_wh = ms.warehouse_level
		_popup_at(mine.position + Vector3(mine.LAYER_WIDTH * 0.5 + 0.65, -0.25, 0.8), "倉庫 ↑ Lv%d" % ms.warehouse_level, Color(0.75, 0.9, 1.0))
	var unlocked_now: int = ms.layer_unlocked.count(true)
	if unlocked_now != _seen_unlocked:
		_seen_unlocked = unlocked_now
		_popup_at(mine.position + mine._layer_center(unlocked_now - 1) + Vector3(0.0, 0.0, 0.6), "礦層 %d 開通！" % unlocked_now, Color(1.0, 0.8, 0.4))

func _popup_at(at: Vector3, text: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 84
	lbl.pixel_size = 0.004
	lbl.outline_size = 14
	lbl.modulate = col
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = at
	_site.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:z", at.z + 1.2, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.4).set_delay(0.6)
	tw.chain().tween_callback(lbl.queue_free)

func _bounce(node: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_SINE)

func _pipeline_rate() -> float:
	var ms := mine.state
	var flow: float = minf(ms.total_mine_output(), minf(ms.cart_capacity(), ms.warehouse_capacity()))
	return flow * (ms.c.ore_value_silver + ms.c.ore_value_gold) * 0.5

func _settle_offline(saved: Dictionary) -> void:
	if not saved.has("last_save_unix"):
		return
	var now := Time.get_unix_time_from_system()
	var result := OfflineSettlement.settle(c, {"cash": state.cash, "last_save_unix": float(saved["last_save_unix"]), "prestige_count": 0}, now, _pipeline_rate())
	var yield_cash: float = float(result["cash_yield"])
	if yield_cash < 1.0:
		return
	_offline_pending = yield_cash
	_offline_label.text = OfflineReport.raccoon_message(yield_cash, float(result["elapsed_secs"]), c.offline_cap_secs) + "\n\n+%s" % _fmt(yield_cash)
	_offline_panel.visible = true

func _build_offline_panel() -> void:
	_offline_panel = PanelContainer.new()
	_offline_panel.anchor_left = 0.5
	_offline_panel.anchor_right = 0.5
	_offline_panel.anchor_top = 0.5
	_offline_panel.anchor_bottom = 0.5
	_offline_panel.offset_left = -290
	_offline_panel.offset_right = 290
	_offline_panel.clip_contents = true
	_offline_panel.offset_top = -160
	_offline_panel.offset_bottom = 160
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.15, 0.96)
	sb.set_corner_radius_all(18)
	_offline_panel.add_theme_stylebox_override("panel", sb)
	_offline_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_offline_panel.add_child(v)
	_offline_label = Label.new()
	_offline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offline_label.add_theme_font_size_override("font_size", 24)
	_offline_label.custom_minimum_size = Vector2(520, 0)
	_offline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_offline_label)
	var buttons_row := HBoxContainer.new()
	buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_row.add_theme_constant_override("separation", 16)
	v.add_child(buttons_row)
	# VR-07（留位）：×2 睇廣告——同 main.gd _build_offline_panel() 一樣做法，
	# 呢度淨係擺位＋停用，接駁廣告係另一張 issue。
	_offline_double_button = Button.new()
	_offline_double_button.text = "×2（睇廣告）"
	_offline_double_button.disabled = true
	_offline_double_button.tooltip_text = "未接（VR-07）"
	_offline_double_button.custom_minimum_size = Vector2(180, 64)
	_offline_double_button.add_theme_font_size_override("font_size", 22)
	buttons_row.add_child(_offline_double_button)
	_offline_claim_button = Button.new()
	_offline_claim_button.text = "收下"
	_offline_claim_button.custom_minimum_size = Vector2(180, 64)
	_offline_claim_button.add_theme_font_size_override("font_size", 26)
	_offline_claim_button.pressed.connect(func() -> void:
		state.cash += _offline_pending
		_offline_pending = 0.0
		_offline_panel.visible = false
		_save_game())
	buttons_row.add_child(_offline_claim_button)
	_hud.add_child(_offline_panel)

func _on_ai_pressed() -> void:
	if not _ai_unlocked:
		# Components 平過 Cash——夠 Components 就用嗰邊，唔夠先睇 Cash。
		if state.components >= AI_COST_COMPONENTS:
			state.components -= AI_COST_COMPONENTS
		elif state.cash >= AI_COST_CASH:
			state.cash -= AI_COST_CASH
		else:
			return
		_ai_unlocked = true
		_ai_on = true
	else:
		_ai_on = not _ai_on
		if not _ai_on:
			_ai_active = false
	_save_game()

func _on_mgr_pressed() -> void:
	if not _mgr_unlocked:
		if state.cash < MGR_COST:
			return
		state.cash -= MGR_COST
		_mgr_unlocked = true
		_mgr_on = true
	else:
		_mgr_on = not _mgr_on
	_save_game()

## AI 司機：去最近礦堆 → 鏟到 6 成 → 去爐賣 → 循環
func _ai_steer(delta: float) -> Vector2:
	var cap: int = CARGO_CAP[clampi(mine.state.push_tier, 0, 2)]
	var carrying: int = _bucket_count()
	var pos := Vector2(_car.position.x, _car.position.y)
	_ai_retarget_t -= delta
	if _ai_mode == "heap":
		if carrying >= int(float(cap) * 0.6):
			_ai_mode = "furnace"
			_ai_target = FURNACE_POS + Vector2(-0.3, -0.6)
		elif _ai_target == Vector2.INF or _ai_retarget_t <= 0.0 or pos.distance_to(_ai_target) < 0.35:
			_ai_target = _nearest_ore_pos(pos)
			_ai_retarget_t = 2.5
	else:
		if carrying == 0 and pos.distance_to(_ai_target) < 1.2:
			_ai_mode = "heap"
			_ai_target = _nearest_ore_pos(pos)
			_ai_retarget_t = 2.5
		elif pos.distance_to(_ai_target) < 0.3:
			_ai_target = FURNACE_POS + Vector2(-1.6, -0.6) # 已喺爐區未賣就行出去再入
	if _ai_target == Vector2.INF:
		return Vector2.ZERO
	var to: Vector2 = _ai_target - pos
	return to.normalized() if to.length() > 0.12 else Vector2.ZERO

func _nearest_ore_pos(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for _i in range(160):
		var s: Dictionary = _slots[rng.randi_range(0, _slots.size() - 1)]
		if s["gone"] or s["active"]:
			continue
		var p: Vector3 = s["pos"]
		var d2: float = from.distance_squared_to(Vector2(p.x, p.y))
		if d2 < best_d:
			best_d = d2
			best = Vector2(p.x, p.y)
	return best

## 經理自動升級：每 5 秒睇瓶頸，留返 20% 現金
func _manager_tick(delta: float) -> void:
	if not (_mgr_unlocked and _mgr_on):
		return
	_mgr_accum += delta
	if _mgr_accum < 5.0:
		return
	_mgr_accum = 0.0
	var ms := mine.state
	var reserve: float = state.cash * 0.2
	var stage: String = ms.bottleneck_stage()
	var options: Array = []
	for idx in range(ms.layer_unlocked.size()):
		if ms.layer_unlocked[idx] and (stage == "layers" or stage == "balanced"):
			options.append([ms.next_layer_speed_cost(idx), func() -> void: ms.apply_layer_speed_upgrade(idx)])
	if (stage == "cart" or stage == "balanced") and ms.can_upgrade_cart():
		options.append([ms.next_cart_cost(), func() -> void: ms.apply_cart_upgrade()])
	if (stage == "warehouse" or stage == "balanced") and ms.can_upgrade_warehouse():
		options.append([ms.next_warehouse_cost(), func() -> void: ms.apply_warehouse_upgrade()])
	if options.is_empty():
		return
	options.sort_custom(func(a, b): return a[0] < b[0])
	var cost: float = options[0][0]
	if state.cash - cost >= reserve:
		state.cash -= cost
		(options[0][1] as Callable).call()

## 地面運輸隊：每 10 秒一個小機械人由倉庫去最近礦堆撿 3 粒返倉（礦值 5 折）
func _surface_team_tick(delta: float) -> void:
	_team_accum += delta
	if _team_accum < 10.0:
		return
	_team_accum = 0.0
	var wh := Vector2(MINE_POS.x + 1.85, MINE_POS.y - 0.25)
	var target: Vector2 = _nearest_ore_pos(wh)
	if target == Vector2.INF:
		return
	var bot := VisualFactory.make_miner()
	bot.rotation_degrees.x = 90.0
	bot.position = Vector3(wh.x, wh.y - 0.4, 0.0)
	_site.add_child(bot)
	var trip: float = clampf(wh.distance_to(target) / 1.2, 0.8, 4.0)
	var tw := create_tween()
	tw.tween_property(bot, "position", Vector3(target.x, target.y, 0.0), trip).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		var picked: Array = []
		for _i in range(80):
			var s: Dictionary = _slots[rng.randi_range(0, _slots.size() - 1)]
			if s["gone"] or s["active"]:
				continue
			var p: Vector3 = s["pos"]
			if Vector2(p.x, p.y).distance_to(target) < 0.5:
				s["gone"] = true
				_hide_slot(s)
				picked.append(s["tier"])
				if picked.size() >= 3:
					break
		bot.set_meta("picked", picked))
	tw.tween_property(bot, "position", Vector3(wh.x, wh.y - 0.4, 0.0), trip).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		var total := 0.0
		for tier in bot.get_meta("picked", []):
			total += mine.state.c.ore_value(tier) * 0.5
		state.cash += total
		bot.queue_free())

func _fmt(v: float) -> String:
	if v >= 1_000_000.0: return "%.1fM" % (v / 1_000_000.0)
	if v >= 1_000.0: return "%.1fK" % (v / 1_000.0)
	return str(int(v))

func _on_frenzy_pressed() -> void:
	if frenzy.start(state.current_income_rate()):
		SfxPlayer.play("frenzy_start")

## main.gd 同一個名／同一個做法——存檔之前一定要 call 一次，等 Wallet
## 記憶體嗰份同即將存落 disk 嗰份一致（見 autoload/wallet.gd 頂部註解）。
func _sync_wallet_from_state() -> void:
	Wallet.cash = state.cash
	Wallet.components = state.components
	Wallet.eco = state.eco

func _save_game() -> void:
	_sync_wallet_from_state()
	var d := SaveManager.load_state()
	d["cash"] = state.cash
	d["components"] = state.components
	d["eco"] = state.eco
	d["mine_zone"] = mine.to_save_dict()
	d["last_save_unix"] = Time.get_unix_time_from_system()
	d["field_ai_unlocked"] = _ai_unlocked
	d["field_ai_on"] = _ai_on
	d["field_mgr_unlocked"] = _mgr_unlocked
	d["field_mgr_on"] = _mgr_on
	Save.save_raw(d)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if mine != null:
			_save_game()

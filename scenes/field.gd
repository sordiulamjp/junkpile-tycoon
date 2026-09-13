extends Node3D
## Field v1 (ALTA-228 rebuild by Analyst): ONE flat field in the IG-ad palette
## (purple rock bowl, dark ground), Zone 1 = MineZone core (terraces / rail /
## warehouse / push pads) + free-roaming bulldozer (floating joystick) that
## pushes ore nuggets into the furnace to sell. Replaces main.tscn as the
## entry scene. Site coords: x right, y away from camera, z up.

const SITE_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
const CAM_PITCH_DEG := -60.0
const CAM_FOV := 40.0
const CAM_DIST := 11.5
const FIELD_MIN := Vector2(-2.4, -2.7)   # site bounds (x, y)
const FIELD_MAX := Vector2(2.4, 2.9)
const MINE_POS := Vector2(0.0, 1.35)     # MineZone origin (its terraces extend +y)
const FURNACE_POS := Vector2(1.55, -1.7)
const CAR_START := Vector2(0.0, -0.6)
const CAR_Z := 0.14
const JOY_RADIUS_PX := 110.0

# TUNE (IG feel: slow, heavy)
const CAR_SPEED := 1.4
const CAR_ACCEL := 4.0
const CAR_TURN_LERP := 8.0
const PUSH_IMPULSE := 0.35
const ORE_RADIUS := 0.04
const ORE_COUNT := 2600
const KICK_RADIUS := 0.42
const KICK_LIFETIME := 1.4
const KICK_BUDGET := 120
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

var _hud: CanvasLayer
var _cash_label: Label
var _comp_label: Label
var _eco_label: Label
var _status_label: Label
var _frenzy_button: Button
var _save_accum := 0.0
var _autodrive := false
var _autodrive_t := 0.0


func _ready() -> void:
	rng.randomize()
	c = GameConstants.new()
	state = GameState.new(c)
	frenzy = FrenzyState.new(c)
	_autodrive = "--autodrive" in OS.get_cmdline_user_args()
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
	_sync_wallet_from_state()
	_build_world()
	_build_zone1(saved.get("mine_zone", {}))
	_build_car()
	_build_ore_pool()
	_build_hud()
	mine.attach_panel(_hud)
	get_viewport().physics_object_picking = true


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
	var body := VisualFactory.make_metal_box(Vector3(0.9, 0.7, 0.55), Color(MineConstants.PALETTE["furnace"]))
	body.position = Vector3(0.0, 0.2, 0.275)
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
	var pad := VisualFactory.make_flat_box(Vector3(1.0, 0.55, 0.02), Color(MineConstants.PALETTE["pad"]))
	pad.position = Vector3(0.0, -0.5, 0.01)
	furnace.add_child(pad)
	var lbl := Label3D.new()
	lbl.text = "SELL"
	lbl.font_size = 100
	lbl.pixel_size = 0.0035
	lbl.position = Vector3(0.0, -0.5, 0.03)
	furnace.add_child(lbl)
	var area := Area3D.new()
	area.name = "SellArea"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.5, 0.8)
	col.shape = shape
	area.add_child(col)
	area.position = Vector3(0.0, -0.15, 0.3)
	area.body_entered.connect(_on_sell_area_entered)
	furnace.add_child(area)


# ══════════════════════ car (free roaming) ══════════════════════

func _build_car() -> void:
	_car = CharacterBody3D.new()
	_car.name = "Car"
	_car.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.44, 0.5, 0.26)
	col.shape = shape
	_car.add_child(col)
	_car.position = _site_to_local(CAR_START, CAR_Z)
	_site.add_child(_car)

	_car_body = Node3D.new()
	_car.add_child(_car_body)
	var body := VisualFactory.make_metal_box(Vector3(0.3, 0.32, 0.16), Color("#F2C230"))
	_car_body.add_child(body)
	var cab := VisualFactory.make_metal_box(Vector3(0.18, 0.16, 0.12), Color("#F7D35A"))
	cab.position = Vector3(0.0, -0.04, 0.13)
	_car_body.add_child(cab)
	for sx in [-1.0, 1.0]:
		var track := VisualFactory.make_metal_box(Vector3(0.09, 0.4, 0.1), Color("#26262B"))
		track.position = Vector3(sx * 0.2, 0.0, -0.05)
		_car_body.add_child(track)
	# curved blade: 5 segments in an arc in front (+y)
	for i in range(5):
		var a: float = (float(i) - 2.0) * 0.32
		var seg := VisualFactory.make_metal_box(Vector3(0.16, 0.04, 0.16), Color("#F2C230").darkened(0.1))
		seg.position = Vector3(sin(a) * 0.34, 0.2 + cos(a) * 0.14, 0.0)
		seg.rotation.z = -a
		_car_body.add_child(seg)
		if i == 2:
			_blade = seg

func _physics_process(delta: float) -> void:
	var input_vec: Vector2 = _joy_vec if _joy_down else _keys_vec
	if _autodrive:
		_autodrive_t += delta
		input_vec = Vector2(cos(_autodrive_t * 0.9), sin(_autodrive_t * 0.6))
	var speed_mult: float = 1.5 if frenzy.active else 1.0
	var target: Vector2 = input_vec.limit_length(1.0) * CAR_SPEED * speed_mult
	_car_vel = _car_vel.move_toward(target, CAR_ACCEL * delta)
	_car.velocity = SITE_BASIS * Vector3(_car_vel.x, _car_vel.y, 0.0)
	_car.move_and_slide()
	# keep on the ground plane
	_car.position.z = CAR_Z
	# push rigid ore
	for i in range(_car.get_slide_collision_count()):
		var kc := _car.get_slide_collision(i)
		var body := kc.get_collider()
		if body is RigidBody3D:
			var n: Vector3 = kc.get_normal()
			(body as RigidBody3D).apply_central_impulse(-n * PUSH_IMPULSE * maxf(_car_vel.length() / CAR_SPEED, 0.3))
	# face movement direction
	if _car_vel.length() > 0.05:
		var ang: float = atan2(_car_vel.y, _car_vel.x) - PI * 0.5
		_car.rotation.z = lerp_angle(_car.rotation.z, ang, CAR_TURN_LERP * delta)
	_pool_tick(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
			return
		if pressed:
			_joy_down = true
			_joy_origin = event.position
			_joy_vec = Vector2.ZERO
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
	var blobs := [Vector2(-1.1, 0.0), Vector2(0.5, -0.35), Vector2(-0.2, 0.75)]
	for tier: String in tiers.keys():
		var count: int = int(ORE_COUNT * float(tiers[tier][0]))
		var mmi := VisualFactory.make_ore_pool_multimesh(ORE_RADIUS, tiers[tier][1], 0.35 if tier == "gold" else 0.0, count)
		mmi.name = "Pool_%s" % tier
		_site.add_child(mmi)
		_pool_mmi[tier] = mmi
		for i in range(count):
			var ctr: Vector2 = blobs[rng.randi_range(0, blobs.size() - 1)]
			var a := rng.randf_range(0.0, TAU)
			var r := sqrt(rng.randf()) * 0.6
			var pos := Vector3(ctr.x + cos(a) * r * 1.2, ctr.y + sin(a) * r, ORE_RADIUS * float(tiers[tier][2]))
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(tiers[tier][2])), pos))
			_slots.append({"tier": tier, "idx": i, "pos": pos, "scale": float(tiers[tier][2]), "active": false, "gone": false})

func _hide_slot(s: Dictionary) -> void:
	(_pool_mmi[s["tier"]] as MultiMeshInstance3D).multimesh.set_instance_transform(s["idx"], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))

func _show_slot(s: Dictionary) -> void:
	(_pool_mmi[s["tier"]] as MultiMeshInstance3D).multimesh.set_instance_transform(s["idx"], Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(s["scale"])), s["pos"]))

func _pool_tick(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum >= 0.1:
		_scan_accum = 0.0
		var budget: int = KICK_BUDGET - _kicked.size()
		var r2: float = KICK_RADIUS * KICK_RADIUS
		var cp: Vector3 = _car.position
		for s: Dictionary in _slots:
			if budget <= 0:
				break
			if s["active"] or s["gone"]:
				continue
			if (s["pos"] as Vector3).distance_squared_to(cp) > r2:
				continue
			_activate_slot(s)
			budget -= 1
	for k: Dictionary in _kicked.duplicate():
		var node: RigidBody3D = k["node"]
		if not is_instance_valid(node):
			_kicked.erase(k)
			continue
		k["t"] += delta
		var far: bool = node.position.distance_to(_car.position) > KICK_RADIUS * 2.2
		if k["t"] >= KICK_LIFETIME and far:
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
	if _furnace_flash > 0.0:
		_furnace_flash -= delta
		_furnace_glow.emission_energy_multiplier = 1.8 + 2.5 * clampf(_furnace_flash, 0.0, 1.0)

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
	mat.friction = 0.8
	body.physics_material_override = mat
	body.linear_damp = 1.2
	_kick_root.add_child(body)
	var away: Vector3 = (s["pos"] as Vector3) - _car.position
	away.z = 0.0
	if away.length() < 0.01:
		away = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0)
	body.apply_central_impulse(away.normalized() * 0.08 + Vector3(0, 0, 0.05))
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
	_refresh_hud()
	_save_accum += delta
	if _save_accum >= 10.0:
		_save_accum = 0.0
		_save_game()

func _follow_camera(delta: float) -> void:
	var target_site := Vector2(_car.position.x, _car.position.y)
	target_site.x = clampf(target_site.x, FIELD_MIN.x + 1.2, FIELD_MAX.x - 1.2)
	target_site.y = clampf(target_site.y + 0.9, FIELD_MIN.y + 1.6, FIELD_MAX.y + 0.4)
	var target_world: Vector3 = _site.to_global(Vector3(target_site.x, target_site.y, 0.0))
	var desired: Vector3 = target_world + _cam.global_transform.basis.z * CAM_DIST
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
	_status_label = Label.new()
	_status_label.anchor_top = 0.0
	_status_label.offset_top = 92
	_status_label.anchor_right = 1.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
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
	brow.add_theme_constant_override("separation", 30)
	bottom.add_child(brow)
	_frenzy_button = Button.new()
	_frenzy_button.text = "狂熱！"
	_frenzy_button.custom_minimum_size = Vector2(220, 70)
	_frenzy_button.add_theme_font_size_override("font_size", 28)
	_frenzy_button.pressed.connect(_on_frenzy_pressed)
	brow.add_child(_frenzy_button)
	var mine_btn := Button.new()
	mine_btn.text = "礦道剖面"
	mine_btn.custom_minimum_size = Vector2(220, 70)
	mine_btn.add_theme_font_size_override("font_size", 28)
	mine_btn.pressed.connect(func() -> void: if mine.panel.visible: mine.panel.close() else: mine.panel.open())
	brow.add_child(mine_btn)

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
		_frenzy_button.text = "狂熱中 %ds" % int(ceil(frenzy.time_remaining))
		_frenzy_button.disabled = true
	else:
		var cd: float = frenzy.cooldown_remaining if "cooldown_remaining" in frenzy else 0.0
		_frenzy_button.disabled = cd > 0.0
		_frenzy_button.text = ("冷卻 %ds" % int(ceil(cd))) if cd > 0.0 else "狂熱！"
	var stage: String = mine.state.bottleneck_stage()
	var names := {"layers": "瓶頸：礦層開採太慢", "cart": "瓶頸：礦車運載太慢", "warehouse": "瓶頸：倉庫收集太慢"}
	_status_label.text = str(names.get(stage, ""))
	mine.refresh_afford_state()

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
	Save.save_raw(d)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if mine != null:
			_save_game()

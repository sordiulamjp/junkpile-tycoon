extends Node3D
class_name Hauler

## 拖車仔（用戶 2026-09-18：參考 Bulldozer Master 工人制）——每條已開礦脈可以請一架，
## 只行「自己礦脈 → 熔爐 → 返礦脈」呢條路，冇碰撞、唔用物理，純粹跟航點行。
## 邊粒礦被執走／賣幾多錢由 field 決定（on_load / on_sell callback），呢度只負責行同畫。

const MAX_LEVEL := 5

var route: Array = []      # site 座標航點：[0] = 礦脈中心，最後 = 熔爐停車位
var level: int = 1
var speed: float = 0.9
var cap: int = 6
var load_secs: float = 1.5 # 喺礦脈裝貨要企幾耐（有鑽機就好快）
var on_load: Callable      # (hauler) -> Array[String]  攞走嘅礦 tier 清單（field 負責隱藏槽位）
var on_sell: Callable      # (hauler, tiers: Array) -> void

var _state := "to_vein"    # to_vein | loading | to_furnace | selling
var _wp := 0
var _t := 0.0
var _tiers: Array = []
var _cargo_nodes: Array = []
var _bed: Node3D
var _body: Node3D
var _bob := 0.0


static func level_speed(l: int) -> float:
	return 0.9 + 0.25 * float(l - 1)

static func level_cap(l: int) -> int:
	return 6 + 3 * (l - 1)

func setup(p_route: Array, p_level: int, p_on_load: Callable, p_on_sell: Callable) -> void:
	route = p_route
	on_load = p_on_load
	on_sell = p_on_sell
	set_level(p_level)
	_build_visual()
	position = Vector3((route[0] as Vector2).x, (route[0] as Vector2).y, 0.0)
	_state = "loading"
	_t = load_secs

func set_level(l: int) -> void:
	level = clampi(l, 1, MAX_LEVEL)
	speed = level_speed(level)
	cap = level_cap(level)

func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	var chassis := VisualFactory.make_metal_box(Vector3(0.24, 0.36, 0.1), Color("#D9773A"))
	chassis.position = Vector3(0.0, 0.0, 0.1)
	_body.add_child(chassis)
	var cab := VisualFactory.make_metal_box(Vector3(0.2, 0.12, 0.12), Color("#F2A35A"))
	cab.position = Vector3(0.0, 0.14, 0.2)
	_body.add_child(cab)
	_bed = Node3D.new()
	_bed.position = Vector3(0.0, -0.06, 0.15)
	_body.add_child(_bed)
	for sx in [-0.13, 0.13]:
		for sy in [-0.12, 0.12]:
			var w := VisualFactory.make_low_poly_cylinder(0.05, 0.05, Color("#1E1E22"), 8, 0.1)
			w.rotation_degrees.y = 90.0
			w.position = Vector3(sx, sy, 0.05)
			_body.add_child(w)
	var lvl := Label3D.new()
	lvl.name = "Lvl"
	lvl.text = "Lv%d" % level
	lvl.font_size = 60
	lvl.pixel_size = 0.003
	lvl.outline_size = 10
	lvl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lvl.position = Vector3(0.0, 0.0, 0.5)
	add_child(lvl)

func refresh_label() -> void:
	var l := get_node_or_null("Lvl") as Label3D
	if l != null:
		l.text = "Lv%d" % level

func _process(delta: float) -> void:
	_bob += delta * 6.0
	match _state:
		"loading":
			_t -= delta
			if _t <= 0.0:
				var got: Array = on_load.call(self) if on_load.is_valid() else []
				if got.is_empty():
					_t = 2.0 # 礦脈空咗：等陣再試
					return
				_tiers = got
				_stack_cargo()
				_state = "to_furnace"
				_wp = 1
		"to_furnace":
			if _move_to(route[_wp], delta):
				_wp += 1
				if _wp >= route.size():
					_state = "selling"
					_t = 0.5
					if on_sell.is_valid():
						on_sell.call(self, _tiers)
					_tiers = []
					_clear_cargo()
		"selling":
			_t -= delta
			if _t <= 0.0:
				_state = "to_vein"
				_wp = route.size() - 2
		"to_vein":
			if _move_to(route[_wp], delta):
				_wp -= 1
				if _wp < 0:
					_state = "loading"
					_t = load_secs
	if _body != null:
		_body.position.z = 0.01 * sin(_bob) if _state in ["to_vein", "to_furnace"] else 0.0

func _move_to(target: Vector2, delta: float) -> bool:
	var pos := Vector2(position.x, position.y)
	var to: Vector2 = target - pos
	var step: float = speed * delta
	if to.length() <= step:
		position = Vector3(target.x, target.y, 0.0)
		return true
	var d: Vector2 = to.normalized()
	position += Vector3(d.x, d.y, 0.0) * step
	rotation.z = lerp_angle(rotation.z, atan2(d.y, d.x) - PI * 0.5, 8.0 * delta)
	return false

func _stack_cargo() -> void:
	_clear_cargo()
	for i in range(_tiers.size()):
		var gold: bool = _tiers[i] == "gold"
		var b := VisualFactory.make_ore_ball(0.04, Color(MineConstants.PALETTE["ore_gold"] if gold else MineConstants.PALETTE["ore_silver"]), 0.3 if gold else 0.0)
		var col: int = i % 3
		var row: int = (i / 3) % 3
		var layer: int = i / 9
		b.position = Vector3(-0.07 + float(col) * 0.07, -0.08 + float(row) * 0.07, 0.03 + float(layer) * 0.07)
		_bed.add_child(b)
		_cargo_nodes.append(b)

func _clear_cargo() -> void:
	for n in _cargo_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_cargo_nodes.clear()

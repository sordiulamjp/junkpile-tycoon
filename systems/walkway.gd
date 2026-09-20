extends Node3D
class_name Walkway

## 走道／輸送帶（用戶 2026-09-18：參考 Bulldozer Master v8.1 Walkways）——
## 由主堆旁邊嘅入口沿東牆一路送到熔爐，礦粒推入入口就自己行，去到尾 field 負責賣。
## 呢度只負責畫條帶同搬礦粒，唔識錢。

const BELT_W := 0.5
var path: Array = []       # site 座標折線
var speed: float = 1.4
var on_arrive: Callable    # (body: Node3D) -> void
var _items: Array = []     # {node, seg, d}
var _seg_len: Array = []
var _chevrons: Array = []
var _anim := 0.0


func setup(p_path: Array, p_on_arrive: Callable) -> void:
	path = p_path
	on_arrive = p_on_arrive
	_build_visual()

func _build_visual() -> void:
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var d: Vector2 = b - a
		var len: float = d.length()
		_seg_len.append(len)
		var seg := Node3D.new()
		seg.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0)
		seg.rotation.z = atan2(d.y, d.x) - PI * 0.5
		add_child(seg)
		var strip := VisualFactory.make_flat_box(Vector3(BELT_W, len + BELT_W, 0.05), Color("#2A2A30"))
		strip.position = Vector3(0.0, 0.0, 0.025)
		seg.add_child(strip)
		for sx in [-1.0, 1.0]:
			var rail := VisualFactory.make_metal_box(Vector3(0.06, len + BELT_W, 0.12), Color("#5A5560"))
			rail.position = Vector3(sx * (BELT_W * 0.5 + 0.03), 0.0, 0.06)
			seg.add_child(rail)
		# 用戶 2026-09-20：整條帶係實體——車撞到會停，礦唔會滾上帶
		var sb := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(BELT_W + 0.12, len + BELT_W, 0.12)
		col.shape = shape
		col.position = Vector3(0.0, 0.0, 0.06)
		sb.add_child(col)
		seg.add_child(sb)
		var n: int = int(len / 0.4)
		for k in range(n):
			var chev := VisualFactory.make_flat_box(Vector3(BELT_W * 0.7, 0.05, 0.012), Color("#F2C230"))
			chev.position = Vector3(0.0, -len * 0.5 + 0.2 + float(k) * 0.4, 0.056)
			seg.add_child(chev)
			_chevrons.append([chev, len])
	# 每個轉角一塊圓墊遮住接口
	for i in range(1, path.size() - 1):
		var p: Vector2 = path[i]
		var corner := VisualFactory.make_low_poly_cylinder(BELT_W * 0.5 + 0.03, 0.05, Color("#2A2A30"), 10, 0.1)
		corner.rotation_degrees.x = 90.0
		corner.position = Vector3(p.x, p.y, 0.025)
		add_child(corner)

## 一粒礦（RigidBody3D，呼叫方已經由物理清單移除）放上帶頭
func add_body(body: Node3D) -> void:
	var gp: Vector3 = body.global_position
	var parent := body.get_parent()
	if parent != null:
		parent.remove_child(body)
	add_child(body)
	body.global_position = gp
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = true
		(body as RigidBody3D).collision_layer = 0
		(body as RigidBody3D).collision_mask = 0
	var start: Vector2 = path[0]
	body.position = Vector3(start.x, start.y, 0.1)
	body.scale = Vector3.ONE
	_items.append({"node": body, "seg": 0, "d": 0.0})

func count() -> int:
	return _items.size()

func _process(delta: float) -> void:
	_anim += delta * speed
	for c in _chevrons:
		var chev: MeshInstance3D = c[0]
		var len: float = c[1]
		chev.position.y += speed * delta
		if chev.position.y > len * 0.5 - 0.1:
			chev.position.y -= len - 0.2
	for it in _items.duplicate():
		var node: Node3D = it["node"]
		if not is_instance_valid(node):
			_items.erase(it)
			continue
		it["d"] += speed * delta
		while it["seg"] < _seg_len.size() and it["d"] >= float(_seg_len[it["seg"]]):
			it["d"] -= float(_seg_len[it["seg"]])
			it["seg"] += 1
		if it["seg"] >= _seg_len.size():
			_items.erase(it)
			if on_arrive.is_valid():
				on_arrive.call(node)
			continue
		var a: Vector2 = path[it["seg"]]
		var b: Vector2 = path[it["seg"] + 1]
		var p: Vector2 = a + (b - a).normalized() * float(it["d"])
		# 同一位置疊住嘅礦粒稍微錯開
		var jitter: float = 0.12 * sin(float(node.get_instance_id() % 97))
		var side: Vector2 = (b - a).normalized().orthogonal() * jitter
		node.position = Vector3(p.x + side.x, p.y + side.y, 0.1)

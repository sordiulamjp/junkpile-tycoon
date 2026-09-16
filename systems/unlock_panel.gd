extends Node3D
class_name UnlockPanel

## VR-11：場地擴張框架——「解鎖板」reusable 元件（field-zones-v9.png：
## 區域 2 入口「200」紫色解鎖板）。「同一場地，由下向上擴張」，唔係
## 獨立場景——呢個元件純粹係擺喺 main.gd 嘅 3D 世界入面、可以撳嘅一嚿
## 板，負責顯示＋接 tap 輸入，完全唔識 GameState／Wallet 內部形狀：夠唔
## 夠錢、扣邊個欄位、點樣持久化全部由呼叫方（main.gd）決定——「而家有
## 幾多錢」由呼叫方喺 refresh_afford_state() 逐次傳落嚟（唔喺呢度自己讀
## Wallet，避免同 GameState 每幀 tick 嘅即時 cash 唔同步，見 main.gd
## _refresh_hud() 嘅呼叫點），撳落去就 call 返呼叫方嘅 callback，等區域
## 3／4（VR-14／15，backlog）之後可以直接重用呢個 class，唔使抄一份。
##
## 三種視覺狀態：已解鎖（唔再接受撳）／夠錢未解鎖（正常紫）／唔夠錢未
## 解鎖（暗紫），對應 _refresh() 嘅分支。

var region_id: String
var cost: float
var display_name: String
var _on_tap: Callable
var _unlocked: bool = false
var _affordable: bool = false

var _label: Label3D
var _pad: MeshInstance3D
var _area: Area3D
var ore_cost: float = 0.0 # 要推幾多粒礦入嚟（0 = 唔使）
var ore_fed: float = 0.0  # 已推入幾多粒（用戶 2026-09-17：唔入庫存，直接推現貨入升級格）
var _feed_area: Area3D
var icon_kind: String = "" # "blade" | "blade_big" | "furnace" | "pickaxe" | "" — 用戶 2026-09-14：墊上用圖示，唔用文字
var _icon: Node3D


## region_id／cost／display_name：呢個解鎖板代表邊個區域、幾錢、卡面
## 顯示乜名。on_tap：未解鎖之前撳落去 call 呢個
## Callable(region_id: String, cost: float)，由呼叫方決定通唔通過（夠唔
## 夠錢）、扣邊個欄位、記唔記存檔；成功之後呼叫方要自己 call 返
## mark_unlocked()——呢個元件自己唔扣錢、唔存檔、唔自動判定「已解鎖」。
func setup(p_region_id: String, p_cost: float, p_display_name: String, on_tap: Callable, p_icon_kind: String = "", p_ore_cost: float = 0.0) -> void:
	region_id = p_region_id
	cost = p_cost
	ore_cost = p_ore_cost
	display_name = p_display_name
	_on_tap = on_tap
	icon_kind = p_icon_kind
	_build_visual()
	_build_icon()
	if ore_cost > 0.0:
		_build_feed_area()
	_refresh()

func _build_visual() -> void:
	_pad = VisualFactory.make_flat_box(Vector3(0.9, 0.5, 0.06), VisualFactory.PALETTE["pad_purple"])
	add_child(_pad)

	_label = Label3D.new()
	_label.font_size = 96
	_label.pixel_size = 0.0035
	_label.position = Vector3(0.0, -0.17, 0.05)
	_label.outline_size = 14
	_label.modulate = Color.WHITE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)

	_area = Area3D.new()
	_area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.5, 0.3)
	col.shape = shape
	_area.add_child(col)
	add_child(_area)
	_area.input_event.connect(_on_input_event)
	_area.body_entered.connect(_on_body_entered)

func _on_input_event(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	if _unlocked:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _on_tap.is_valid():
		_on_tap.call(region_id, cost)

## ALTA-228 round 4（field.tscn 萬向車，用戶 18:41 規格）：「墊／解鎖板：
## 車駛入 Area3D 即觸發（IG 式），唔使撳掣」——駛入淨係轉發返 on_tap
## callback，同 `_on_input_event()` 一樣，夠唔夠錢／扣邊個欄位一律由
## 呼叫方判斷，呢度自己乜都唔識。淨認 `CharacterBody3D`（field.gd 嘅
## 車）——礦粒係 RigidBody3D、地面／岩壁係 StaticBody3D，唔會誤觸發。
## main.tscn 場景冇 CharacterBody3D，呢個 signal 冇嘢會觸發，唔影響舊有
## 純 tap 流程。
func _on_body_entered(body: Node3D) -> void:
	if _unlocked:
		return
	if not (body is CharacterBody3D):
		return
	if _on_tap.is_valid():
		_on_tap.call(region_id, cost)

## 呼叫方判斷成功解鎖之後 call 呢個——更新視覺，之後就唔再接受撳。
func mark_unlocked() -> void:
	_unlocked = true
	_refresh()

## 呼叫方每次有最新嘅「而家有幾多錢」（例如 main.gd _refresh_hud() 每幀
## 傳 state.cash）就 call 呢個，更新「夠唔夠錢」嘅顯示，唔使玩家撳落去
## 先知道買唔買得起。已解鎖就乜都唔使做。
func refresh_afford_state(available_cash: float, available_ore: float = INF) -> void:
	if _unlocked:
		return
	var affordable := available_cash >= cost and ore_fed >= ore_cost
	if affordable == _affordable:
		return # 冇轉變就唔使重寫 Label3D／material，慳返啲嘢（同帶升級掣個做法一致）
	_affordable = affordable
	_refresh()

func _refresh() -> void:
	var mat: StandardMaterial3D = _pad.material_override
	if _unlocked:
		_label.text = "✓"
		mat.albedo_color = (VisualFactory.PALETTE["pad_purple"] as Color).lightened(0.25)
		return
	_label.text = _fmt_cost(cost) if ore_cost <= 0.0 else "%s\n礦 %d/%d" % [_fmt_cost(cost), int(ore_fed), int(ore_cost)]
	var base_color: Color = VisualFactory.PALETTE["pad_purple"]
	mat.albedo_color = base_color if _affordable else base_color.darkened(0.45)

## 細版 K/M 格式，同 main.gd::_fmt_num() 邏輯一樣，冇共用 util module
## （呢個 script 唔想引用 main.gd）所以各自維護一份細 function。
func _fmt_cost(n: float) -> String:
	if n < 1000.0:
		return "%d" % int(round(n))
	var v := n / 1000.0
	if v < 1000.0:
		return ("%.1fK" % v) if (v < 10.0 and absf(v - round(v)) > 0.05) else ("%.0fK" % v)
	return "%.1fM" % (v / 1000.0)


# ══════════════════════ 圖示（代替文字，IG 廣告語言：墊上放物件預覽 + 價錢） ══════════════════════

static func ghost_material(color: Color, alpha: float = 0.55) -> StandardMaterial3D:
	var m := VisualFactory.flat_material(color)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m

func _build_icon() -> void:
	if icon_kind == "":
		return
	_icon = Node3D.new()
	_icon.name = "Icon"
	_icon.position = Vector3(0.0, 0.08, 0.03)
	add_child(_icon)
	match icon_kind:
		"blade", "blade_big":
			var big: bool = icon_kind == "blade_big"
			var w: float = 0.5 if big else 0.36
			var h: float = 0.22 if big else 0.15
			var ghost := ghost_material(Color("#B4E1F0"))
			for i in range(5):
				var a: float = (float(i) - 2.0) * 0.3
				var seg := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(w * 0.26, 0.04, h)
				seg.mesh = box
				seg.material_override = ghost
				seg.position = Vector3(sin(a) * w * 0.5, cos(a) * 0.12, h * 0.5)
				seg.rotation.z = -a
				_icon.add_child(seg)
			var body := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.18, 0.2, 0.1)
			body.mesh = bb
			body.material_override = ghost
			body.position = Vector3(0.0, -0.12, 0.05)
			_icon.add_child(body)
		"furnace":
			var fb := VisualFactory.make_metal_box(Vector3(0.34, 0.26, 0.24), Color("#2E2E33"))
			fb.position = Vector3(0.0, 0.0, 0.12)
			_icon.add_child(fb)
			var fire := VisualFactory.make_metal_box(Vector3(0.2, 0.03, 0.12), Color("#FF7A1E"), Color("#FF7A1E"), 1.6)
			fire.position = Vector3(0.0, -0.14, 0.09)
			_icon.add_child(fire)
			var ch := VisualFactory.make_metal_box(Vector3(0.08, 0.08, 0.14), Color("#3A3A40"))
			ch.position = Vector3(0.1, 0.06, 0.3)
			_icon.add_child(ch)
		"pickaxe":
			var handle := VisualFactory.make_flat_box(Vector3(0.05, 0.05, 0.4), Color("#8B5A2B"))
			handle.position = Vector3(0.0, 0.0, 0.2)
			handle.rotation.y = 0.5
			_icon.add_child(handle)
			var head := VisualFactory.make_metal_box(Vector3(0.3, 0.06, 0.07), Color("#C9CFD6"))
			head.position = Vector3(0.0, 0.0, 0.38)
			head.rotation.y = 0.5
			_icon.add_child(head)
		_:
			pass


# ══════════════════════ 推現貨入格：礦粒駛入墊即被吸收計數 ══════════════════════

func _build_feed_area() -> void:
	_feed_area = Area3D.new()
	_feed_area.name = "FeedArea"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.55, 0.5)
	col.shape = shape
	_feed_area.add_child(col)
	_feed_area.position = Vector3(0.0, 0.0, 0.2)
	_feed_area.body_entered.connect(_on_feed_body)
	add_child(_feed_area)

func _on_feed_body(body: Node3D) -> void:
	if _unlocked or ore_fed >= ore_cost:
		return
	if not (body is RigidBody3D) or not body.has_meta("slot"):
		return
	if body.has_meta("consume"):
		(body.get_meta("consume") as Callable).call(body)
	else:
		body.queue_free()
	ore_fed += 1.0
	_refresh()
	# 礦夠喇：即刻試買（現金唔夠就等，礦數保留）
	if ore_fed >= ore_cost and _on_tap.is_valid():
		_on_tap.call(region_id, cost)

func ore_ready() -> bool:
	return ore_fed >= ore_cost

extends PanelContainer
class_name GaragePanel

## 車房三軸升級面板（用戶 2026-09-18：參考 arcade idle 標準「速度／容量／收入」升級亭）。
## 純 UI：三行，每行 名稱 / Lv / 買掣；數值同扣錢由 field 處理（on_buy(axis) callback）。

const AXES := ["speed", "cargo", "price"]
const NAMES := {"speed": "車速", "cargo": "載量", "price": "賣價"}
const ICONS := {"speed": "res://assets/icons/arrowRight.png", "cargo": "res://assets/icons/plus.png", "price": "res://assets/icons/coin.png"}
const MAX_LEVEL := 10
const BASE_COST := {"speed": 120.0, "cargo": 150.0, "price": 200.0}
const GROWTH := 1.4

var on_buy: Callable # (axis: String) -> void
var _rows: Dictionary = {} # axis -> {lvl: Label, btn: Button}


static func cost_for(axis: String, lvl: int) -> float:
	return float(BASE_COST[axis]) * pow(GROWTH, float(lvl))

static func speed_mult(lvl: int) -> float:
	return 1.0 + 0.08 * float(lvl)

static func cargo_mult(lvl: int) -> float:
	return 1.0 + 0.1 * float(lvl)

static func price_mult(lvl: int) -> float:
	return 1.0 + 0.1 * float(lvl)

func setup(p_on_buy: Callable) -> void:
	on_buy = p_on_buy
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -300
	offset_right = 300
	offset_top = -420
	offset_bottom = -135
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.15, 0.96)
	sb.set_corner_radius_all(18)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "🔧 車房"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(60, 50)
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	for axis in AXES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		v.add_child(row)
		var ic := VisualFactory.make_icon(ICONS[axis], 36.0)
		row.add_child(ic)
		var name_l := Label.new()
		name_l.text = NAMES[axis]
		name_l.add_theme_font_size_override("font_size", 28)
		name_l.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_l)
		var lvl := Label.new()
		lvl.add_theme_font_size_override("font_size", 26)
		lvl.custom_minimum_size = Vector2(150, 0)
		lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lvl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(170, 60)
		btn.add_theme_font_size_override("font_size", 26)
		btn.pressed.connect(func() -> void: if on_buy.is_valid(): on_buy.call(axis))
		row.add_child(btn)
		_rows[axis] = {"lvl": lvl, "btn": btn}

## field 每幀傳入而家嘅等級同現金，呢度只更新文字／可撳唔可撳
func refresh(levels: Dictionary, cash: float) -> void:
	if not visible:
		return
	for axis in AXES:
		var l: int = int(levels.get(axis, 0))
		var r: Dictionary = _rows[axis]
		var mult: float = 1.0
		match axis:
			"speed": mult = speed_mult(l)
			"cargo": mult = cargo_mult(l)
			"price": mult = price_mult(l)
		(r["lvl"] as Label).text = "Lv%d  ×%.2f" % [l, mult]
		var btn: Button = r["btn"]
		if l >= MAX_LEVEL:
			btn.text = "MAX"
			btn.disabled = true
		else:
			var cst: float = cost_for(axis, l)
			btn.text = "● " + (("%.1fK" % (cst / 1000.0)) if cst >= 1000.0 else str(int(cst)))
			btn.disabled = cash < cst

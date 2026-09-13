extends Control

## ALTA-228（VR-12）區域 1 礦坑：Godot 2D 側視剖面灰模。
##
## 場景本身自成一體，冚晒 MineState（見同目錄 mine_state.gd）嘅數值模擬同
## 呢個 UI；唔掛靠 GameState／SaveManager／main.tscn——跨區域嘅共用錢包、
## 存檔、場景切換係 VR-11（區域地圖＋共用 autoload）嘅範圍，呢張 issue
## 淨係做呢個區域本身嘅玩法（見父 issue 附件 zone-map-v8.png「每個區域係
## 獨立 Godot 場景」）。日後 VR-11 接通嗰陣，_ready() 嘅 MineState.new()
## 應該改做由外部（區域地圖）注入已存檔嘅狀態。
##
## 冇搶 project.godot 嘅 run/main_scene（跟 README.md 已定嘅慣例：
## ad_test.tscn／event_log_debug.tscn 一樣）——依家想睇/測就用 Godot
## editor 開呢個 scene 撳 F6（Run Current Scene），或者出 APK 前臨時將
## run/main_scene 改去呢個 scene。
##
## 灰模風格：色塊 + Label，冚 VisualFactory.ORE_TIER_COLOR 做礦物階色板
## （純視覺 flavor，唔碰任何判分邏輯），其餘全部 code 砌 Control（跟
## main.gd _build_hud() 同一風格）。

const LAYER_NAMES := ["礦層 1", "礦層 2", "礦層 3"]
const LAYER_ORE_LABELS := ["石／煤", "銅／金", "鑽／皇冠"]
const LAYER_TIER_KEYS := [["stone", "coal"], ["copper", "gold"], ["diamond", "crown"]]

var state: MineState

var _cash_label: Label
var _bottleneck_label: Label
var _underground_bar: ProgressBar
var _underground_label: Label
var _ground_bar: ProgressBar
var _ground_label: Label

var _warehouse_rate_label: Label
var _warehouse_upgrade_button: Button
var _elevator_rate_label: Label
var _elevator_upgrade_button: Button

var _layer_rate_labels: Array[Label] = []
var _layer_upgrade_buttons: Array[Button] = []

var _layer4_price_label: Label


func _ready() -> void:
	state = MineState.new()
	_build_ui()
	_refresh_ui()


func _process(delta: float) -> void:
	state.tick(delta)
	_refresh_ui()


# ══════════════════════ UI 建構 ══════════════════════

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.09, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(720, 0)
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_build_bottleneck_banner())
	vbox.add_child(_build_warehouse_row())
	vbox.add_child(_build_ground_backlog_bar())
	vbox.add_child(_build_elevator_row())
	vbox.add_child(_build_underground_backlog_bar())
	for idx in range(3):
		vbox.add_child(_build_layer_row(idx))
	vbox.add_child(_build_layer4_locked_row())


func _build_header() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "區域 1 礦坑"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 22)
	_cash_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(_cash_label)

	return _padded(box)


func _build_bottleneck_banner() -> Control:
	_bottleneck_label = Label.new()
	_bottleneck_label.add_theme_font_size_override("font_size", 16)
	_bottleneck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return _padded(_bottleneck_label)


func _build_warehouse_row() -> Control:
	var row := _row_panel(Color(0.2, 0.4, 0.65))
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = "倉庫(收集 → 現金)"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_warehouse_rate_label = Label.new()
	vbox.add_child(_warehouse_rate_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	_warehouse_upgrade_button = Button.new()
	_warehouse_upgrade_button.pressed.connect(_on_upgrade_warehouse_pressed)
	btn_row.add_child(_warehouse_upgrade_button)
	btn_row.add_child(_manager_placeholder_button())
	vbox.add_child(btn_row)

	return row


func _build_elevator_row() -> Control:
	var row := _row_panel(Color(0.35, 0.35, 0.38))
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = "升降機塔 ＋ 地面運輸隊"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_elevator_rate_label = Label.new()
	vbox.add_child(_elevator_rate_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	_elevator_upgrade_button = Button.new()
	_elevator_upgrade_button.pressed.connect(_on_upgrade_elevator_pressed)
	btn_row.add_child(_elevator_upgrade_button)
	btn_row.add_child(_manager_placeholder_button())
	vbox.add_child(btn_row)

	return row


func _build_layer_row(idx: int) -> Control:
	var color: Color = VisualFactory.ORE_TIER_COLOR.get(LAYER_TIER_KEYS[idx][0], Color.GRAY)
	var row := _row_panel(color.darkened(0.3))
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = "%s(%s)" % [LAYER_NAMES[idx], LAYER_ORE_LABELS[idx]]
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var rate_label := Label.new()
	_layer_rate_labels.append(rate_label)
	vbox.add_child(rate_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	var upgrade_btn := Button.new()
	upgrade_btn.pressed.connect(_on_upgrade_layer_pressed.bind(idx))
	_layer_upgrade_buttons.append(upgrade_btn)
	btn_row.add_child(upgrade_btn)
	btn_row.add_child(_manager_placeholder_button())
	vbox.add_child(btn_row)

	return row


func _build_layer4_locked_row() -> Control:
	var row := _row_panel(Color(0.15, 0.15, 0.16))
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = "礦層 4 🔒"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(title)

	_layer4_price_label = Label.new()
	_layer4_price_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_layer4_price_label)

	return row


func _build_ground_backlog_bar() -> Control:
	var box := VBoxContainer.new()
	_ground_label = Label.new()
	_ground_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_ground_label)
	_ground_bar = ProgressBar.new()
	_ground_bar.max_value = 1.0
	_ground_bar.show_percentage = false
	box.add_child(_ground_bar)
	return _padded(box)


func _build_underground_backlog_bar() -> Control:
	var box := VBoxContainer.new()
	_underground_label = Label.new()
	_underground_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_underground_label)
	_underground_bar = ProgressBar.new()
	_underground_bar.max_value = 1.0
	_underground_bar.show_percentage = false
	box.add_child(_underground_bar)
	return _padded(box)


func _manager_placeholder_button() -> Button:
	# VR-12 issue：「每層／升降機／倉庫各有『經理』欄位（第二階段先接卡牌，
	# 先留 UI 位）」——呢期淨係佔位，唔功能化。
	var btn := Button.new()
	btn.text = "經理"
	btn.disabled = true
	btn.tooltip_text = "第二階段開放(經理卡)"
	return btn


func _row_panel(accent: Color) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	return panel


func _padded(child: Control) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_child(child)
	return margin


# ══════════════════════ UI 更新（每幀） ══════════════════════

func _refresh_ui() -> void:
	_cash_label.text = "$%s" % _format_number(state.cash)

	var stage := state.bottleneck_stage()
	match stage:
		"balanced":
			_bottleneck_label.text = "三段已平衡"
			_bottleneck_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		"layers":
			_bottleneck_label.text = "瓶頸：礦層開採(升降機／倉庫有餘力)"
			_bottleneck_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		"elevator":
			_bottleneck_label.text = "瓶頸：升降機(礦塞地底)"
			_bottleneck_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		"warehouse":
			_bottleneck_label.text = "瓶頸：倉庫收集(地面運輸隊塞車)"
			_bottleneck_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))

	_warehouse_rate_label.text = "收集上限 %.2f/s" % state.warehouse_capacity()
	if state.can_upgrade_warehouse():
		_warehouse_upgrade_button.text = "升級($%s)" % _format_number(state.next_warehouse_cost())
		_warehouse_upgrade_button.disabled = state.cash < state.next_warehouse_cost()
	else:
		_warehouse_upgrade_button.text = "已封頂 Lv%d" % state.warehouse_level
		_warehouse_upgrade_button.disabled = true

	_elevator_rate_label.text = "運載上限 %.2f/s" % state.elevator_capacity()
	if state.can_upgrade_elevator():
		_elevator_upgrade_button.text = "升級($%s)" % _format_number(state.next_elevator_cost())
		_elevator_upgrade_button.disabled = state.cash < state.next_elevator_cost()
	else:
		_elevator_upgrade_button.text = "已封頂 Lv%d" % state.elevator_level
		_elevator_upgrade_button.disabled = true

	for idx in range(3):
		_layer_rate_labels[idx].text = "出礦 %.2f ore/s(Lv%d)" % [state.layer_rate(idx), state.layer_level[idx]]
		var cost := state.next_layer_cost(idx)
		_layer_upgrade_buttons[idx].text = "升級($%s)" % _format_number(cost)
		_layer_upgrade_buttons[idx].disabled = state.cash < cost

	_layer4_price_label.text = "解鎖價 $%s(未開放)" % _format_number(state.c.layer4_unlock_price)

	var ug_ratio: float = clampf(state.underground_backlog / state.c.underground_backlog_cap, 0.0, 1.0)
	_underground_bar.value = ug_ratio
	_underground_label.text = "地底存量 %d%%%s" % [
		roundi(ug_ratio * 100.0), "(塞爆！)" if ug_ratio >= 0.999 else ""
	]

	var gr_ratio: float = clampf(state.ground_backlog / state.c.ground_backlog_cap, 0.0, 1.0)
	_ground_bar.value = gr_ratio
	_ground_label.text = "地面存量 %d%%%s" % [
		roundi(gr_ratio * 100.0), "(升降機停運！)" if gr_ratio >= 0.999 else ""
	]


func _format_number(value: float) -> String:
	if value >= 1000000.0:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.2fK" % (value / 1000.0)
	return "%.1f" % value


# ══════════════════════ 升級按鈕 callback ══════════════════════

func _on_upgrade_layer_pressed(idx: int) -> void:
	state.upgrade_layer(idx)
	_refresh_ui()

func _on_upgrade_elevator_pressed() -> void:
	state.upgrade_elevator()
	_refresh_ui()

func _on_upgrade_warehouse_pressed() -> void:
	state.upgrade_warehouse()
	_refresh_ui()

extends Control
class_name MineCrossSectionPanel

## ALTA-228（VR-12）Part B：礦道入口撳落去彈嘅 2D 剖面面板——升降機
## （礦車路軌）喺中、礦層向下疊、地面倉庫，每層／礦車／倉庫各一個升級
## 掣 + 經理欄位（灰，第二階段）。數字同 Part A（mine_zone.gd 嘅 3D 場景）
## 即時同步，因為兩者讀同一個 MineState 個體；關面板返 3D（唔 free 呢個
## node，淨係 hide，下次撳入口再 show，唔使重新 build）。
##
## 呢個 Control 唔擁有 Cash／MineState——構造由 MineZone 負責，夠唔夠錢
## 都係揸住 main.gd 傳落嚟嗰個 GameState（`state`）判斷，同
## systems/unlock_panel.gd 同一分工。main.gd／mine_zone.gd 每幀 call
## refresh() 就得，呢度唔自己 _process()（面板收埋嗰陣冇必要行）。

signal close_requested

const LAYER_NAMES := ["礦層 1", "礦層 2", "礦層 3"]

var mine: MineState
var state: GameState

var _cash_label: Label
var _bottleneck_label: Label
var _underground_bar: ProgressBar
var _underground_label: Label
var _ground_bar: ProgressBar
var _ground_label: Label

var _warehouse_rate_label: Label
var _warehouse_upgrade_button: Button
var _cart_rate_label: Label
var _cart_upgrade_button: Button

var _layer_rows: Array[Dictionary] = [] # 每層一個 {rate_label, action_button}


func setup(p_mine: MineState, p_state: GameState) -> void:
	mine = p_mine
	state = p_state
	_build_ui()
	refresh()


# ══════════════════════ UI 建構 ══════════════════════

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.08, 0.96) # 半透明深紫黑，貼返 IG 色調氣氛
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # 擋住背後 3D 世界嘅 tap（同 _build_modal_card() 嘅 scrim 一致）
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
	vbox.add_child(_build_backlog_bar("地面存量", "礦車停運！"))
	_ground_label = vbox.get_child(vbox.get_child_count() - 1).get_node("Content/Label")
	_ground_bar = vbox.get_child(vbox.get_child_count() - 1).get_node("Content/Bar")
	vbox.add_child(_build_cart_row())
	vbox.add_child(_build_backlog_bar("地底存量", "塞爆！"))
	_underground_label = vbox.get_child(vbox.get_child_count() - 1).get_node("Content/Label")
	_underground_bar = vbox.get_child(vbox.get_child_count() - 1).get_node("Content/Bar")
	for idx in range(MineConstants.LAYER_COUNT):
		vbox.add_child(_build_layer_row(idx))


func _build_header() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "區域 1 · 礦道剖面"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 20)
	_cash_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(_cash_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "關閉"
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	box.add_child(close_btn)

	return _padded(box)


func _build_bottleneck_banner() -> Control:
	_bottleneck_label = Label.new()
	_bottleneck_label.add_theme_font_size_override("font_size", 15)
	_bottleneck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return _padded(_bottleneck_label)


func _build_warehouse_row() -> Control:
	var row := _row_panel(Color("#6E3CA0"))
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = "倉庫（地面收集 → 現金）"
	title.add_theme_font_size_override("font_size", 17)
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


func _build_cart_row() -> Control:
	var row := _row_panel(Color("#5E3A8C"))
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = "礦車路軌（層台 → 倉庫）"
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)

	_cart_rate_label = Label.new()
	vbox.add_child(_cart_rate_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	_cart_upgrade_button = Button.new()
	_cart_upgrade_button.pressed.connect(_on_upgrade_cart_pressed)
	btn_row.add_child(_cart_upgrade_button)
	btn_row.add_child(_manager_placeholder_button())
	vbox.add_child(btn_row)

	return row


func _build_layer_row(idx: int) -> Control:
	var tier_key := "layer%d" % (idx + 1)
	var color: Color = Color(MineConstants.PALETTE.get(tier_key, "#8C7A6A"))
	var row := _row_panel(color)
	var vbox: VBoxContainer = row.get_node("VBox")

	var title := Label.new()
	title.text = LAYER_NAMES[idx]
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)

	var rate_label := Label.new()
	vbox.add_child(rate_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	var action_btn := Button.new()
	action_btn.pressed.connect(_on_layer_action_pressed.bind(idx))
	btn_row.add_child(action_btn)
	btn_row.add_child(_manager_placeholder_button())
	vbox.add_child(btn_row)

	_layer_rows.append({"rate_label": rate_label, "action_button": action_btn})
	return row


func _build_backlog_bar(label_prefix: String, warn_text: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "Content"
	var label := Label.new()
	label.name = "Label"
	label.add_theme_font_size_override("font_size", 13)
	label.set_meta("prefix", label_prefix)
	label.set_meta("warn", warn_text)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.max_value = 1.0
	bar.show_percentage = false
	box.add_child(bar)
	return _padded(box)


func _manager_placeholder_button() -> Button:
	# issue：「每層／礦車／倉庫各一個升級掣 + 經理欄位（灰，第二階段）」
	# ——呢度淨係佔位，唔功能化。
	var btn := Button.new()
	btn.text = "經理"
	btn.disabled = true
	btn.tooltip_text = "第二階段開放（經理卡）"
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


# ══════════════════════ 開／關 ══════════════════════

func open() -> void:
	visible = true
	refresh()

func close() -> void:
	visible = false


# ══════════════════════ 數值刷新（main.gd／mine_zone.gd 每幀 call） ══════════════════════

func refresh() -> void:
	if not visible:
		return # 面板收埋嗰陣唔使刷新，慳返啲嘢

	_cash_label.text = "$%s" % _format_number(state.cash)

	match mine.bottleneck_stage():
		"balanced":
			_bottleneck_label.text = "三段已平衡"
			_bottleneck_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		"layers":
			_bottleneck_label.text = "瓶頸：礦層開採（礦車／倉庫有餘力）"
			_bottleneck_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		"cart":
			_bottleneck_label.text = "瓶頸：礦車路軌（礦塞層台）"
			_bottleneck_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		"warehouse":
			_bottleneck_label.text = "瓶頸：倉庫收集（礦車停運）"
			_bottleneck_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))

	_warehouse_rate_label.text = "收集上限 %.2f/s" % mine.warehouse_capacity()
	if mine.can_upgrade_warehouse():
		_warehouse_upgrade_button.text = "升級 ($%s)" % _format_number(mine.next_warehouse_cost())
		_warehouse_upgrade_button.disabled = state.cash < mine.next_warehouse_cost()
	else:
		_warehouse_upgrade_button.text = "已封頂 Lv%d" % mine.warehouse_level
		_warehouse_upgrade_button.disabled = true

	_cart_rate_label.text = "運載上限 %.2f/s" % mine.cart_capacity()
	if mine.can_upgrade_cart():
		_cart_upgrade_button.text = "升級 ($%s)" % _format_number(mine.next_cart_cost())
		_cart_upgrade_button.disabled = state.cash < mine.next_cart_cost()
	else:
		_cart_upgrade_button.text = "已封頂 Lv%d" % mine.cart_level
		_cart_upgrade_button.disabled = true

	for idx in range(MineConstants.LAYER_COUNT):
		var row: Dictionary = _layer_rows[idx]
		var rate_label: Label = row["rate_label"]
		var action_btn: Button = row["action_button"]
		if mine.layer_unlocked[idx]:
			rate_label.text = "出礦 %.2f ore/s (Lv%d)" % [mine.layer_rate(idx), mine.layer_level[idx]]
			var cost: float = mine.next_layer_speed_cost(idx)
			action_btn.text = "升級 ($%s)" % _format_number(cost)
			action_btn.disabled = state.cash < cost
		else:
			var locked_by_prev: bool = idx > 0 and not mine.layer_unlocked[idx - 1]
			rate_label.text = "未鑿岩壁" if not locked_by_prev else "先解鎖上一層"
			var unlock_cost: float = mine.layer_unlock_cost(idx)
			action_btn.text = "解鎖 ($%s)" % _format_number(unlock_cost)
			action_btn.disabled = locked_by_prev or state.cash < unlock_cost

	var ug_ratio: float = clampf(mine.underground_backlog / mine.c.underground_backlog_cap, 0.0, 1.0)
	_underground_bar.value = ug_ratio
	_apply_backlog_label(_underground_label, ug_ratio)

	var gr_ratio: float = clampf(mine.ground_backlog / mine.c.ground_backlog_cap, 0.0, 1.0)
	_ground_bar.value = gr_ratio
	_apply_backlog_label(_ground_label, gr_ratio)


func _apply_backlog_label(label: Label, ratio: float) -> void:
	var prefix: String = label.get_meta("prefix")
	var warn: String = label.get_meta("warn")
	label.text = "%s %d%%%s" % [prefix, roundi(ratio * 100.0), (" (%s)" % warn) if ratio >= 0.999 else ""]


func _format_number(value: float) -> String:
	if value >= 1000000.0:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.2fK" % (value / 1000.0)
	return "%.1f" % value


# ══════════════════════ 升級／解鎖按鈕 callback ══════════════════════
# 呢度直接扣 state.cash（同 main.gd 其餘升級掣一致嘅做法），MineState
# 淨係郁自己嘅等級／解鎖旗標，唔識錢包。

func _on_upgrade_warehouse_pressed() -> void:
	var cost := mine.next_warehouse_cost()
	if not mine.can_upgrade_warehouse() or state.cash < cost:
		return
	state.cash -= cost
	mine.apply_warehouse_upgrade()
	SfxPlayer.play("upgrade")
	refresh()

func _on_upgrade_cart_pressed() -> void:
	var cost := mine.next_cart_cost()
	if not mine.can_upgrade_cart() or state.cash < cost:
		return
	state.cash -= cost
	mine.apply_cart_upgrade()
	SfxPlayer.play("upgrade")
	refresh()

func _on_layer_action_pressed(idx: int) -> void:
	if mine.layer_unlocked[idx]:
		var cost := mine.next_layer_speed_cost(idx)
		if state.cash < cost:
			return
		state.cash -= cost
		mine.apply_layer_speed_upgrade(idx)
	else:
		if not mine.can_unlock_layer(idx):
			return
		var cost := mine.layer_unlock_cost(idx)
		if state.cash < cost:
			return
		state.cash -= cost
		mine.apply_layer_unlock(idx)
	SfxPlayer.play("upgrade")
	refresh()

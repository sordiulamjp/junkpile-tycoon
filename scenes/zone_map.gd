extends Control

## VR-11：區域地圖（「Choose the next Level」式入口，PLAN v2 附件
## zone-map-v8.png）。開場先入呢度（project.godot run/main_scene 已經
## 改咗）——淨係做「顯示四張區域卡＋撳落切場景」，唔識任何區域自己嘅
## 玩法／數值，嗰啲全部留喺各區域自己嘅 scene/script（見下面 ZONES 嘅
## scene_path）。錢包／存檔都係 autoload（Wallet／Save），呢度淨係讀。
##
## 解鎖門檻（unlock_cost）暫時淨係卡面文字，唔係實際擋入場嘅判斷——
## 真正擋撳唔撳得入嘅係 scene_path 有冇嘢（即係「呢個區域起咗未」）。
## 原因：而家得返區域 4（沿用現有 main.tscn，VR-15 先會再改玩法）有場景，
## 如果連佢都要 3M Cash 先解鎖，新玩家一開場冇任何區域玩得，賺唔到嗰
## 3M——變相成個遊戲入唔到。等區域 1～3（VR-12～14）起好、玩家真係有
## 途徑賺到門檻金額之後，先應該將解鎖改做真正擋住＋扣錢嘅購買流程。
const ZONES := [
	{
		"id": "zone1", "title": "區域 1　礦坑",
		"subtitle": "側視放置：礦層＋升降機＋倉庫",
		"unlock_cost": 0.0, "scene_path": "", "color": Color(0.29, 0.2, 0.16),
	},
	{
		"id": "zone2", "title": "區域 2　紫岩礦場",
		"subtitle": "推堆穿透明倍數板、價錢墊、磚牆",
		"unlock_cost": 50000.0, "scene_path": "", "color": Color(0.24, 0.16, 0.32),
	},
	{
		"id": "zone3", "title": "區域 3　金河峽谷",
		"subtitle": "斜坑推金幣避岩漿、升級小屋、木閘",
		"unlock_cost": 500000.0, "scene_path": "", "color": Color(0.32, 0.16, 0.12),
	},
	{
		"id": "zone4", "title": "區域 4　峽谷礦道",
		"subtitle": "串聯倍數門、刺滾筒、岩漿木橋",
		"unlock_cost": 3000000.0, "scene_path": "res://main.tscn", "color": Color(0.16, 0.22, 0.28),
	},
]

var _cash_label: Label
var _zone_buttons: Array[Button] = []


func _ready() -> void:
	Save.load_and_apply_wallet()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Junkpile Tycoon － 區域地圖"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_cash_label = Label.new()
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cash_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_cash_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	_zone_buttons.clear()
	for zone: Dictionary in ZONES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 150.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = false

		var style := StyleBoxFlat.new()
		style.bg_color = zone["color"]
		style.set_corner_radius_all(12)
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		style.content_margin_top = 10.0
		style.content_margin_bottom = 10.0
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)

		var style_disabled: StyleBoxFlat = style.duplicate()
		style_disabled.bg_color = (zone["color"] as Color).darkened(0.35)
		button.add_theme_stylebox_override("disabled", style_disabled)

		var zone_id: String = zone["id"]
		button.pressed.connect(func() -> void: _on_zone_pressed(zone_id))
		grid.add_child(button)
		_zone_buttons.append(button)


func _refresh() -> void:
	_cash_label.text = "Cash %s ｜ Components %s ｜ Eco %s" % [
		_fmt_num(Wallet.cash), _fmt_num(Wallet.components), _fmt_num(Wallet.eco)
	]
	for i in ZONES.size():
		var zone: Dictionary = ZONES[i]
		var button := _zone_buttons[i]
		var built: bool = not String(zone["scene_path"]).is_empty()
		button.disabled = not built

		var cost: float = float(zone["unlock_cost"])
		var status_line: String
		if built:
			status_line = "撳入去"
		elif cost <= 0.0:
			status_line = "開發中"
		else:
			status_line = "開發中（未來解鎖 %s）" % _fmt_num(cost)
		button.text = "%s\n%s\n\n%s" % [zone["title"], zone["subtitle"], status_line]


func _on_zone_pressed(zone_id: String) -> void:
	for zone: Dictionary in ZONES:
		if zone["id"] != zone_id:
			continue
		var scene_path: String = zone["scene_path"]
		if scene_path.is_empty():
			return # 未起嘅區域——理論上掣已經 disabled，呢度淨係防手快撳穿
		get_tree().change_scene_to_file(scene_path)
		return


## 同 main.gd::_fmt_num() 一樣嘅 K/M 縮寫格式，兩處各自維護一份細
## function（呢個 script 冇引用 main.gd 嘅理由），冇共用 util module。
func _fmt_num(n: float) -> String:
	var sign_str := "-" if n < 0.0 else ""
	var v := absf(n)
	if v < 1000.0:
		return "%s%d" % [sign_str, int(round(v))]
	var units := ["K", "M", "B", "T"]
	var idx := -1
	while v >= 1000.0 and idx < units.size() - 1:
		v /= 1000.0
		idx += 1
	return "%s%.1f%s" % [sign_str, v, units[idx]]

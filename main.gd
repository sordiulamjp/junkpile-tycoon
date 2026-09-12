extends Node3D

## VR-03：放置場灰模（山腳 + 帶 + 爐 + 礦工 + 建築升級）。
##
## 灰模美術全部用 BoxMesh 喺 Godot 度直接砌（冇 Blender、冇 .blend）；
## 場景本身冇 hardcode 任何數值——全部經 GameConstants（`c`）／
## GameState（`state`）攞。呢個 script 淨係負責：擺位、畫面更新、
## 輸入轉接（tap-to-scoop）；核心數值邏輯全部喺 systems/game_state.gd，
## 方便 GUT 獨立測試（見 test/test_game_state.gd）。
##
## 座標：docx 場地座標 (x, y) 直接當世界單位用，y 向上（山向上長）；
## 相機用正交、望向 -Z，畫面淨用 (world.x, world.y)，Z 淨係俾盒仔有少少
## 立體厚度（冇透視變形）。screen_kx／screen_ky／screen_cy（docx）決定
## 正交相機嘅視野縮放同垂直置中，令山腳／帶／爐喺 3:4 直版入面啱晒
## HUD 12/66/22 版面。

## 山腳堆疊嘅盒仔尺寸——純美術造型，唔係遊戲數值，所以留喺呢度做
## script const（唔屬於 constants.gd 嘅「數值」，但相機取景要用嚟計算
## 山頂最高會去到邊，所以抽出嚟同 _rebuild_foothill_stack() 共用，
## 避免兩處各自 hardcode 一份出現唔一致）。
const FOOTHILL_BASE_HEIGHT := 0.3
const FOOTHILL_TIER_HEIGHT := 0.16

var c: GameConstants
var state: GameState
var rng := RandomNumberGenerator.new()

var _belt_visual_accum: float = 0.0
var _pile_spawn_timer: Timer

# -- 3D 節點 --
var _world: Node3D
var _foothill_root: Node3D
var _miners_root: Node3D
var _pile_root: Node3D
var _belt_items_root: Node3D

# -- HUD 節點 --
var _lock_label: Label
var _prestige_bar: ProgressBar
var _prestige_label: Label
var _cash_label: Label
var _components_label: Label
var _eco_label: Label
var _summon_button: Button
var _belt_upgrade_button: Button
var _miner_upgrade_button: Button
var _refine_upgrade_button: Button


func _ready() -> void:
	c = GameConstants.new()
	state = GameState.new(c)
	rng.randomize()

	get_viewport().physics_object_picking = true

	_build_world()
	_build_hud()

	_pile_spawn_timer = Timer.new()
	_pile_spawn_timer.wait_time = c.pile_debris_spawn_interval_secs
	_pile_spawn_timer.autostart = true
	_pile_spawn_timer.timeout.connect(_on_pile_spawn_timeout)
	add_child(_pile_spawn_timer)

	_refresh_hud()


func _process(delta: float) -> void:
	var result: Dictionary = state.tick(delta)
	_belt_visual_accum += float(result["fed"])
	while _belt_visual_accum >= 1.0:
		_belt_visual_accum -= 1.0
		_spawn_belt_visual_item()
	_refresh_hud()


# ══════════════════════ 建場景（灰模） ══════════════════════

func _site_to_world(v: Vector2, z: float = 0.0) -> Vector3:
	return Vector3(v.x, v.y, z)

## 由實際場地座標（山腳／帶頭／爐／倉，加山頂長到盡嘅高度）反推正交
## 相機嘅 size／中心，令呢啲物件嘅螢幕 Y 比例落喺 hud_top~1-hud_bottom
## 之間（中層 66% 果段），唔會俾頂／底 HUD 遮咗。
##
## 上一版單憑 docx 嘅 screen_kx／screen_ky／screen_cy 三個數推導鏡頭
## size／中心，撞出帶／爐／倉全部跌出畫面（Review 意見，見 ALTA-150）。
## 原 Canvas 工程／docx 冇留低呢三個數點樣換算做正交相機參數嘅公式，
## 淨憑估好易再撞第二次；而家改為直接由場地座標反推，保證幾個關鍵
## 節點實跌喺中層帶入面。screen_kx／screen_ky／screen_cy 冇再用喺呢個
## function（留喺 constants.gd 等後續搵返原公式或者遠端設定接手）。
func _compute_camera_frame() -> Dictionary:
	var pts: Array[Vector2] = [c.site_foothill_pos, c.belt_head_pos, c.smelter_pos, c.warehouse_pos]
	var min_x: float = pts[0].x
	var max_x: float = pts[0].x
	var min_y: float = pts[0].y
	var max_y: float = pts[0].y
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)

	# 山頂會隨召喚礦工長到最盡（miner_summon_cap 層），連埋預留返
	# 少少邊界，保證由 0 個礦工到 12 個礦工都留喺中層帶入面。
	var mountain_top: float = c.site_foothill_pos.y + FOOTHILL_BASE_HEIGHT \
		+ float(c.miner_summon_cap) * FOOTHILL_TIER_HEIGHT
	max_y = maxf(max_y, mountain_top)
	max_y += 0.3   # 山頂／礦工盒仔留白
	min_y -= 0.5   # 倉腳留白
	min_x -= 0.5
	max_x += 0.5

	var top_frac: float = c.hud_top / 100.0
	var bottom_frac: float = 1.0 - (c.hud_bottom / 100.0)

	var size: float = (max_y - min_y) / (bottom_frac - top_frac)
	var world_cy: float = max_y - size * (0.5 - top_frac)
	var world_cx: float = (min_x + max_x) * 0.5

	return {"size": size, "cx": world_cx, "cy": world_cy}

func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat
	return mesh_instance

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT # size＝視野「高度」，唔受畫面闊度影響
	var frame := _compute_camera_frame()
	cam.size = frame["size"]
	cam.position = Vector3(frame["cx"], frame["cy"], 10.0)
	cam.rotation = Vector3.ZERO # 望向 -Z
	cam.current = true
	_world.add_child(cam)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	_world.add_child(light)

	_foothill_root = Node3D.new()
	_foothill_root.name = "Foothill"
	_foothill_root.position = _site_to_world(c.site_foothill_pos)
	_world.add_child(_foothill_root)
	_rebuild_foothill_stack()

	var belt_track := _make_box(
		Vector3(0.18, 0.05, (c.belt_head_pos - c.smelter_pos).length()), Color(0.35, 0.35, 0.38)
	)
	belt_track.name = "BeltTrack"
	var belt_mid := (c.belt_head_pos + c.smelter_pos) * 0.5
	belt_track.position = _site_to_world(belt_mid)
	belt_track.look_at_from_position(belt_track.position, _site_to_world(c.smelter_pos), Vector3.UP)
	_world.add_child(belt_track)

	var smelter := _make_box(Vector3(0.5, 0.5, 0.5), Color(0.75, 0.35, 0.1))
	smelter.name = "Smelter"
	smelter.position = _site_to_world(c.smelter_pos, 0.25)
	_world.add_child(smelter)

	var warehouse := _make_box(Vector3(0.6, 0.45, 0.45), Color(0.2, 0.4, 0.65))
	warehouse.name = "Warehouse"
	warehouse.position = _site_to_world(c.warehouse_pos, 0.22)
	_world.add_child(warehouse)

	# 礦工／山腳碎料嘅本地座標係「相對山腳」嘅少少 jitter；root 本身要
	# 擺喺 site_foothill_pos，唔係就會全部跌喺世界原點（同底部 HUD
	# 個 ColorRect 重疊，tap 事件俾 GUI 食咗去唔到 physics picking——
	# Review 意見，見 ALTA-150）。
	_miners_root = Node3D.new()
	_miners_root.name = "MinersRoot"
	_miners_root.position = _site_to_world(c.site_foothill_pos)
	_world.add_child(_miners_root)

	_pile_root = Node3D.new()
	_pile_root.name = "PileRoot"
	_pile_root.position = _site_to_world(c.site_foothill_pos)
	_world.add_child(_pile_root)

	_belt_items_root = Node3D.new()
	_belt_items_root.name = "BeltItemsRoot"
	_world.add_child(_belt_items_root)

## 廢料山（往上長）：山腳一個底座 + 每召喚一個礦工加一層方塊，
## 視覺上表達「開採緊、堆越嚟越高」。上限同召喚上限一致（12）。
func _rebuild_foothill_stack() -> void:
	for child in _foothill_root.get_children():
		child.queue_free()
	var base := _make_box(Vector3(0.9, 0.3, 0.6), Color(0.42, 0.36, 0.3))
	base.position = Vector3(0.0, 0.0, 0.0)
	_foothill_root.add_child(base)
	var tiers: int = state.miner_count
	for i in range(tiers):
		var t: float = float(i) / float(maxi(c.miner_summon_cap, 1))
		var box := _make_box(
			Vector3(0.75 - t * 0.35, FOOTHILL_TIER_HEIGHT, 0.5 - t * 0.2), Color(0.5, 0.44, 0.36)
		)
		box.position = Vector3(0.0, FOOTHILL_BASE_HEIGHT + float(i) * FOOTHILL_TIER_HEIGHT, 0.0)
		_foothill_root.add_child(box)


# ══════════════════════ 礦工 ══════════════════════

func _try_summon_miner() -> void:
	if not state.summon_miner():
		return
	var miner := _make_box(Vector3(0.22, 0.4, 0.22), Color(0.95, 0.75, 0.1))
	miner.name = "Miner%d" % state.miner_count
	var jitter := Vector2(rng.randf_range(-0.3, 0.3), 0.0)
	miner.position = Vector3(jitter.x, 0.3, rng.randf_range(-0.2, 0.2))
	_miners_root.add_child(miner)
	_bob(miner)
	_rebuild_foothill_stack()

func _bob(node: Node3D) -> void:
	var tw := create_tween()
	tw.set_loops()
	var base_y := node.position.y
	tw.tween_property(node, "position:y", base_y + 0.08, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position:y", base_y, 0.4).set_trans(Tween.TRANS_SINE)


# ══════════════════════ 山腳碎料：手動 scoop ══════════════════════

func _on_pile_spawn_timeout() -> void:
	if state.pile_debris.size() >= c.miner_summon_cap:
		return # 山腳未撿碎料太多就唔再生（避免場景無限脹）
	var ore_key := state.spawn_pile_debris(rng, "foothill")
	if ore_key == "":
		return
	_spawn_pile_visual(ore_key)

func _spawn_pile_visual(ore_key: String) -> void:
	var chunk := _make_box(Vector3(0.12, 0.12, 0.12), _ore_color(ore_key))
	chunk.position = Vector3(rng.randf_range(-0.4, 0.4), 0.55, rng.randf_range(-0.3, 0.3))

	var area := Area3D.new()
	area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 0.12, 0.12)
	col.shape = shape
	area.add_child(col)
	chunk.add_child(area)
	# 未 belted 先接 tap handler；一入帶（_spawn_belt_visual_item）嘅盒仔
	# 完全冇 Area3D，結構上就已經保證「已 belted 碎料不可 scoop」。
	area.input_event.connect(_on_pile_chunk_input.bind(chunk, ore_key))

	_pile_root.add_child(chunk)

func _on_pile_chunk_input(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int,
	chunk: Node3D, ore_key: String
) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var gained := state.scoop_ore(ore_key)
	if gained > 0.0:
		chunk.queue_free()

func _ore_color(ore_key: String) -> Color:
	match ore_key:
		"stone": return Color(0.55, 0.55, 0.55)
		"coal": return Color(0.15, 0.15, 0.15)
		"copper": return Color(0.72, 0.42, 0.2)
		"gold": return Color(0.95, 0.8, 0.15)
		"diamond": return Color(0.6, 0.9, 0.95)
		"crown": return Color(0.85, 0.65, 0.95)
		_: return Color(0.7, 0.7, 0.7)


# ══════════════════════ 帶：視覺流動（純造型，唔影響數值）══════════════════════

## tick() 已經按帶產能上限算好實際入帳嘅 Cash；呢度淨係將 fed 轉做
## 一粒粒喺 BELT_HEAD → SMELTER → WAREHOUSE 之間飄過嘅盒仔，做視覺
## 回饋。呢啲盒仔冇 Area3D，唔會、亦唔應該俾人 tap 到。
func _spawn_belt_visual_item() -> void:
	var item := _make_box(Vector3(0.1, 0.1, 0.1), Color(0.8, 0.8, 0.7))
	item.position = _site_to_world(c.belt_head_pos, 0.1)
	_belt_items_root.add_child(item)

	var tw := create_tween()
	tw.tween_property(item, "position", _site_to_world(c.smelter_pos, 0.1), c.belt_visual_travel_secs)
	tw.tween_property(item, "position", _site_to_world(c.warehouse_pos, 0.1), c.belt_visual_travel_secs * 0.6)
	tw.tween_callback(item.queue_free)


# ══════════════════════ HUD ══════════════════════

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var top_frac: float = c.hud_top / 100.0
	var bottom_frac: float = c.hud_bottom / 100.0

	# -- 頂：常駐鎖住提示 + 威望進度（重置邏輯係 VR-05，呢度只顯示） --
	var top_bar := Control.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 0.0
	top_bar.anchor_bottom = top_frac
	hud.add_child(top_bar)

	var top_bg := ColorRect.new()
	top_bg.color = Color(0.08, 0.08, 0.1, 0.85)
	top_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_bar.add_child(top_bg)

	var top_vbox := VBoxContainer.new()
	top_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_bar.add_child(top_vbox)

	_lock_label = Label.new()
	# issue 文案要求完整數字「鎖住 · 2,000,000」，唔用 _fmt_num() 嘅
	# K/M 縮寫（嗰個係俾底部窄 HUD 用）。
	_lock_label.text = "鎖住 · %s" % _fmt_int_commas(c.unlock_price("mid"))
	top_vbox.add_child(_lock_label)

	_prestige_bar = ProgressBar.new()
	_prestige_bar.min_value = 0.0
	_prestige_bar.max_value = c.prestige_threshold(0)
	_prestige_bar.value = 0.0 # 威望重置邏輯見 VR-05，呢度淨係擺位
	top_vbox.add_child(_prestige_bar)

	_prestige_label = Label.new()
	_prestige_label.text = "威望 0 / %s" % _fmt_num(c.prestige_threshold(0))
	top_vbox.add_child(_prestige_label)

	# -- 底：三資源 + 召喚 + 三條升級線 --
	var bottom_bar := Control.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.anchor_top = 1.0 - bottom_frac
	hud.add_child(bottom_bar)

	var bottom_bg := ColorRect.new()
	bottom_bg.color = Color(0.08, 0.08, 0.1, 0.85)
	bottom_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_bar.add_child(bottom_bg)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_bar.add_child(bottom_vbox)

	var resources_row := HBoxContainer.new()
	bottom_vbox.add_child(resources_row)
	_cash_label = Label.new()
	_components_label = Label.new()
	_eco_label = Label.new()
	for lbl in [_cash_label, _components_label, _eco_label]:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resources_row.add_child(lbl)

	_summon_button = Button.new()
	_summon_button.text = "召喚礦工"
	_summon_button.pressed.connect(_try_summon_miner)
	bottom_vbox.add_child(_summon_button)

	var upgrades_row := HBoxContainer.new()
	bottom_vbox.add_child(upgrades_row)

	_belt_upgrade_button = Button.new()
	_belt_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_belt_upgrade_button.pressed.connect(func() -> void: state.upgrade_belt())
	upgrades_row.add_child(_belt_upgrade_button)

	_miner_upgrade_button = Button.new()
	_miner_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_miner_upgrade_button.pressed.connect(func() -> void: state.upgrade_miner_level())
	upgrades_row.add_child(_miner_upgrade_button)

	_refine_upgrade_button = Button.new()
	_refine_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refine_upgrade_button.pressed.connect(func() -> void: state.upgrade_refine())
	upgrades_row.add_child(_refine_upgrade_button)

func _refresh_hud() -> void:
	_cash_label.text = "Cash %s" % _fmt_num(state.cash)
	_components_label.text = "Components %s" % _fmt_num(state.components)
	_eco_label.text = "Eco %s" % _fmt_num(state.eco)

	_summon_button.text = "召喚礦工 (%d/%d)" % [state.miner_count, c.miner_summon_cap]
	_summon_button.disabled = not state.can_summon_miner() or state.cash < state.next_miner_cost()

	if state.can_upgrade_belt():
		_belt_upgrade_button.text = "帶 Lv%d → 升級 %s" % [state.belt_level, _fmt_num(state.next_belt_cost())]
		_belt_upgrade_button.disabled = state.cash < state.next_belt_cost()
	else:
		_belt_upgrade_button.text = "帶 Lv%d（封頂）" % state.belt_level
		_belt_upgrade_button.disabled = true

	_miner_upgrade_button.text = "礦工 Lv%d → 升級 %s" % [state.miner_level, _fmt_num(state.next_miner_level_cost())]
	_miner_upgrade_button.disabled = state.cash < state.next_miner_level_cost()

	_refine_upgrade_button.text = "精煉 Lv%d → 升級 %s" % [state.refine_level, _fmt_num(state.next_refine_level_cost())]
	_refine_upgrade_button.disabled = state.cash < state.next_refine_level_cost()

## 大數字縮寫成 K/M/B，HUD 底 22% 高度先放得落。
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

## 完整數字加千分位逗號（例如 2000000.0 → "2,000,000"），俾頂欄常駐
## 提示用——嗰度地方夠闊，issue 文案亦要求完整數字。
func _fmt_int_commas(n: float) -> String:
	var sign_str := "-" if n < 0.0 else ""
	var digits := str(int(round(absf(n))))
	var grouped := ""
	for i in range(digits.length()):
		var pos_from_right := digits.length() - i
		grouped += digits[i]
		if pos_from_right > 1 and pos_from_right % 3 == 1:
			grouped += ","
	return sign_str + grouped

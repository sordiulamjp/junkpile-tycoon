extends Node3D
class_name MineZone

## ALTA-228（VR-12）Part A：場內礦坑核心——後壁梯級礦層（terrace）+
## 礦車 Z 字路軌 + 倉庫 + 地面礦堆 + 三個推堆墊，掛喺 main.tscn 嘅場地
## 擴張框架下（VR-11／ALTA-227「同一場地，由下向上擴張」，唔係獨立
## 場景——Reviewer round 1 修正，取代第一版獨立 Control 場景）。
##
## main.gd 負責：擺位（`.position = _site_to_world(MINE_ZONE_SITE_POS,
## MINE_ZONE_ELEVATION)`——Reviewer round 2：山腳 12 層梯田＋峽谷後排石
## 恆常起足高，礦坑貼地擺喺後面會俾佢哋遮住，故意「浮高咗」一截先企
## 出嚟，見 main.gd MINE_ZONE_ELEVATION 註解）、`add_child(_placement_root)`、
## 每幀 call `tick(delta)`、`_refresh_hud()` 度 call `refresh_afford_state()`、
## 存檔讀寫 call `to_save_dict()` / 讀檔後將 dict 傳落 `setup()` 嘅
## `saved` 參數。呢個 class 自己擁有埋 Part B（MineCrossSectionPanel，
## 撳「礦道入口」toggle）、地面礦堆生成／tap、3 個推堆墊、2 個礦層解鎖
## 板——全部沿用 systems/unlock_panel.gd（唔重新起一套解鎖板）。
##
## 色調跟 Analyst 16:48「區域 1 規格」：IG 廣告 DdEYh2HMRW1 紫岩色調（見
## mine_constants.gd PALETTE）。

const LAYER_WIDTH := 2.4
const PALETTE := MineConstants.PALETTE

## Reviewer round 4：層 2／3 解鎖板舊位（掛喺 `_layer_center(idx)` 上面、
## z = 層高 + 0.3）企喺層台後面、離地 0.85 起跳——萬向車企地面（CAR_Z
## 0.14），加上層 1 台而家有實心 collider 擋住條路，車物理上去唔到嗰個
## 位，「駛入即觸發」得個講字。層 2／3 解鎖板唔會同時存在（一定要順序
## 解鎖，見 `_on_layer_unlock_tap()` 嘅 `can_unlock_layer()` 判斷），所以
## 淨係要一個車去到嘅地台位（同 `_build_push_pads()` 一樣 z=0.25、企喺
## 層台前面），唔使逐層各自一個位。
const LAYER_UNLOCK_PAD_POS := Vector3(1.75, -1.1, 0.12) # 倉庫下面、車到得嘅地面位（Analyst polish）

var state: MineState
var _game_state: GameState # main.gd 嘅共用 GameState——Wallet 背後嗰個 source of truth
var _frenzy: FrenzyState
var rng := RandomNumberGenerator.new()

var panel: MineCrossSectionPanel

var _layer_root: Node3D
var _pile_root: Node3D
var _cart_mesh: Node3D
var _cart_anim_t: float = 0.0

var _layer_unlock_panels: Array[UnlockPanel] = [] # index 對應 layer_unlocked idx（idx 0 一定唔會有）
var _push_panels: Array[UnlockPanel] = []

var _pile_spawn_timer: Timer


## saved：main.gd 讀檔攞到嘅 mine_zone 子 dict（見 data/save_manager.gd
## v2→v3 遷移），冇存檔就 {}（MineState 用預設值：層 1 開，層 2／3 鎖）。
##
## 淨係起 3D 部分（Part A）——Part B（剖面面板）要掛落 HUD CanvasLayer
## 先掛得啱 z-order／接得到 tap（Reviewer round 2：面板掛喺呢個 Node3D
## 底下預設 canvas layer 0，俾 HUD 嘅 CanvasLayer(1) 冚住/擋撳），見
## `attach_panel()`，main.gd `_build_hud()` 起完 HUD 先 call。
func setup(p_game_state: GameState, p_frenzy: FrenzyState, saved: Dictionary = {}) -> void:
	_game_state = p_game_state
	_frenzy = p_frenzy
	rng.randomize()
	state = MineState.new()
	_load_progress(saved)

	_layer_root = Node3D.new()
	_layer_root.name = "Layers"
	add_child(_layer_root)

	_pile_root = Node3D.new()
	_pile_root.name = "PileOre"
	add_child(_pile_root)

	_build_back_wall()
	_rebuild_layers()
	_build_rail_and_cart()
	_build_warehouse()
	_build_push_pads()
	_build_entrance()

	_pile_spawn_timer = Timer.new()
	_pile_spawn_timer.wait_time = state.c.pile_spawn_interval_secs
	_pile_spawn_timer.autostart = true
	_pile_spawn_timer.timeout.connect(_on_pile_spawn_timeout)
	add_child(_pile_spawn_timer)

## Part B：main.gd `_build_hud()` 起完 HUD（top_bar／bottom_bar／離線／
## 威望彈窗）之後 call 一次——面板掛落同一個 `hud_layer`，跟
## `_build_modal_card()` 嗰兩個彈窗同一層、同一種「後加入＝畫喺面」次序，
## 先保證面板嘅標題／Cash／「關閉」掣冚得過頂／底 HUD bar，撳得到。
func attach_panel(hud_layer: CanvasLayer) -> void:
	panel = MineCrossSectionPanel.new()
	panel.name = "MineCrossSectionPanel"
	hud_layer.add_child(panel)
	panel.setup(state, _game_state)
	panel.close_requested.connect(panel.close)


func _load_progress(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	var loaded_unlocked: Array = saved.get("layer_unlocked", [])
	for idx in range(mini(loaded_unlocked.size(), state.layer_unlocked.size())):
		state.layer_unlocked[idx] = bool(loaded_unlocked[idx])
	var loaded_levels: Array = saved.get("layer_level", [])
	for idx in range(mini(loaded_levels.size(), state.layer_level.size())):
		state.layer_level[idx] = int(loaded_levels[idx])
	state.cart_level = int(saved.get("cart_level", 1))
	state.warehouse_level = int(saved.get("warehouse_level", 1))
	state.push_tier = int(saved.get("push_tier", 0))

func to_save_dict() -> Dictionary:
	return {
		"layer_unlocked": state.layer_unlocked,
		"layer_level": state.layer_level,
		"cart_level": state.cart_level,
		"warehouse_level": state.warehouse_level,
		"push_tier": state.push_tier,
	}


# ══════════════════════ 每幀模擬 ══════════════════════

var _seen_cart_level := -1
var _seen_wh_level := -1
var _seen_layer_levels: Array = []
var _wh_crates: Array = []

func tick(delta: float) -> void:
	var result := state.tick(delta)
	_game_state.cash += float(result["cash_gain"])
	_animate_cart(delta)
	_watch_model_upgrades()
	if panel != null:
		panel.refresh() # 面板自己 visible=false 就即刻 return，收埋嗰陣冇額外成本

## 用戶 2026-09-20：升級直接變模型——礦車越大架、倉庫頂疊多啲箱、礦層每級多一個礦工（最多 5）
func _watch_model_upgrades() -> void:
	if state.cart_level != _seen_cart_level:
		_seen_cart_level = state.cart_level
		if _cart_mesh != null:
			_cart_mesh.scale = Vector3.ONE * (1.0 + 0.18 * float(state.cart_level - 1))
	if state.warehouse_level != _seen_wh_level:
		_seen_wh_level = state.warehouse_level
		_rebuild_wh_crates()
	if _seen_layer_levels != state.layer_level:
		var first: bool = _seen_layer_levels.is_empty()
		_seen_layer_levels = state.layer_level.duplicate()
		if not first:
			_rebuild_layers()

func _miners_for_level(lvl: int) -> int:
	return clampi(1 + lvl, 1, 5)

func _rebuild_wh_crates() -> void:
	for c in _wh_crates:
		if is_instance_valid(c):
			c.queue_free()
	_wh_crates.clear()
	var base := Vector3(LAYER_WIDTH * 0.5 + 0.65, -0.25, 0.25)
	var n: int = clampi(state.warehouse_level, 1, 6)
	for i in range(n):
		var col: int = i % 3
		var row: int = i / 3
		var crate := VisualFactory.make_model(VisualFactory.MODEL_CRATE, func() -> Node3D:
			var fb := Node3D.new()
			var body := VisualFactory.make_flat_box(Vector3(0.22, 0.22, 0.18), Color("#B8894A"))
			fb.add_child(body)
			var band := VisualFactory.make_flat_box(Vector3(0.24, 0.06, 0.2), Color("#6B4A24"))
			fb.add_child(band)
			return fb)
		crate.position = base + Vector3(-0.24 + float(col) * 0.24, 0.0, 0.4 + float(row) * 0.19)
		add_child(crate)
		_wh_crates.append(crate)

func _animate_miner(node: Node3D, phase: float) -> void:
	var base_z := node.position.z
	var tw := create_tween()
	tw.set_loops()
	tw.tween_interval(phase)
	tw.tween_property(node, "position:z", base_z + 0.05, 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position:z", base_z, 0.2).set_trans(Tween.TRANS_SINE)
	var sw := create_tween()
	sw.set_loops()
	sw.tween_interval(phase)
	sw.tween_property(node, "rotation:x", deg_to_rad(90.0) + 0.35, 0.18).set_trans(Tween.TRANS_SINE)
	sw.tween_property(node, "rotation:x", deg_to_rad(90.0), 0.24).set_trans(Tween.TRANS_SINE)
	# 礦工被 _rebuild_layers() 拆走嗰陣先殺 tween，否則 loop tween 對住已 free 嘅節點會報 Infinite loop
	node.tree_exiting.connect(func() -> void:
		tw.kill()
		sw.kill())

func _animate_cart(delta: float) -> void:
	_cart_anim_t += delta * (0.6 + 0.12 * float(state.cart_level - 1)) # 升級礦車即見到行快咗
	var rail_len: float = float(MineConstants.LAYER_COUNT) * MineConstants.LAYER_DEPTH_STEP
	var frac: float = (sin(_cart_anim_t) + 1.0) * 0.5
	_cart_mesh.position.y = frac * rail_len

## main.gd `_refresh_hud()` 每幀 call（同 `_region2_panel.refresh_afford_state()`
## 一致做法）——解鎖板／推堆墊嘅「夠唔夠錢」暗／亮色跟返即時 Cash。
func _find_panel(region_id: String) -> UnlockPanel:
	for p in _layer_unlock_panels:
		if p.region_id == region_id:
			return p
	for p in _push_panels:
		if p.region_id == region_id:
			return p
	return null

func refresh_afford_state() -> void:
	for p in _layer_unlock_panels:
		p.refresh_afford_state(_game_state.cash)
	for p in _push_panels:
		p.refresh_afford_state(_game_state.cash)


# ══════════════════════ 3D 視覺：後壁梯級礦層 ══════════════════════

func _layer_center(idx: int) -> Vector3:
	var y := float(idx) * MineConstants.LAYER_DEPTH_STEP + MineConstants.LAYER_DEPTH_STEP * 0.5
	var h := float(idx + 1) * MineConstants.LAYER_HEIGHT_STEP
	return Vector3(0.0, y, h * 0.5)

func _build_back_wall() -> void:
	var wall := VisualFactory.make_flat_box(
		Vector3(LAYER_WIDTH + 0.6, 0.3, 1.6), Color(PALETTE["wall_dark"])
	)
	wall.name = "BackWall"
	wall.position = Vector3(
		0.0, float(MineConstants.LAYER_COUNT) * MineConstants.LAYER_DEPTH_STEP + 0.15, 0.8
	)
	add_child(wall)

## 解鎖／升級都會改變某一層嘅外觀（未鑿岩壁 → 平台＋礦工），乾脆成組
## 重起，跟 main.gd `_rebuild_foothill_stack()` 同一做法（node 數量細，
## 成本可以忽略）。
func _rebuild_layers() -> void:
	for child in _layer_root.get_children():
		child.name = "_old_" + child.name # 讓出名稱：新起嘅同名節點先唔會被改名（LayerMiner0_0 → @Node3D@80）
		child.queue_free()
	_layer_unlock_panels.clear()
	for idx in range(MineConstants.LAYER_COUNT):
		_build_layer_terrace(idx)

func _build_layer_terrace(idx: int) -> void:
	var h := float(idx + 1) * MineConstants.LAYER_HEIGHT_STEP
	var box_size := Vector3(LAYER_WIDTH, MineConstants.LAYER_DEPTH_STEP, h)
	var tier_color: Color = Color(PALETTE["layer%d" % (idx + 1)])
	var unlocked: bool = state.layer_unlocked[idx]
	var platform := VisualFactory.make_flat_box(box_size, tier_color if unlocked else tier_color.darkened(0.35))
	platform.name = "LayerPlatform%d" % idx
	platform.position = _layer_center(idx)
	_layer_root.add_child(platform)

	# Reviewer round 3（field.tscn 萬向車）：VisualFactory.make_flat_box()
	# 純粹係 MeshInstance3D，冇 collider——萬向車冇嘢擋會直穿層台。加一個
	# StaticBody3D 貼實個台，同 `_rebuild_layers()` 一齊生命週期（解鎖／
	# 重起都會喺 _layer_root 底下重新起一份，唔使另外管理）。
	var collider := StaticBody3D.new()
	collider.name = "LayerCollider%d" % idx
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	collider.add_child(col)
	collider.position = platform.position
	_layer_root.add_child(collider)

	if unlocked:
		# issue：「每層：自己嘅礦工（層 1 開場 1 隻）」。
		# Analyst polish：每層 3 個礦工沿前緣分佈，面向岩壁揮鎬（tween）
		var n_m: int = _miners_for_level(state.layer_level[idx])
		for m in range(n_m):
			var miner := VisualFactory.make_miner()
			miner.name = "LayerMiner%d_%d" % [idx, m]
			var spread: float = LAYER_WIDTH * 0.8
			var mx: float = 0.0 if n_m == 1 else -spread * 0.5 + spread * float(m) / float(n_m - 1)
			miner.position = _layer_center(idx) + Vector3(mx, -MineConstants.LAYER_DEPTH_STEP * 0.25, box_size.z * 0.5 + 0.02)
			miner.rotation_degrees.x = 90.0
			_layer_root.add_child(miner)
			_animate_miner(miner, float(m) * 0.13)
		return

	# 鎖住：未鑿岩壁（岩石切面）+ UnlockPanel「解鎖 N」牌。
	var locked_by_prev: bool = idx > 0 and not state.layer_unlocked[idx - 1]
	var rock := VisualFactory.make_rock_facet(
		Vector3(LAYER_WIDTH * 0.85, 0.45, h * 0.7), Color(PALETTE["wall"]).darkened(0.2)
	)
	rock.name = "LockedRock%d" % idx
	rock.position = _layer_center(idx) + Vector3(0.0, 0.15, h * 0.15)
	_layer_root.add_child(rock)

	if locked_by_prev:
		return # 上一層都未解鎖，唔畀跳級——呢層淨係擺岩壁，未擺解鎖板

	var unlock_panel := UnlockPanel.new()
	unlock_panel.name = "LayerUnlockPanel%d" % idx
	unlock_panel.position = LAYER_UNLOCK_PAD_POS
	_layer_root.add_child(unlock_panel)
	unlock_panel.setup("layer%d" % idx, state.layer_unlock_cost(idx), "礦層 %d" % (idx + 1), _on_layer_unlock_tap, "pickaxe", state.layer_unlock_ore(idx))
	_layer_unlock_panels.append(unlock_panel)

func _on_layer_unlock_tap(region_id: String, cost: float) -> void:
	var idx := int(region_id.trim_prefix("layer"))
	if not state.can_unlock_layer(idx):
		return
	var panel: UnlockPanel = _find_panel(region_id)
	if _game_state.cash < cost or (panel != null and not panel.ore_ready()):
		return
	_game_state.cash -= cost
	state.apply_layer_unlock(idx)
	SfxPlayer.play("upgrade")
	EventLog.log_event("mine_layer_unlock", {"layer": idx, "cost": cost})
	_rebuild_layers() # 上一層解鎖之後，下一層可能由「未擺解鎖板」變「擺到」


# ══════════════════════ 3D 視覺：礦車路軌 + 倉庫 ══════════════════════

func _build_rail_and_cart() -> void:
	var rail_len: float = float(MineConstants.LAYER_COUNT) * MineConstants.LAYER_DEPTH_STEP
	var rail := VisualFactory.make_flat_box(Vector3(0.12, rail_len + 0.4, 0.05), Color(PALETTE["wall_dark"]).lightened(0.15))
	rail.name = "Rail"
	rail.position = Vector3(LAYER_WIDTH * 0.5 + 0.2, rail_len * 0.5, 0.05)
	add_child(rail)

	_cart_mesh = Node3D.new()
	_cart_mesh.name = "Cart"
	_cart_mesh.position = Vector3(LAYER_WIDTH * 0.5 + 0.2, 0.0, 0.12)
	add_child(_cart_mesh)
	var cart_model := VisualFactory.make_model(VisualFactory.MODEL_MINE_CART, func() -> Node3D:
		return VisualFactory.make_metal_box(Vector3(0.22, 0.16, 0.14), Color("#F2B830")))
	_cart_mesh.add_child(cart_model)
	var cb := AnimatableBody3D.new() # 用戶 2026-09-20：礦車係實體
	cb.sync_to_physics = true
	var cc := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(0.22, 0.16, 0.14)
	cc.shape = cs
	cb.add_child(cc)
	_cart_mesh.add_child(cb)

func _build_warehouse() -> void:
	var wh_pos := Vector3(LAYER_WIDTH * 0.5 + 0.65, -0.25, 0.25)
	var model := VisualFactory.make_model(VisualFactory.MODEL_WAREHOUSE, func() -> Node3D:
		var fb := Node3D.new()
		var wh := VisualFactory.make_flat_box(Vector3(0.8, 0.55, 0.5), Color(PALETTE["wall_light"]).darkened(0.15))
		fb.add_child(wh)
		var roof := VisualFactory.make_flat_box(Vector3(0.9, 0.65, 0.06), Color(PALETTE["wall_dark"]))
		roof.position = Vector3(0.0, 0.0, 0.28)
		fb.add_child(roof)
		var door := VisualFactory.make_flat_box(Vector3(0.3, 0.02, 0.32), Color(PALETTE["wall_dark"]).darkened(0.3))
		door.position = Vector3(0.0, -0.28, -0.08)
		fb.add_child(door)
		return fb)
	model.name = "Warehouse"
	model.position = wh_pos
	add_child(model)

	var whb := StaticBody3D.new() # 用戶 2026-09-20：倉庫係實體
	var whc := CollisionShape3D.new()
	var whs := BoxShape3D.new()
	whs.size = Vector3(0.9, 0.65, 0.6)
	whc.shape = whs
	whb.add_child(whc)
	whb.position = wh_pos + Vector3(0.0, 0.0, 0.05)
	add_child(whb)
	# 屋頂木箱由 _rebuild_wh_crates() 按倉庫等級疊


# ══════════════════════ 3D 視覺：礦道入口（toggle 剖面面板） ══════════════════════

## Reviewer round 3：舊位置（0, -0.3, 0.35）同「大鏟斗」推堆墊
## （push2 = _build_push_pads() i=2，x=0.25/y=-0.2/z=0.25）Area3D 重疊——
## 牌身俾墊擋住、撳落去仲會撞埋第二個 Area3D（邊個先中 ray 邊個食）。
## 層 1 開場恆常解鎖，_build_layer_terrace() unlocked 分支唔會幫佢起
## UnlockPanel（果段邏輯淨係鎖住層先有），即係層 2／3 UnlockPanel 嗰條掛
## 牌公式（`_layer_center(idx) + (0, -DEPTH_STEP*0.3, h+0.3)`）套用落層 1
## 會得出嚟嘅位一直得閒——搬去嗰度：z 企得夠高（0.65 起跳），同推堆墊
## z 上限（0.4）完全唔再重疊，唔使郁推堆墊本身（已通過 round 2 嘅取景）。
func _build_entrance() -> void:
	var h0 := MineConstants.LAYER_HEIGHT_STEP # idx0 層高——同 _build_layer_terrace() 嗰個 h 一致
	var sign_pos: Vector3 = _layer_center(0) + Vector3(0.0, -MineConstants.LAYER_DEPTH_STEP * 0.3, h0 + 0.3)

	# 用戶 2026-09-14：圖示代替文字——礦道入口做木框拱門 + 兩盞燈，撳門開剖面
	var sign := Node3D.new()
	sign.name = "EntranceSign"
	sign.position = sign_pos
	add_child(sign)
	var model := VisualFactory.make_model(VisualFactory.MODEL_MINE_ENTRANCE, func() -> Node3D:
		var fb := Node3D.new()
		for px in [-0.32, 0.32]:
			var post := VisualFactory.make_flat_box(Vector3(0.09, 0.09, 0.55), Color("#8B5A2B"))
			post.position = Vector3(px, 0.0, 0.0)
			fb.add_child(post)
			var lamp := VisualFactory.make_lamp(0.045, Color("#FFD27A"))
			lamp.position = Vector3(px, -0.08, 0.2)
			fb.add_child(lamp)
		var lintel := VisualFactory.make_flat_box(Vector3(0.8, 0.12, 0.09), Color("#6B4A24"))
		lintel.position = Vector3(0.0, 0.0, 0.31)
		fb.add_child(lintel)
		var dark := VisualFactory.make_flat_box(Vector3(0.6, 0.02, 0.5), Color("#1A1420"))
		dark.position = Vector3(0.0, 0.08, 0.0)
		fb.add_child(dark)
		return fb)
	sign.add_child(model)

	var area := Area3D.new()
	area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.4, 0.5)
	col.shape = shape
	area.add_child(col)
	area.position = sign.position
	add_child(area)
	area.input_event.connect(_on_entrance_input)

## Part B 驗收：「撳礦道入口先開剖面面板，關咗返 3D」——toggle，唔係淨
## 開一路。
func _on_entrance_input(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if panel.visible:
		panel.close()
	else:
		panel.open()


# ══════════════════════ 3D 視覺：推堆墊（150／500／1000 鏟斗 tier） ══════════════════════

func _build_push_pads() -> void:
	# Reviewer round 2：Y 方向（深度）排開喺遠鏡頭底下透視壓縮到幾乎疊
	# 埋一齊（三個牌文字疊晒），改用橫向（X）排開，唔受深度壓縮影響。
	for i in range(state.c.push_tier_cost.size()):
		var p := UnlockPanel.new()
		p.name = "PushPad%d" % i
		p.position = Vector3(-LAYER_WIDTH * 0.5 - 0.55 + float(i) * 1.05, -0.2, 0.12)
		add_child(p)
		var region_id := "push%d" % i
		p.setup(region_id, state.c.push_tier_cost[i], state.c.push_tier_names[i], _on_push_tap, ["blade", "furnace", "blade_big"][i], state.c.push_tier_ore[i] if i < state.c.push_tier_ore.size() else 0.0)
		if i < state.push_tier:
			p.mark_unlocked()
		_push_panels.append(p)

	if state.push_tier > 0:
		_apply_shovel_preview()

func _on_push_tap(region_id: String, cost: float) -> void:
	var idx := int(region_id.trim_prefix("push"))
	if idx != state.push_tier: # 一定要順序買，唔可以跳級
		return
	var panel: UnlockPanel = _find_panel(region_id)
	if _game_state.cash < cost or (panel != null and not panel.ore_ready()):
		return
	_game_state.cash -= cost
	state.apply_push_tier_upgrade()
	SfxPlayer.play("upgrade")
	EventLog.log_event("mine_push_tier_upgrade", {"tier": state.push_tier, "cost": cost})
	if idx < _push_panels.size():
		_push_panels[idx].mark_unlocked()
	_apply_shovel_preview()

## issue：「車黃色弧形鏟斗；150 鏟斗墊（半透明藍鏟預覽）」——買咗至少
##一級之後，車頂加一嚿半透明藍色鏟斗預覽，純視覺回饋買咗嘢。
func _apply_shovel_preview() -> void:
	if _cart_mesh == null or _cart_mesh.get_node_or_null("ShovelPreview") != null:
		return
	var shovel := VisualFactory.make_flat_box(Vector3(0.26, 0.1, 0.08), Color(PALETTE["shovel_preview"]))
	shovel.name = "ShovelPreview"
	var mat: StandardMaterial3D = shovel.material_override
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shovel.position = Vector3(0.0, 0.14, 0.05)
	_cart_mesh.add_child(shovel)


# ══════════════════════ 地面礦堆：生成 + tap 收礦 ══════════════════════

func _on_pile_spawn_timeout() -> void:
	var ore_key := state.spawn_pile(rng)
	if ore_key == "":
		return
	_spawn_pile_visual(ore_key)

## issue：「礦工敲層 1 前緣，礦粒瀉落地面成堆」——擺喺層 1（idx 0）平台
## 前緣、地面之上。
func _spawn_pile_visual(ore_key: String) -> void:
	var color: Color = Color(PALETTE["ore_silver"]) if ore_key == "silver" else Color(PALETTE["ore_gold"])
	var chunk := VisualFactory.make_ore_chunk(0.16, color)
	var x: float = rng.randf_range(-LAYER_WIDTH * 0.35, LAYER_WIDTH * 0.35)
	chunk.position = Vector3(x, -0.12 + rng.randf_range(-0.04, 0.04), 0.08)
	chunk.rotation_degrees.x = 90.0
	chunk.rotation.z = rng.randf_range(0.0, TAU)

	var area := Area3D.new()
	area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.3
	col.shape = shape
	area.add_child(col)
	chunk.add_child(area)
	area.input_event.connect(_on_pile_tap.bind(chunk, area, ore_key))

	_pile_root.add_child(chunk)

func _on_pile_tap(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int,
	chunk: Node3D, area: Area3D, ore_key: String
) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var frenzy_active: bool = _frenzy != null and _frenzy.active
	var gained := state.scoop_pile(ore_key, frenzy_active)
	if gained <= 0.0:
		return
	_game_state.cash += gained
	area.input_ray_pickable = false # 撳中即停接輸入，唔會同一粒重複扣
	SfxPlayer.play("pile_mine")
	chunk.queue_free()

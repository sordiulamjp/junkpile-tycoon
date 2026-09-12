extends Node3D

## VR-03：放置場灰模（山腳 + 帶 + 爐 + 礦工 + 建築升級）。
## VR-06：換皮——美術全部改由 systems/visual_factory.gd（VisualFactory）
## 同 systems/sfx_player.gd（SfxPlayer autoload）出，呢個 script 淨係
## 揀「邊個位置整邊種物件」，唔再自己起 mesh／材質（見 CREDITS.md 嘅
## 資產來源）。
##
## 場景本身冇 hardcode 任何數值——全部經 GameConstants（`c`）／
## GameState（`state`）攞。呢個 script 淨係負責：擺位、畫面更新、
## 輸入轉接（tap-to-scoop）；核心數值邏輯全部喺 systems/game_state.gd，
## 方便 GUT 獨立測試（見 test/test_game_state.gd）。
##
## 座標：docx 場地座標 (x, y) 直接當世界單位用，y 向上（山向上長），Z
## 俾盒仔少少立體厚度——**成個放置場＋車場（VR-03／VR-04 共用）實際上
## 全部住喺世界 Z=0 呢個平面**，斜視相機淨係改咗「點睇呢個平面」，冇
## 將場地重新擺去地面 (XZ) 平面。（Review 意見，ALTA-150 round 3：
## 曾經考慮改做「地面平面＋真垂直 Y」嘅古典等角視角，但 VR-04 車場
## 一大堆已審過嘅座標常數（gates／spike_roller_pos／lava_bridge_y／
## yard_x_range 等）全部跟緊現有 Z=0 平面假設，改嗰個要重新過晒 VR-04
## 判分／物理，超出呢個 playtest-fix issue 嘅範圍，所以維持現狀；
## touch→world 嘅映射（FrenzyYardView._unhandled_input()）已經改用
## 射線同 Z=0 平面求交，唔再假設相機正面望 -Z，所以呢個決定唔會再
## 逼手指映射嗰段代碼重做多次。副作用：帶／車道／四道門呢類橫向佈局
## 斜視之後會睇落斜咗（唔再係水平線），純美術取捨，留返俾日後獨立
## 設計 issue 處理。）相機用正交，跟 docx §6 斜視 pitch/yaw 約
## −55°／45°（screen_camera_pitch_deg／screen_camera_yaw_deg，用戶實機
## 回饋 ALTA-150：正面平視令方塊變 2D 色塊），令 BoxMesh 睇得出側面/立
## 體感（配 DirectionalLight3D 陰影）。size／位置由 _compute_camera_frame()
## 直接由場地座標反推，保證山腳／帶／爐／倉喺 3:4 直版入面啱晒 HUD
## 12/66/22 版面（screen_kx／screen_ky／screen_cy 冇再用，留喺
## constants.gd）。

## 山腳堆疊嘅盒仔尺寸——純美術造型，唔係遊戲數值，所以留喺呢度做
## script const（唔屬於 constants.gd 嘅「數值」，但相機取景要用嚟計算
## 山頂最高會去到邊，所以抽出嚟同 _rebuild_foothill_stack() 共用，
## 避免兩處各自 hardcode 一份出現唔一致）。
const FOOTHILL_BASE_HEIGHT := 0.3
const FOOTHILL_TIER_HEIGHT := 0.16

## 山腳碎料嘅 tap 拾取範圍——刻意獨立於 0.12 嘅視覺盒仔尺寸（ALTA-195，
## 實機驗收見 Reviewer 喺 ALTA-150 嘅提醒）。720×960 下依家個相機要一次
## 框晒山腳到山頂長到盡（12 層），令 1 世界單位≈107px，跟視覺尺寸嘅
## Area3D 淨得 ~13px 闊——遠細過 44px 呢類慣常 tap 目標下限，實機撳唔中。
## 呢度冇改鏡頭（12 層山高仍然要一次框晒，中層帶／爐／倉先唔會跌出
## 畫面），淨係將拾取形狀獨立放大到 ~43px（0.4 世界單位），視覺盒仔
## 大細不變。
const PILE_CHUNK_TAP_HIT_SIZE := 0.4

## 山腳碎料嘅視覺盒仔尺寸——用戶實機回饋（ALTA-150）：原本 0.12 太細
## （~10px），睇唔到、都冇提示點撳，放大到最少 0.25（tap 形狀
## PILE_CHUNK_TAP_HIT_SIZE 已經係 0.4，呢個純粹係美術造型，冇改拾取）。
const PILE_CHUNK_VISUAL_SIZE := 0.25

var c: GameConstants
var state: GameState
var frenzy: FrenzyState
var rng := RandomNumberGenerator.new()

var _belt_visual_accum: float = 0.0
var _pile_spawn_timer: Timer
var _remote_constants_loader: RemoteConstantsLoader # VR-08

# -- 3D 節點 --
var _world: Node3D
var _placement_root: Node3D # VR-04：狂熱期間成個放置場收埋，畀車場借同一個 camera
var _foothill_root: Node3D
var _miners_root: Node3D
var _pile_root: Node3D
var _belt_items_root: Node3D
var _frenzy_view: FrenzyYardView

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
var _frenzy_button: Button
var _scoop_hint_label: Label # 開場提示「撳碎料鏟入爐」，第一次剷完就收起（ALTA-150 實機回饋）
var _scoop_hint_shown: bool = false


func _ready() -> void:
	c = GameConstants.new()
	state = GameState.new(c)
	frenzy = FrenzyState.new(c)
	rng.randomize()

	get_viewport().physics_object_picking = true

	_build_world()
	_build_hud()

	_frenzy_view = FrenzyYardView.new(c, state, frenzy)
	_frenzy_view.name = "FrenzyYard"
	_world.add_child(_frenzy_view)

	_pile_spawn_timer = Timer.new()
	_pile_spawn_timer.wait_time = c.pile_debris_spawn_interval_secs
	_pile_spawn_timer.autostart = true
	_pile_spawn_timer.timeout.connect(_on_pile_spawn_timeout)
	add_child(_pile_spawn_timer)

	_refresh_hud()

	# VR-08：本機事件 log + 遠端 constants 覆寫，見 systems/event_log.gd／
	# systems/remote_constants_loader.gd。呢兩樣都喺世界／HUD 起晒之後
	# 先做，唔會拖慢開場（背景 fetch，攞唔到就繼續用本機預設）。
	EventLog.log_event("session_start")
	_start_remote_constants_fetch()


## 開機背景攞遠端 constants 覆寫；成功就直接 set() 落現有嘅 `c`（同一個
## Resource 個體，state／frenzy／_frenzy_view 全部揸緊呢個 reference，
## 唔使逐個傳過），失敗就乜都唔做（維持本機預設）。
func _start_remote_constants_fetch() -> void:
	_remote_constants_loader = RemoteConstantsLoader.new()
	add_child(_remote_constants_loader)
	_remote_constants_loader.finished.connect(_on_remote_constants_loaded)
	_remote_constants_loader.start()

func _on_remote_constants_loaded(overrides: Dictionary, _source: String) -> void:
	if overrides.is_empty():
		return
	for key: String in overrides:
		c.set(key, overrides[key])
	_refresh_hud() # 有覆寫升級價／狂熱數值等 → HUD 顯示緊嘅價錢即刻反映新值


func _process(delta: float) -> void:
	var result: Dictionary = state.tick(delta)
	_belt_visual_accum += float(result["fed"])
	while _belt_visual_accum >= 1.0:
		_belt_visual_accum -= 1.0
		_spawn_belt_visual_item()

	var events: Dictionary = frenzy.tick(delta)
	if events["gear_spawn"]:
		_frenzy_view.spawn_gear()
	if events["ended"]:
		_on_frenzy_ended()

	_refresh_hud()


# ══════════════════════ VR-04：狂熱車場觸發 ══════════════════════

func _try_start_frenzy() -> void:
	var income_rate := state.current_income_rate()
	if not frenzy.start(income_rate):
		return
	EventLog.log_event("frenzy_start", {"income_rate": income_rate})
	SfxPlayer.play("frenzy_start")
	_placement_root.visible = false
	# Review 意見：淨係隱藏 _placement_root 唔會關咗山腳碎料 Area3D 嘅
	# 揀選——CollisionObject3D 物理揀選同 VisualInstance3D visible 係
	# 兩件事，隱形碎料狂熱期間仍然 tap 得中。狂熱嘅車／門／滾筒／爐
	# 全部靠 body_entered／_unhandled_input，冇一個靠 physics_object_picking，
	# 所以成個 viewport 揼熄佢係安全嘅。
	get_viewport().physics_object_picking = false
	_frenzy_view.start()

func _on_frenzy_ended() -> void:
	EventLog.log_event("frenzy_end", {"eco_bonus": frenzy.eco_bonus_earned})
	state.eco += frenzy.eco_bonus_earned
	_frenzy_view.stop()
	_placement_root.visible = true
	get_viewport().physics_object_picking = true


# ══════════════════════ 建場景（灰模） ══════════════════════

func _site_to_world(v: Vector2, z: float = 0.0) -> Vector3:
	return Vector3(v.x, v.y, z)

## 由實際場地座標（山腳／帶頭／爐／倉，加山頂長到盡嘅高度）反推正交
## 相機嘅 size／位置，令呢啲物件嘅螢幕 Y 比例落喺 hud_top~1-hud_bottom
## 之間（中層 66% 果段），唔會俾頂／底 HUD 遮咗。
##
## 相機依家跟 docx §6 斜視咗（screen_camera_pitch_deg／screen_camera_yaw_deg，
## 用戶實機回饋 ALTA-150：正面平視令 BoxMesh 睇落係死板 2D 色塊），唔再係
## 望向 -Z 嘅平面投影，所以「世界 x/y＝螢幕 x/y」呢個假設唔再成立。做法：
## 將關鍵場地點轉去相機自己嘅本地座標系（basis 轉置＝world→local，
## 因為 basis 係正交矩陣），喺嗰個座標系度做返同上一版一樣嘅 bounding-box
## 反推（size／置中），再將反推出嚟嘅本地座標轉返做世界座標畀 cam.position。
##
## 上一版單憑 docx 嘅 screen_kx／screen_ky／screen_cy 三個數推導鏡頭
## size／中心，撞出帶／爐／倉全部跌出畫面；原 Canvas 工程／docx 冇留低
## 呢三個數點樣換算做正交相機參數嘅公式，淨憑估好易再撞第二次——而家
## 一律由場地座標反推，保證幾個關鍵節點實跌喺中層帶入面。screen_kx／
## screen_ky／screen_cy 冇再用喺呢個 function（留喺 constants.gd 等後續
## 搵返原公式或者遠端設定接手）。
func _compute_camera_frame() -> Dictionary:
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(c.screen_camera_pitch_deg), deg_to_rad(c.screen_camera_yaw_deg), 0.0)
	)
	var basis_t := basis.transposed() # 正交矩陣嘅轉置＝反矩陣，world→local

	# 山頂會隨召喚礦工長到最盡（miner_summon_cap 層），連山腳 x 一齊入 pts。
	var mountain_top_y: float = c.site_foothill_pos.y + FOOTHILL_BASE_HEIGHT \
		+ float(c.miner_summon_cap) * FOOTHILL_TIER_HEIGHT
	var world_pts: Array[Vector3] = [
		_site_to_world(c.site_foothill_pos),
		_site_to_world(Vector2(c.site_foothill_pos.x, mountain_top_y)),
		_site_to_world(c.belt_head_pos),
		_site_to_world(c.smelter_pos, 0.25),
		_site_to_world(c.warehouse_pos, 0.22),
	]

	var min_lx: float = INF
	var max_lx: float = -INF
	var min_ly: float = INF
	var max_ly: float = -INF
	var max_lz: float = -INF
	for p in world_pts:
		var l: Vector3 = basis_t * p
		min_lx = minf(min_lx, l.x)
		max_lx = maxf(max_lx, l.x)
		min_ly = minf(min_ly, l.y)
		max_ly = maxf(max_ly, l.y)
		max_lz = maxf(max_lz, l.z)

	max_ly += 0.3   # 山頂／礦工盒仔留白
	min_ly -= 0.5   # 倉腳留白
	min_lx -= 0.5
	max_lx += 0.5

	var top_frac: float = c.hud_top / 100.0
	var bottom_frac: float = 1.0 - (c.hud_bottom / 100.0)

	var size: float = (max_ly - min_ly) / (bottom_frac - top_frac)
	var local_cx: float = (min_lx + max_lx) * 0.5
	var local_cy: float = max_ly - size * (0.5 - top_frac)
	var local_cz: float = max_lz + 10.0 # 相機沿住自己嘅 -forward 退後喺場景後面

	var cam_pos: Vector3 = basis.x * local_cx + basis.y * local_cy + basis.z * local_cz
	return {"size": size, "position": cam_pos}

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT # size＝視野「高度」，唔受畫面闊度影響
	# docx §6：斜視 2.5D（用戶實機回饋 ALTA-150，正面平視令方塊變 2D 色塊）。
	cam.rotation_degrees = Vector3(c.screen_camera_pitch_deg, c.screen_camera_yaw_deg, 0.0)
	var frame := _compute_camera_frame()
	cam.size = frame["size"]
	cam.position = frame["position"]
	cam.current = true
	_world.add_child(cam)

	# VR-06：洞穴暖色環境光 + 帶陰影嘅太陽光，代替預設冇環境光嘅平光。
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.13, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.46, 0.4)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_world.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	# 用戶實機回饋（ALTA-150）：斜視之後 BoxMesh 要睇得出側面／立體感，
	# 加返淡陰影（低 energy／唔太重手，避免灰模睇落太暗）；VR-06 加暖色
	# 溫度（洞穴太陽光唔係死白）。
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 1.1
	light.shadow_enabled = true
	_world.add_child(light)

	# VR-04：放置場成組收埋喺呢個 root 底下，狂熱期間 toggle
	# visible 就成組隱藏／還原，唔使逐個節點記低顯示狀態。
	_placement_root = Node3D.new()
	_placement_root.name = "PlacementField"
	_world.add_child(_placement_root)

	_foothill_root = Node3D.new()
	_foothill_root.name = "Foothill"
	_foothill_root.position = _site_to_world(c.site_foothill_pos)
	_placement_root.add_child(_foothill_root)
	_rebuild_foothill_stack()

	var belt_track := VisualFactory.make_flat_box(
		Vector3(0.18, 0.05, (c.belt_head_pos - c.smelter_pos).length()), VisualFactory.PALETTE["belt"]
	)
	belt_track.name = "BeltTrack"
	var belt_mid := (c.belt_head_pos + c.smelter_pos) * 0.5
	belt_track.position = _site_to_world(belt_mid)
	belt_track.look_at_from_position(belt_track.position, _site_to_world(c.smelter_pos), Vector3.UP)
	_placement_root.add_child(belt_track)

	# 熔爐：藍身 + 發光橙色爐口（VR-06 換皮，代替純色盒仔）。
	var smelter := Node3D.new()
	smelter.name = "Smelter"
	smelter.position = _site_to_world(c.smelter_pos, 0.25)
	var smelter_body := VisualFactory.make_metal_box(Vector3(0.5, 0.5, 0.5), VisualFactory.PALETTE["furnace_body"])
	smelter.add_child(smelter_body)
	var smelter_mouth := VisualFactory.make_metal_box(
		Vector3(0.3, 0.22, 0.05), VisualFactory.PALETTE["furnace_glow"], VisualFactory.PALETTE["furnace_glow"], 1.5
	)
	smelter_mouth.position = Vector3(0.0, -0.05, 0.26)
	smelter.add_child(smelter_mouth)
	_placement_root.add_child(smelter)

	# 倉：body + 斜頂，代替純色盒仔。
	var warehouse := Node3D.new()
	warehouse.name = "Warehouse"
	warehouse.position = _site_to_world(c.warehouse_pos, 0.22)
	var warehouse_body := VisualFactory.make_flat_box(Vector3(0.6, 0.45, 0.45), VisualFactory.PALETTE["warehouse_body"])
	warehouse.add_child(warehouse_body)
	var warehouse_roof := VisualFactory.make_flat_box(Vector3(0.66, 0.08, 0.5), VisualFactory.PALETTE["warehouse_roof"])
	warehouse_roof.position = Vector3(0.0, 0.265, 0.0)
	warehouse.add_child(warehouse_roof)
	_placement_root.add_child(warehouse)

	# 礦工／山腳碎料嘅本地座標係「相對山腳」嘅少少 jitter；root 本身要
	# 擺喺 site_foothill_pos，唔係就會全部跌喺世界原點（同底部 HUD
	# 個 ColorRect 重疊，tap 事件俾 GUI 食咗去唔到 physics picking——
	# Review 意見，見 ALTA-150）。
	_miners_root = Node3D.new()
	_miners_root.name = "MinersRoot"
	_miners_root.position = _site_to_world(c.site_foothill_pos)
	_placement_root.add_child(_miners_root)

	_pile_root = Node3D.new()
	_pile_root.name = "PileRoot"
	_pile_root.position = _site_to_world(c.site_foothill_pos)
	_placement_root.add_child(_pile_root)

	_belt_items_root = Node3D.new()
	_belt_items_root.name = "BeltItemsRoot"
	_placement_root.add_child(_belt_items_root)

## 廢料山（往上長）：山腳一個底座 + 每召喚一個礦工加一層方塊，
## 視覺上表達「開採緊、堆越嚟越高」。上限同召喚上限一致（12）。
func _rebuild_foothill_stack() -> void:
	for child in _foothill_root.get_children():
		child.queue_free()
	var base := VisualFactory.make_flat_box(Vector3(0.9, 0.3, 0.6), VisualFactory.PALETTE["cave"])
	base.position = Vector3(0.0, 0.0, 0.0)
	_foothill_root.add_child(base)
	var tiers: int = state.miner_count
	for i in range(tiers):
		var t: float = float(i) / float(maxi(c.miner_summon_cap, 1))
		var box := VisualFactory.make_flat_box(
			Vector3(0.75 - t * 0.35, FOOTHILL_TIER_HEIGHT, 0.5 - t * 0.2), VisualFactory.PALETTE["cave_light"]
		)
		box.position = Vector3(0.0, FOOTHILL_BASE_HEIGHT + float(i) * FOOTHILL_TIER_HEIGHT, 0.0)
		_foothill_root.add_child(box)


# ══════════════════════ 礦工 ══════════════════════

func _try_summon_miner() -> void:
	if not state.summon_miner():
		return
	# VR-06：機械人 glTF（CREDITS.md）origin 喺腳底（y=0），同舊盒仔置中
	# 唔同，企喺 y=0.1 貼地；盒仔 fallback 個樣會企得稍為浮啲，接受。
	var miner := VisualFactory.make_miner()
	miner.name = "Miner%d" % state.miner_count
	var jitter := Vector2(rng.randf_range(-0.3, 0.3), 0.0)
	miner.position = Vector3(jitter.x, 0.1, rng.randf_range(-0.2, 0.2))
	miner.rotation.y = rng.randf_range(-0.4, 0.4)
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
	var chunk := VisualFactory.make_ore_chunk(PILE_CHUNK_VISUAL_SIZE, _ore_color(ore_key))
	chunk.position = Vector3(rng.randf_range(-0.4, 0.4), 0.55, rng.randf_range(-0.3, 0.3))
	chunk.rotation.y = rng.randf_range(0.0, TAU)

	var area := Area3D.new()
	area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * PILE_CHUNK_TAP_HIT_SIZE
	col.shape = shape
	area.add_child(col)
	chunk.add_child(area)
	# 未 belted 先接 tap handler；一入帶（_spawn_belt_visual_item）嘅盒仔
	# 完全冇 Area3D，結構上就已經保證「已 belted 碎料不可 scoop」。
	area.input_event.connect(_on_pile_chunk_input.bind(chunk, area, ore_key))

	_pile_root.add_child(chunk)

func _on_pile_chunk_input(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int,
	chunk: Node3D, area: Area3D, ore_key: String
) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var gained := state.scoop_ore(ore_key)
	if gained <= 0.0:
		return
	area.input_ray_pickable = false # 撳中即停接輸入，播緊回饋果下唔會重複扣同一粒
	SfxPlayer.play("pile_mine")
	_hide_scoop_hint()
	_play_scoop_feedback(chunk)

## 用戶實機回饋（ALTA-150）：撳中冇任何回饋，唔知有冇撳中。撳中即放大
## 閃一閃先消失，等玩家見到「撳咗嘢」。
func _play_scoop_feedback(chunk: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(chunk, "scale", Vector3.ONE * 1.6, 0.08).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(chunk.queue_free)

func _hide_scoop_hint() -> void:
	if _scoop_hint_shown:
		return
	_scoop_hint_shown = true
	_scoop_hint_label.visible = false

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
	var item := VisualFactory.make_flat_box(Vector3(0.1, 0.1, 0.1), Color(0.8, 0.8, 0.7))
	item.position = _site_to_world(c.belt_head_pos, 0.1)
	_belt_items_root.add_child(item)

	var tw := create_tween()
	tw.tween_property(item, "position", _site_to_world(c.smelter_pos, 0.1), c.belt_visual_travel_secs)
	tw.tween_callback(func() -> void: SfxPlayer.play("furnace_feed", -8.0))
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

	var lock_row := HBoxContainer.new()
	top_vbox.add_child(lock_row)
	lock_row.add_child(VisualFactory.make_icon("res://assets/icons/locked.png", 18.0, Color(0.9, 0.75, 0.4)))
	_lock_label = Label.new()
	# issue 文案要求完整數字「鎖住 · 2,000,000」，唔用 _fmt_num() 嘅
	# K/M 縮寫（嗰個係俾底部窄 HUD 用）。
	_lock_label.text = "鎖住 · %s" % _fmt_int_commas(c.unlock_price("mid"))
	lock_row.add_child(_lock_label)

	_prestige_bar = ProgressBar.new()
	_prestige_bar.min_value = 0.0
	_prestige_bar.max_value = c.prestige_threshold(0)
	_prestige_bar.value = 0.0 # 威望重置邏輯見 VR-05，呢度淨係擺位
	top_vbox.add_child(_prestige_bar)

	var prestige_row := HBoxContainer.new()
	top_vbox.add_child(prestige_row)
	prestige_row.add_child(VisualFactory.make_icon("res://assets/icons/star.png", 18.0, Color(0.85, 0.65, 0.95)))
	_prestige_label = Label.new()
	_prestige_label.text = "威望 0 / %s" % _fmt_num(c.prestige_threshold(0))
	prestige_row.add_child(_prestige_label)

	# -- 開場提示：撳碎料鏟入爐——用戶實機回饋（ALTA-150），碎料太細
	# 又冇提示，唔知撳邊度。貼喺頂 HUD 底下，中層 3D 畫面最上面，第一次
	# 剷成功就收起（_hide_scoop_hint()），唔會長期擋畫面。 --
	_scoop_hint_label = Label.new()
	_scoop_hint_label.text = "撳碎料鏟入爐"
	_scoop_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoop_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	_scoop_hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_scoop_hint_label.add_theme_constant_override("outline_size", 4)
	_scoop_hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_scoop_hint_label.anchor_top = top_frac
	_scoop_hint_label.anchor_bottom = top_frac
	_scoop_hint_label.offset_top = 4.0
	hud.add_child(_scoop_hint_label)

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
	_cash_label = _add_resource_slot(resources_row, "res://assets/icons/coin.png", Color(1.0, 0.85, 0.35))
	_components_label = _add_resource_slot(resources_row, "res://assets/icons/gear.png", Color(0.75, 0.78, 0.85))
	_eco_label = _add_resource_slot(resources_row, "res://assets/icons/eco_leaf.png", Color(0.55, 0.85, 0.5))

	_summon_button = Button.new()
	_summon_button.text = "召喚礦工"
	_summon_button.pressed.connect(_try_summon_miner)
	bottom_vbox.add_child(_summon_button)

	# VR-04：免費觸發，冷卻／倒數文案喺 _refresh_hud() 更新。
	_frenzy_button = Button.new()
	_frenzy_button.pressed.connect(_try_start_frenzy)
	bottom_vbox.add_child(_frenzy_button)

	var upgrades_row := HBoxContainer.new()
	bottom_vbox.add_child(upgrades_row)

	_belt_upgrade_button = Button.new()
	_belt_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_upgrade_button(_belt_upgrade_button, "res://assets/icons/arrowRight.png")
	_belt_upgrade_button.pressed.connect(func() -> void:
		if state.upgrade_belt():
			EventLog.log_event("upgrade", {"track": "belt", "level": state.belt_level})
			SfxPlayer.play("upgrade")
	)
	upgrades_row.add_child(_belt_upgrade_button)

	_miner_upgrade_button = Button.new()
	_miner_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_upgrade_button(_miner_upgrade_button, "res://assets/icons/plus.png")
	_miner_upgrade_button.pressed.connect(func() -> void:
		if state.upgrade_miner_level():
			EventLog.log_event("upgrade", {"track": "miner", "level": state.miner_level})
			SfxPlayer.play("upgrade")
	)
	upgrades_row.add_child(_miner_upgrade_button)

	_refine_upgrade_button = Button.new()
	_refine_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_upgrade_button(_refine_upgrade_button, "res://assets/icons/wrench.png")
	_refine_upgrade_button.pressed.connect(func() -> void:
		if state.upgrade_refine():
			EventLog.log_event("upgrade", {"track": "refine", "level": state.refine_level})
			SfxPlayer.play("upgrade")
	)
	upgrades_row.add_child(_refine_upgrade_button)

## 資源列一格：icon + 數值 label，回傳 label 俾 _refresh_hud() 更新文字。
func _add_resource_slot(parent: HBoxContainer, icon_path: String, tint: Color) -> Label:
	var slot := HBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slot)
	slot.add_child(VisualFactory.make_icon(icon_path, 18.0, tint))
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(lbl)
	return lbl

## 升級按鈕統一加 icon（Kenney Game Icons，見 CREDITS.md），icon 大細
## 用 theme constant 夾住，唔會俾原生 50x50 PNG 谷爆粒按鈕。
func _style_upgrade_button(button: Button, icon_path: String) -> void:
	if ResourceLoader.exists(icon_path):
		button.icon = load(icon_path)
	button.add_theme_constant_override("icon_max_width", 22)

func _refresh_hud() -> void:
	_cash_label.text = "Cash %s" % _fmt_num(state.cash)
	_components_label.text = "Components %s" % _fmt_num(state.components)
	_eco_label.text = "Eco %s" % _fmt_num(state.eco)

	_summon_button.text = "召喚礦工 (%d/%d)" % [state.miner_count, c.miner_summon_cap]
	if state.can_summon_miner():
		var affordable := state.cash >= state.next_miner_cost()
		_summon_button.disabled = not affordable
		_set_afford_color(_summon_button, affordable)
	else:
		_summon_button.disabled = true
		_clear_afford_color(_summon_button) # 撞召喚上限，唔係等錢，維持預設灰色

	if state.can_upgrade_belt():
		var affordable := state.cash >= state.next_belt_cost()
		_belt_upgrade_button.text = "帶 Lv%d → 升級 %s" % [state.belt_level, _fmt_num(state.next_belt_cost())]
		_belt_upgrade_button.disabled = not affordable
		_set_afford_color(_belt_upgrade_button, affordable)
		# 威望重置（VR-05）會將帶等級打番去 1，換返箭嘴（唔會停留喺
		# 上鋪封頂嗰刻嘅剔號）。
		if ResourceLoader.exists("res://assets/icons/arrowRight.png"):
			_belt_upgrade_button.icon = load("res://assets/icons/arrowRight.png")
	else:
		_belt_upgrade_button.text = "帶 Lv%d（封頂）" % state.belt_level
		_belt_upgrade_button.disabled = true
		_clear_afford_color(_belt_upgrade_button) # 封頂，唔係等錢
		# 封頂之後箭嘴 icon 冇意思，換做剔號（同一 icon_max_width 樣式）。
		if ResourceLoader.exists("res://assets/icons/checkmark.png"):
			_belt_upgrade_button.icon = load("res://assets/icons/checkmark.png")

	var miner_lv_affordable := state.cash >= state.next_miner_level_cost()
	_miner_upgrade_button.text = "礦工 Lv%d → 升級 %s" % [state.miner_level, _fmt_num(state.next_miner_level_cost())]
	_miner_upgrade_button.disabled = not miner_lv_affordable
	_set_afford_color(_miner_upgrade_button, miner_lv_affordable)

	var refine_affordable := state.cash >= state.next_refine_level_cost()
	_refine_upgrade_button.text = "精煉 Lv%d → 升級 %s" % [state.refine_level, _fmt_num(state.next_refine_level_cost())]
	_refine_upgrade_button.disabled = not refine_affordable
	_set_afford_color(_refine_upgrade_button, refine_affordable)

	if frenzy.active:
		_frenzy_button.text = "狂熱中 %ds" % int(ceil(frenzy.time_remaining))
		_frenzy_button.disabled = true
	elif frenzy.can_start():
		_frenzy_button.text = "狂熱！（免費）"
		_frenzy_button.disabled = false
	else:
		_frenzy_button.text = "狂熱冷卻中 %ds" % int(ceil(frenzy.cooldown_remaining))
		_frenzy_button.disabled = true

## 用戶實機回饋（ALTA-150）：升級掣全部灰晒，撞唔到分清楚係「等緊
## 錢」定「壞咗」。夠錢就轉返正常／綠色，唔夠錢價錢轉紅色，等玩家知
## 道等緊儲夠錢，唔係壞咗。（撞上限／封頂嘅掣唔叫呢個，維持預設灰色。）
func _set_afford_color(btn: Button, affordable: bool) -> void:
	var color := Color(0.4, 0.9, 0.4) if affordable else Color(0.95, 0.35, 0.3)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_disabled_color", color)

func _clear_afford_color(btn: Button) -> void:
	btn.remove_theme_color_override("font_color")
	btn.remove_theme_color_override("font_disabled_color")

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

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
## 座標（VR-06b／ALTA-219 場地規格 v2 起，取代之前「成個場地住喺世界
## Z=0 直立面」嘅舊做法——嗰個做法連同「改地面平面」issue ALTA-198
## 當時 cancelled 嘅決定已經唔適用，見 git blame）：docx 場地座標
## (x, y) 係地面平面，唔企起身嘅嘢淨用呢兩個分量；企起身嘅結構（門柱、
## 礦堆粒等）額外加一個「高度」分量先落第三維。`SITE_BASIS`（見下面）
## 將呢個地面平面攤平做世界地面，site z（高度）先接得落 Godot 預設嘅
## 「上」（世界 +y）——重力／碰撞直接用得，唔使再夾細 debris_gravity_scale
## 補償。相機轉用透視、由上方斜望落（IZM 峽谷構圖）。
##
## VR-06b：相機由正交改透視（issue 視覺參考 ALTA-153 最後一則留言，IZM
## 截圖構圖：高角度望落一條由畫面頂延伸到底嘅峽谷，前景大後景細）。
## FOV／pitch／yaw 唔再讀 constants.gd 嘅 screen_camera_pitch_deg／
## yaw_deg（嗰兩個係舊正交相機嘅角度，issue 明確話「唔郁 constants.gd」，
## 留喺嗰度做歷史記錄／日後遠端設定接手），改用呢個 script 自己嘅
## CAMERA_FOV_DEG／CAMERA_PITCH_DEG／CAMERA_YAW_DEG（見上面，同
## FOOTHILL_* 一樣係美術取景常數，唔係遊戲數值）。位置由
## _compute_camera_frame() 數值解出嚟（透視底下垂直取景比例隨深度變，
## 冇封閉公式，改用二分法，見該函式註解），保證山腳～山頂、帶、爐、
## 倉、車場兩牆全部喺 3:4 直版入面啱晒 HUD 12/22 版面嘅中層帶。

## 山腳堆疊嘅盒仔尺寸——純美術造型，唔係遊戲數值，所以留喺呢度做
## script const（唔屬於 constants.gd 嘅「數值」，但相機取景要用嚟計算
## 山頂最高會去到邊，所以抽出嚟同 _rebuild_foothill_stack() 共用，
## 避免兩處各自 hardcode 一份出現唔一致）。
const FOOTHILL_BASE_HEIGHT := 0.22
const FOOTHILL_TIER_HEIGHT := 0.1
## VR-06b 場地規格 v2：廢料山（12 層梯田）嘅平面尺寸——闊約 2.6（車闊≈0.5，
## 即 ~5 車闊）、由山腳向後（+y）伸 1.7；每層向後縮、向上疊。
const MOUNTAIN_WIDTH := 2.9
const MOUNTAIN_DEPTH := 1.6
## 場地（site）座標 → 世界：site 平面攤平做地面（site y → 世界 -z，site z → 世界 +y）。
## 成個場地掛喺 _site_root（rotation.x = -90°）之下，物件仍然用 site 座標寫。
const SITE_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

## VR-06b：鏡頭改透視（issue 視覺參考 ALTA-153 最後一則留言，IZM 截圖：
## 高角度望落一條由頂延伸到底嘅峽谷，前景大後景細）。呢啲純粹係鏡頭
## 取景嘅美術參數，唔屬於 constants.gd 嘅遊戲數值（issue 明確話「唔郁
## constants.gd」），所以同 FOOTHILL_* 一樣擺呢度做 script const。
## constants.gd 嘅 screen_camera_pitch_deg／yaw_deg 係之前正交相機嗰set
## 角度，維持唔變（留返俾歷史記錄／日後遠端設定），新透視相機用返呢
## 幾個獨立常數。
##
## 場地規格 v2（ALTA-219，2026-09-13）：pitch 收窄去 60–65°、FOV 定 40°、
## yaw 歸零（「唔轉 yaw」，取代之前 ALTA-214 嗰 8° 輕微 yaw）——取代舊版
## 55–60°／40–45°／8° 呢組數，見 test_main_scene.gd
## test_camera_is_tilted_not_front_on() 跟住改咗嘅門檻。
const CAMERA_FOV_DEG := 40.0    # 場地規格 v2：40°
const CAMERA_PITCH_DEG := -60.0 # 場地規格 v2：60–65°（負數＝低頭望落場地，跟返正交相機嗰個正負號慣例）
const CAMERA_YAW_DEG := 0.0     # 場地規格 v2：唔轉 yaw

## 取景安全邊界（screen fraction／世界單位），畀盒仔／模型本身嘅大細
## 留返少少呼吸位，純美術決定，唔係精算出嚟嘅公差。
const CAMERA_TOP_MARGIN := 0.02
const CAMERA_BOTTOM_MARGIN := 0.03
const CAMERA_HORIZONTAL_MARGIN_WORLD := 0.2

## VR-11：鏡頭可拖（「鏡頭跟車／可拖」，field-zones-v9.png）——場地由下
## （區域 1）向上擴張，預設取景（上面 _camera_reference_points() 嘅框架）
## 淨係框住區域 1，區域 2 嘅解鎖板企喺呢個框以外，要拖先睇到。拖動淨係
## 沿住相機自己 local up 軸（_compute_camera_frame() 嗰個 basis.y）平移
## 相機位置，方向／FOV／_camera_reference_points() 為本嘅預設取景計算
## 完全唔變——_camera_pan 預設 0，唔拖就同之前一模一樣，唔會累到現有
## 相機取景回歸測試（test_main_scene.gd 嗰批 _in_camera_mid_band()）。
const CAMERA_DRAG_SENSITIVITY := 0.005 # 美術取景常數（唔係遊戲數值）：每螢幕像素拖動對應幾多世界單位
const CAMERA_MAX_PAN := 2.6            # 美術取景常數：最多拖幾遠先見到區域 2 解鎖板

## VR-11：區域 2 入口解鎖板擺位——喺現有峽谷入面、後壁附近、山腳左方
## （跟 field-zones-v9.png「左上」示意），冇改任何區域 1 既有幾何／
## 判分。呢個位置純粹係框架驗證用嘅第一個示範，區域 2 實際場地
## （VR-13，backlog）起好之後，呢個板同呢兩個常數應該搬去嗰個區域自己
## 嘅位置，唔再掛喺區域 1 場地度。
const REGION2_PANEL_SITE_POS := Vector2(-1.3, 2.6)
const REGION2_PANEL_HEIGHT := 0.3

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

# -- VR-05b：存檔／離線結算／威望——GameState 冇呢幾個欄位（唔屬於放置場
# 核心數值，見 data/save_manager.gd／data/prestige.gd 嘅欄位定義），由呢個
# script 自己揸，經 _build_save_state()／_apply_loaded_state() 同存檔互轉。--
var _save_timer: Timer
var _lifetime_cash: float = 0.0
var _prestige_count: int = 0
var _last_save_unix: float = 0.0
var _pending_offline_result: Dictionary = {} # 等緊玩家撳「收下」嘅 OfflineSettlement.settle() 結果

# -- 3D 節點 --
var _world: Node3D
var _site_root: Node3D # VR-06b：場地根（攤平做地面）
# ALTA-153 round2：放置場一直 visible（唔再狂熱期間隱藏，見
# _try_start_frenzy()／_on_frenzy_ended()），保留呢個 root 淨係為咗
# 分組管理（山腳／帶／爐／倉／礦工／碎料一齊掛喺度）。
var _placement_root: Node3D
var _foothill_root: Node3D
var _miners_root: Node3D
var _pile_root: Node3D
var _belt_items_root: Node3D
var _belt_rollers: Array[MeshInstance3D] = [] # ALTA-153 round2：分段滾軸，_process() 度持續轉
var _frenzy_view: FrenzyYardView

# -- VR-11：鏡頭可拖 --
var _camera: Camera3D
var _camera_base_position: Vector3 # _compute_camera_frame() 算出嚟嗰個預設位置（_camera_pan=0 嗰刻）
var _camera_pan: float = 0.0       # 沿住相機 local up 軸嘅偏移量，夾喺 [0, CAMERA_MAX_PAN]

# -- VR-11：場地擴張框架 --
var _unlocked_regions: Array[String] = ["region1"] # 區域 1 恆常已解鎖
var _region2_panel: UnlockPanel

# -- HUD 節點 --
var _lock_label: Label
var _prestige_bar: ProgressBar
var _prestige_label: Label
var _cash_label: Label
var _components_label: Label
var _eco_label: Label
var _miner_count_label: Label # VR-06b：頂列「礦工 n/12」pill，純顯示，唔可以撳（撳嘅掣仍然係底部 _summon_button）
var _summon_button: Button
var _belt_upgrade_button: Button
var _miner_upgrade_button: Button
var _refine_upgrade_button: Button
# 效能修正（ALTA-219 fps 調查）：見 _refresh_hud() 註解——帶升級掣嘅箭嘴／
# 剔號 icon 預先喺 _build_hud() load() 一次快取喺度，_refresh_hud() 每幀
# 淨係讀呢兩個 reference，唔再每幀 touch ResourceLoader。
var _belt_icon_arrow: Texture2D
var _belt_icon_check: Texture2D
var _frenzy_button: Button
var _scoop_hint_label: Label # 開場提示「撳碎料鏟入爐」，第一次剷完就收起（ALTA-150 實機回饋）
var _scoop_hint_shown: bool = false

# -- VR-05b：離線結算彈窗（浣熊經理發糧）／威望確認彈窗 --
var _offline_panel: Control
var _offline_message_label: Label
var _offline_yield_label: Label
var _offline_claim_button: Button
var _offline_double_button: Button # 「×2」：先顯示但灰，rewarded 接駁留 VR-07
var _prestige_button: Button # 「拆廠搬礦」：達到威望門檻先顯示
var _prestige_confirm_panel: Control
var _prestige_confirm_label: Label


func _ready() -> void:
	c = GameConstants.new()
	# VR-08 Review 修正：一定要喺呢一刻（構造任何讀 `c` 嘅物件之前）同步
	# 套用返上次成功 fetch 存低嘅 cache——GameState._init()／FrenzyState._init()
	# 會即刻讀 c.starting_cash／c.frenzy_first_cooldown_secs，遲少少（例如
	# 背景 fetch 完成先 set()）呢兩個欄位就永遠冚唔到，唔理重開幾多次都
	# 冇用。見 systems/remote_constants.gd 嘅 CACHE_PATH 註解。
	_apply_overrides(RemoteConstants.read_cache())
	state = GameState.new(c)
	frenzy = FrenzyState.new(c)
	rng.randomize()

	get_viewport().physics_object_picking = true

	# VR-05b：存檔接駁——冇存檔（save_exists=false）就維持 GameState._init()
	# 啱啱設好嘅新玩家開場值（唔可以俾 SaveManager.load_state() 喺冇檔案
	# 個案回傳嘅 default_state()「cash=0」冚咗 c.starting_cash）；有存檔就
	# 喺呢度（構造 _foothill／HUD 之前）套用落 state／_lifetime_cash／
	# _prestige_count，等 _build_world() 起梯田、_build_hud() 起 HUD 嗰陣
	# 已經睇到啱嘅數值。離線結算面板要等 _build_hud() 起完先彈（見底）。
	var save_exists := FileAccess.file_exists(SaveManager.SAVE_PATH)
	var loaded_state: Dictionary = {}
	var offline_raw_rate := 0.0
	if save_exists:
		# VR-11：經 Save autoload 讀（唔再直接叫 SaveManager.load_state()）
		# ——Save.load_and_apply_wallet() 讀完同一份 flat dict 之餘，順手
		# 將 cash／components／eco 套落 Wallet（共用錢包 autoload，見
		# autoload/wallet.gd），等 _apply_loaded_state() 下面可以直接由
		# Wallet 攞返呢三個欄位，單一 source of truth。
		loaded_state = Save.load_and_apply_wallet()
		_apply_loaded_state(loaded_state)
		# VR-05b review fix：呢一刻 state.income_multiplier 仲係預設 1.0
		# （下一行先 set），current_income_rate() 攞到嘅係未計威望嘅 raw
		# rate。一定要喺套用威望倍率之前攞——OfflineSettlement.settle()
		# 自己會再用 loaded_state 嘅 prestige_count 乘多一次
		# Prestige.income_multiplier()，如果呢度已經包埋倍率就會計多次
		# （見 _run_offline_settlement()）。
		offline_raw_rate = state.current_income_rate()
		state.income_multiplier = Prestige.income_multiplier(c, _prestige_count)
	# VR-11：冇存檔（新玩家）嗰陣 state.cash 係 GameState._init() 剛設低
	# 嘅 c.starting_cash，唔係 0——Wallet 都要跟住同步，唔留喺預設 0。
	_sync_wallet_from_state()

	_build_world()
	_spawn_loaded_miners() # VR-05b review fix：讀檔補返已召喚礦工嘅 node（新玩家 miner_count=0，冧一世都唔會行）
	_build_hud()

	_frenzy_view = FrenzyYardView.new(c, state, frenzy)
	_frenzy_view.name = "FrenzyYard"
	_site_root.add_child(_frenzy_view)

	_pile_spawn_timer = Timer.new()
	_pile_spawn_timer.wait_time = c.pile_debris_spawn_interval_secs
	_pile_spawn_timer.autostart = true
	_pile_spawn_timer.timeout.connect(_on_pile_spawn_timeout)
	add_child(_pile_spawn_timer)

	# VR-05b：每 30 秒自動存檔兜底——升級／召喚／狂熱完場／退背景／關閉
	# 視窗呢幾個時間點各自主動存（見對應函式／_notification()），呢個
	# timer 淨係保證長時間掛住冇觸發任何一個上述事件都唔會唔存檔。
	_save_timer = Timer.new()
	_save_timer.wait_time = 30.0
	_save_timer.autostart = true
	_save_timer.timeout.connect(_save_game)
	add_child(_save_timer)

	_refresh_hud()

	# VR-08：本機事件 log + 遠端 constants 覆寫，見 systems/event_log.gd／
	# systems/remote_constants_loader.gd。呢兩樣都喺世界／HUD 起晒之後
	# 先做，唔會拖慢開場（背景 fetch，攞唔到就繼續用本機預設）。
	EventLog.log_event("session_start")
	_start_remote_constants_fetch()

	# VR-05b：離線結算要等 HUD（連埋離線面板本身）起晒先可以彈，所以擺
	# _ready() 最尾。用返上面讀檔嗰刻嘅 loaded_state（未套用之前嘅原始
	# 存檔，帶住上次嘅 last_save_unix）同埋套用威望倍率之前攞低嘅
	# offline_raw_rate，OfflineSettlement.settle() 自己計「經過咗幾耐」
	# 同套威望倍率。
	if save_exists:
		_run_offline_settlement(loaded_state, offline_raw_rate)


## VR-05b：退到背景／關閉視窗一定要存檔（唔係殺 App 嗰一刻嘅進度會冚
## 失）。NOTIFICATION_APPLICATION_PAUSED＝手機切去背景／熄屏；
## NOTIFICATION_WM_CLOSE_REQUEST＝Windows host 撳關閉掣（SceneTree 通知
## 晒所有 node 之後先自動 quit，呢度啱啱嚟得切存檔）。
func _notification(what: int) -> void:
	if state == null:
		return # _ready() 未行完（例如場景仲喺構造中）就唔會有嘢好存
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


## 開機背景攞遠端 constants 覆寫；成功就直接 set() 落現有嘅 `c`（同一個
## Resource 個體，state／frenzy／_frenzy_view 全部揸緊呢個 reference，
## 唔使逐個傳過）,失敗就乜都唔做（維持本機預設／舊 cache）。呢個 fetch
## 本身淨係處理「今次呢個 session 之後仲讀得到 c」嘅欄位——已經喺 _ready()
## 開頭讀走咗嘅嗰幾個（starting_cash 等）要等下次重開先食到新值，見
## _on_remote_constants_loaded() 寫 cache 嗰段。
func _start_remote_constants_fetch() -> void:
	_remote_constants_loader = RemoteConstantsLoader.new()
	add_child(_remote_constants_loader)
	_remote_constants_loader.finished.connect(_on_remote_constants_loaded)
	_remote_constants_loader.start()

func _on_remote_constants_loaded(overrides: Dictionary, source: String) -> void:
	# "local_default:..." = 呢次 fetch 完全失敗（冇部署／逾時／連唔到／壞
	# JSON），伺服器嘅實際狀態未知，唔可以當「而家冇覆寫」寫爛（清走）舊
	# cache——維持上次成功攞到嗰份，離線都用得到。
	if source.begins_with("local_default"):
		return
	# 呢度先係真正接觸到伺服器嘅回應（"remote_empty" 或
	# "remote_applied:..."）：可能係空 Dictionary（管理員刻意清咗全部
	# 覆寫），都要照寫落 cache——下次開機先會跟返伺服器而家嘅實際狀態
	# 用返純本機預設，唔會一直卡住舊值。
	RemoteConstants.write_cache(overrides)
	if overrides.is_empty():
		return
	_apply_overrides(overrides)
	_refresh_hud() # 有覆寫升級價／狂熱數值等 → HUD 顯示緊嘅價錢即刻反映新值

func _apply_overrides(overrides: Dictionary) -> void:
	for key: String in overrides:
		c.set(key, overrides[key])


# ══════════════════════ VR-05b：存檔／離線結算／威望重置 ══════════════════════

## 將存檔讀到嘅 state dict 套用落 GameState（`state`）同呢個 script 自己
## 揸嘅 _lifetime_cash／_prestige_count（GameState 冇呢兩個欄位——威望
## 門檻／存檔要用嘅「終身賺到」同「重置次數」唔屬於放置場核心數值，
## 見 data/prestige.gd／data/save_manager.gd 嘅欄位定義）。用 get() 夾
## 埋預設值，就算存檔缺咗某個欄位都唔會拋錯。
func _apply_loaded_state(loaded: Dictionary) -> void:
	# VR-11：cash／components／eco 而家由 Wallet（共用錢包 autoload）攞——
	# 呼叫方（_ready()）已經喺呢個之前 call 咗 Save.load_and_apply_wallet()，
	# 呢一刻 Wallet 已經套用咗同一份 `loaded` 入面嘅呢三個欄位，數值一定
	# 一致。
	state.cash = Wallet.cash
	state.components = Wallet.components
	state.eco = Wallet.eco
	state.miner_count = int(loaded.get("miners", 0))
	state.miner_level = int(loaded.get("miner_level", 0))
	state.belt_level = int(loaded.get("belt_level", 1))
	state.refine_level = int(loaded.get("refine_level", 0))
	# VR-11：Array 型別要逐個元素轉 String（JSON 讀返嚟嘅係 Array[Variant]），
	# 缺咗欄位（舊 v1 存檔，理論上已經俾 SaveManager._migrate() 補齊，呢度
	# 淨係額外防守）當只有 region1。
	var loaded_regions: Array = loaded.get("unlocked_regions", ["region1"])
	_unlocked_regions = []
	for region_id: Variant in loaded_regions:
		_unlocked_regions.append(String(region_id))
	if not "region1" in _unlocked_regions:
		_unlocked_regions.append("region1")
	_lifetime_cash = float(loaded.get("lifetime_cash", 0.0))
	_prestige_count = int(loaded.get("prestige_count", 0))
	_last_save_unix = float(loaded.get("last_save_unix", Time.get_unix_time_from_system()))

## 反過嚟：由 GameState／_lifetime_cash／_prestige_count 砌返一份
## SaveManager 認得嘅 state dict（欄位名／形狀睇 SaveManager.default_state()）。
## save_state()／OfflineSettlement.settle()／Prestige.reset() 三個入口
## 全部食呢個形狀，砌埋一份共用，唔使三處各自組一次。
func _build_save_state() -> Dictionary:
	return {
		"version": SaveManager.CURRENT_VERSION,
		"last_save_unix": Time.get_unix_time_from_system(),
		"cash": state.cash,
		"components": state.components,
		"eco": state.eco,
		"lifetime_cash": _lifetime_cash,
		"prestige_count": _prestige_count,
		"miners": state.miner_count,
		"miner_level": state.miner_level,
		"belt_level": state.belt_level,
		"refine_level": state.refine_level,
		"unlocked_regions": _unlocked_regions,
	}

## VR-11：將當刻嘅即時 cash／components／eco 推返落 Wallet（共用錢包
## autoload）——存檔之前一定要 call 一次，保證 Wallet 記憶體嗰份同即將
## 存落 disk 嗰份一致。
func _sync_wallet_from_state() -> void:
	Wallet.cash = state.cash
	Wallet.components = state.components
	Wallet.eco = state.eco

func _save_game() -> void:
	_sync_wallet_from_state()
	Save.save_raw(_build_save_state())

## 開機讀到存檔（`loaded` 係讀檔嗰刻、套用之前嘅原始 dict，帶住上次嘅
## last_save_unix）就行 OfflineSettlement.settle()：用復原返嗰刻嘅礦工／
## 升級數值計嘅「離線嗰刻嘅放置收入」近似值——呢個 script 冇另外記低
## 「熄機一刻」嘅收入率，符合 VR-05 原本設計嘅呼叫方式（settle() 淨係
## 唔管「呢個 rate 點嚟」）。`raw_rate` 一定要係未計威望倍率嗰個（`_ready()`
## 讀檔嗰刻、套用 state.income_multiplier 之前攞低），因為 settle() 自己
## 會再用 `loaded` 嘅 prestige_count 乘一次 Prestige.income_multiplier()
## ——傳個已經計咗威望嘅 rate 落嚟會令威望倍率計多次。結果暫存喺
## _pending_offline_result，等玩家喺面板撳「收下」先真正入帳（見
## _on_offline_claim_pressed()）。
func _run_offline_settlement(loaded: Dictionary, raw_rate: float) -> void:
	var now_unix := Time.get_unix_time_from_system()
	var result := OfflineSettlement.settle(c, loaded, now_unix, raw_rate)
	_pending_offline_result = result
	_show_offline_report(result)

func _show_offline_report(result: Dictionary) -> void:
	_offline_message_label.text = OfflineReport.raccoon_message(
		result["cash_yield"], result["elapsed_secs"], c.offline_cap_secs
	)
	_offline_yield_label.text = "+%s" % _fmt_num(result["cash_yield"])
	_offline_panel.visible = true

## 撳「收下」：真正將 settle() 算好嘅 cash_yield 入帳，補 EventLog
## 「offline_claim」事件（data/offline_settlement.gd 留低嘅呼叫點註解），
## 即刻多存一次檔（等離線收成都受「殺 App 資源不變」保護，唔使等落一個
## 30 秒 timer 先落實）。
##
## Review 意見：唔可以直接 `state.cash = new_state["cash"]` 覆寫——面板
## 開住嗰陣 `_process()` 照樣 tick 緊，state.cash 可能已經比 settle()
## 嗰刻嘅快照多咗少少（玩家繼續放置收入），覆寫會冚走呢部分。改用
## `+= cash_yield`（只加離線嗰份），唔理面板開住幾耐都唔會流失緊行緊嘅
## 實時收入。
func _on_offline_claim_pressed() -> void:
	if not _pending_offline_result.is_empty():
		var cash_yield: float = _pending_offline_result["cash_yield"]
		state.cash += cash_yield
		_lifetime_cash += cash_yield
		_last_save_unix = float(_pending_offline_result["state"]["last_save_unix"])
		EventLog.log_event("offline_claim", {
			"elapsed_secs": _pending_offline_result["elapsed_secs"],
			"cash_yield": cash_yield,
		})
		_pending_offline_result = {}
	_offline_panel.visible = false
	_save_game()
	_refresh_hud()

## 「拆廠搬礦」確認面板撳「確認重置」：Prestige.reset() 已經包晒「清乜
## 留乜」嘅邏輯（呢個 script 唔重覆去計），呢度淨係將結果搬返落 GameState
## 同視覺（礦工 node／梯田要重起，先反映返「清零」）。
func _do_prestige_reset() -> void:
	var new_state := Prestige.reset(_build_save_state())
	state.cash = float(new_state["cash"])
	state.components = float(new_state["components"])
	state.eco = float(new_state.get("eco", 0.0))
	state.miner_count = int(new_state["miners"])
	state.miner_level = int(new_state["miner_level"])
	state.belt_level = int(new_state["belt_level"])
	state.refine_level = int(new_state["refine_level"])
	state.pile_debris.clear()
	_lifetime_cash = float(new_state["lifetime_cash"])
	_prestige_count = int(new_state["prestige_count"])
	# VR-05b review fix：即時收入（tick()／current_income_rate()）要即刻
	# 食返新嘅威望倍率，唔淨係 HUD 門檻／確認面板嘅文字講吓。
	state.income_multiplier = Prestige.income_multiplier(c, _prestige_count)

	for child in _miners_root.get_children():
		child.queue_free()
	_rebuild_foothill_stack()

	EventLog.log_event("prestige", {"prestige_count": _prestige_count})
	_prestige_confirm_panel.visible = false
	_save_game()
	_refresh_hud()

func _show_prestige_confirm() -> void:
	_prestige_confirm_label.text = (
		"拆廠搬礦：清空 Cash／Components／礦工同三條升級線，保留終身 Cash 同威望重置次數。\n重置次數 %d → %d，永久收入倍率 ×%.1f → ×%.1f。"
		% [
			_prestige_count, _prestige_count + 1,
			Prestige.income_multiplier(c, _prestige_count), Prestige.income_multiplier(c, _prestige_count + 1),
		]
	)
	_prestige_confirm_panel.visible = true


func _process(delta: float) -> void:
	var result: Dictionary = state.tick(delta)
	_lifetime_cash += float(result["cash_gain"]) # VR-05b：終身 Cash 唔隨花費／威望重置清零，威望門檻用
	_belt_visual_accum += float(result["fed"])
	while _belt_visual_accum >= 1.0:
		_belt_visual_accum -= 1.0
		_spawn_belt_visual_item()

	# ALTA-153 round2 第 6 點：帶用分段滾軸 mesh，持續自轉先有「流動視覺」
	# ——同 FrenzyYardView._roller_visual 嘅刺滾筒一樣手法（rotate_x() 喺
	# 已經擺好嘅局部 X 軸度轉），純造型，唔影響帶產能／判分。
	for roller in _belt_rollers:
		roller.rotate_x(delta * 6.0)

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
	# 用戶實機回饋（ALTA-153 round2 第 1 點）：放置場＋車場要「上下分屏，
	# 兩者常駐」，唔可以再切場景——_placement_root 同 _frenzy_view 依家
	# 一直都 visible（見 _build_world()／FrenzyYardView._ready()），呢度
	# 淨係令車場「活起來」（車郁得、生碎料、_process() 開始行），山腳
	# 嘅碎料 tap 全程都揀得到，唔使再開關 physics_object_picking。
	_frenzy_view.start()

func _on_frenzy_ended() -> void:
	EventLog.log_event("frenzy_end", {"eco_bonus": frenzy.eco_bonus_earned})
	state.eco += frenzy.eco_bonus_earned
	# VR-05b review fix：狂熱過爐嘅 Cash 由 FrenzyYardView._score_and_free()
	# 直接加落 state.cash（唔經 GameState.tick()／scoop_ore()），冇呢句嘅話
	# 呢部分永遠唔會計入 _lifetime_cash，威望進度條會少計成截（狂熱係
	# 放置收入 ×5 ×120s，唔係小數目）。
	_lifetime_cash += frenzy.cash_earned
	_frenzy_view.stop()
	_save_game() # VR-05b：狂熱完場即存檔


# ══════════════════════ 建場景（灰模） ══════════════════════

func _site_to_world(v: Vector2, z: float = 0.0) -> Vector3:
	return Vector3(v.x, v.y, z)

## site 座標 → 世界座標（畀相機取景／測試用；場景物件本身用 _site_to_world 局部座標）。
func _site_to_global(v: Vector2, z: float = 0.0) -> Vector3:
	return SITE_BASIS * Vector3(v.x, v.y, z)

## VR-06b：鏡頭改透視之後由邊幾個地標決定取景——山腳／山頂（同舊版
## 一樣）、帶頭／爐／倉，加埋車場兩幅牆（FrenzyYardView._build_walls()
## 嘅位置，同一份場地座標）。狂熱車場同放置場共用呢一個相機（唔另起
## 爐灶），舊版正交相機淨計放置場 5 個點就啱使，係因為嗰個取景範圍
## 啱啱好連車場都框埋；依家帶車場兩牆落嚟一齊算，係因為新透視
## 相機嘅橫向視野比正交窄（KEEP_HEIGHT 之下，3:4 直版嘅橫向 FOV 細過
## 縱向），唔可以再靠撞彩，要老老實實將車場橫向範圍都計埋先保證
## 「車場兩牆全部喺中層帶」（issue 驗收）。
func _camera_reference_points() -> Array[Vector3]:
	var mountain_top_z: float = FOOTHILL_BASE_HEIGHT + float(c.miner_summon_cap) * FOOTHILL_TIER_HEIGHT
	var mountain_back_y: float = c.site_foothill_pos.y + MOUNTAIN_DEPTH
	var half_w: float = MOUNTAIN_WIDTH * 0.5
	return [
		_site_to_global(Vector2(c.site_foothill_pos.x - half_w, c.site_foothill_pos.y)),
		_site_to_global(Vector2(c.site_foothill_pos.x + half_w, c.site_foothill_pos.y)),
		_site_to_global(Vector2(c.site_foothill_pos.x, mountain_back_y), mountain_top_z),
		_site_to_global(Vector2(c.site_foothill_pos.x - half_w, mountain_back_y), mountain_top_z),
		_site_to_global(Vector2(c.site_foothill_pos.x + half_w, mountain_back_y), mountain_top_z),
		_site_to_global(c.belt_head_pos),
		_site_to_global(c.smelter_pos, 0.5),
		_site_to_global(c.warehouse_pos, 0.45),
		_site_to_global(Vector2(c.warehouse_pos.x, c.warehouse_pos.y - 0.35)),
		_site_to_global(Vector2(c.yard_x_range.x - 0.1, c.yard_min_y)),
		_site_to_global(Vector2(c.yard_x_range.y + 0.1, c.yard_min_y)),
		_site_to_global(Vector2(c.yard_x_range.x - 0.1, c.car_park_max_y)),
		_site_to_global(Vector2(c.yard_x_range.y + 0.1, c.car_park_max_y)),
		_site_to_global(Vector2(c.yard_x_range.y + 0.7, c.gate_y)),
	]

func _solve_camera_distance_for_vertical_fit(
	locals: Array[Vector3], max_lz: float, k_v: float, top_frac: float, bottom_frac: float
) -> float:
	var lo: float = max_lz + 0.5
	var hi: float = max_lz + 60.0
	for _i in range(48):
		var mid: float = (lo + hi) * 0.5
		var lcy: float = _solve_camera_height_for_bottom_fit(locals, mid, k_v, bottom_frac)
		var min_frac: float = INF
		for l: Vector3 in locals:
			var depth: float = mid - l.z
			var frac: float = 0.5 - 0.5 * (l.y - lcy) / (depth * k_v)
			min_frac = minf(min_frac, frac)
		if min_frac > top_frac:
			hi = mid # 頂點留白太多，仲貼唔切 top_frac，鏡頭要再貼近（縮細 local_cz）
		else:
			lo = mid # 頂點已經頂到（或者穿咗）top_frac，鏡頭要再退後
	return hi

## 喺畀定嘅相機距離（local_cz）之下，二分法搵鏡頭沿住 up 軸嘅偏移
## （local_cy），令「畫面最底嗰個地標」啱好貼近 bottom_frac。每個地標
## 嘅螢幕 Y 比例隨 local_cy 單調遞增（鏡頭企得愈高，啲嘢喺畫面度愈跌
## 愈低），所以「畫面最底嗰個」都係單調遞增，可以直接二分。
func _solve_camera_height_for_bottom_fit(
	locals: Array[Vector3], local_cz: float, k_v: float, bottom_frac: float
) -> float:
	var lo: float = -100.0
	var hi: float = 100.0
	for _i in range(48):
		var mid: float = (lo + hi) * 0.5
		var max_frac: float = -INF
		for l: Vector3 in locals:
			var depth: float = local_cz - l.z
			var frac: float = 0.5 - 0.5 * (l.y - mid) / (depth * k_v)
			max_frac = maxf(max_frac, frac)
		if max_frac > bottom_frac:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5

## 場地規格 v2（ALTA-219）根源修正：橫向要夾實車場兩牆（3.6 世界單位
## 闊）喺呢個裝置嘅窄直版 aspect（S8+ ≈1080:2220）之下，需要嘅相機距離
## 大過純垂直取景（山頂↔倉）所需——即係 local_cz_horizontal >
## local_cz_vertical。呢種情況底下，如果淨用 _solve_camera_height_for_bottom_fit()
## 揸實「底」貼 bottom_frac，「頂」（山頂）會因為鏡頭比垂直取景所需更
## 遠而縮埋落畫面中間，同 top_frac 之間空返一大截——實機（S8+）截圖
## 見到嘅「頂 30~40% 純黑」根源就係呢度（唔係地面／岩壁幾何漏咗，而係
## 相機本身已經預留咗嗰截留白）。呢個函式將「多出嚟嘅留白」平均分落
## 頂／底兩邊。試過偏向山頂嘅固定 bias（0.35）——S8+ 實機（1080:2220，
## 好窄嘅直版）睇落更貼近 top_frac，但呢個 bias 係跟實機 aspect 校出嚟，
## headless 測試用緊嘅預設 viewport（720:960，闊過實機好多）之下橫向
## 未必仲係 binding constraint，冇多餘留白可分之餘再屈個 0.35 bias 會
## 將山頂谷穿落 top_frac 之上（test_mountain_top_at_full_miner_cap_still_in_mid_band
## 就係咁樣爆）。改返用一半一半（0.5）——冇額外留白可分嗰陣（垂直本身
## 已經係 binding constraint）呢個結果同舊版 _solve_camera_height_for_bottom_fit()
## 一致；有額外留白嗰陣（橫向變成 binding constraint，見上面大段註解）
## 就平均分落頂／底，唔會因為裝置 aspect 唔同而爆界，跨 aspect 都穩陣。
func _solve_camera_height_centered(
	locals: Array[Vector3], local_cz: float, k_v: float, top_frac: float, bottom_frac: float
) -> float:
	var lo: float = -100.0
	var hi: float = 100.0
	var target_mid: float = (top_frac + bottom_frac) * 0.5
	for _i in range(48):
		var mid: float = (lo + hi) * 0.5
		var min_frac: float = INF
		var max_frac: float = -INF
		for l: Vector3 in locals:
			var depth: float = local_cz - l.z
			var frac: float = 0.5 - 0.5 * (l.y - mid) / (depth * k_v)
			min_frac = minf(min_frac, frac)
			max_frac = maxf(max_frac, frac)
		var span_mid: float = (min_frac + max_frac) * 0.5
		if span_mid > target_mid:
			hi = mid # 成組地標中心跌得太低（螢幕 Y 比例太大），鏡頭要企高啲（縮細 lcy）
		else:
			lo = mid
	return (lo + hi) * 0.5

## 由場地座標（加車場兩牆）反推透視相機嘅位置，令關鍵地標嘅螢幕 Y 比例
## 落喺 hud_top~1-hud_bottom（中層帶）之間，橫向亦唔會撞出畫面兩側
## （KEEP_HEIGHT 之下橫向 FOV 隨 3:4 直版縮窄，見下面橫向部分）。
##
## 做法：先將地標轉去相機自己嘅本地座標系（basis 轉置＝world→local，
## 因為 basis 係正交矩陣，同正交相機舊版一樣嘅技巧），分開解橫向／垂直
## 兩條：橫向每個地標喺自己深度要求嘅最少相機距離可以直接由
## tan(半橫向 FOV) 反推（見 needed 嗰行）；垂直冇封閉解，用
## _solve_camera_distance_for_vertical_fit() 數值解。最後鏡頭距離取
## 兩者較大嗰個（較保守，確保橫向都唔會爆鏡），先再喺呢個距離之下
## 用 _solve_camera_height_for_bottom_fit() 揸實垂直位置。
func _compute_camera_frame() -> Dictionary:
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(CAMERA_PITCH_DEG), deg_to_rad(CAMERA_YAW_DEG), 0.0)
	)
	var basis_t := basis.transposed() # 正交矩陣嘅轉置＝反矩陣，world→local

	var locals: Array[Vector3] = []
	for p in _camera_reference_points():
		locals.append(basis_t * p)

	var min_lx: float = INF
	var max_lx: float = -INF
	var max_lz: float = -INF
	for l: Vector3 in locals:
		min_lx = minf(min_lx, l.x)
		max_lx = maxf(max_lx, l.x)
		max_lz = maxf(max_lz, l.z)
	var local_cx: float = (min_lx + max_lx) * 0.5

	var half_fov_v: float = deg_to_rad(CAMERA_FOV_DEG) * 0.5
	var k_v: float = tan(half_fov_v)
	# keep_aspect＝KEEP_HEIGHT：垂直 FOV 固定，橫向 FOV 隨畫面闊高比縮放
	# （tan(半橫向)＝tan(半垂直)×aspect，唔使行 atan／tan 一嚟一回）。
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var k_h: float = k_v * aspect

	var top_frac: float = c.hud_top / 100.0 + CAMERA_TOP_MARGIN
	var bottom_frac: float = 1.0 - (c.hud_bottom / 100.0) - CAMERA_BOTTOM_MARGIN

	var local_cz_horizontal: float = -INF
	for l: Vector3 in locals:
		var needed: float = l.z + (absf(l.x - local_cx) + CAMERA_HORIZONTAL_MARGIN_WORLD) / k_h
		local_cz_horizontal = maxf(local_cz_horizontal, needed)

	var local_cz_vertical: float = _solve_camera_distance_for_vertical_fit(
		locals, max_lz, k_v, top_frac, bottom_frac
	)
	var local_cz: float = maxf(local_cz_vertical, local_cz_horizontal)
	var local_cy: float = _solve_camera_height_centered(locals, local_cz, k_v, top_frac, bottom_frac)

	var cam_pos: Vector3 = basis.x * local_cx + basis.y * local_cy + basis.z * local_cz
	return {"position": cam_pos}

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	# VR-06b：透視取代正交（issue 視覺參考：望落峽谷，前景大後景細）。
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = CAMERA_FOV_DEG
	cam.keep_aspect = Camera3D.KEEP_HEIGHT # fov＝垂直視野，唔受畫面闊度影響
	cam.rotation_degrees = Vector3(CAMERA_PITCH_DEG, CAMERA_YAW_DEG, 0.0)
	var frame := _compute_camera_frame()
	cam.position = frame["position"]
	cam.current = true
	_world.add_child(cam)
	_camera = cam
	_camera_base_position = frame["position"] # VR-11：拖動嘅基準點，_camera_pan=0 即係呢個預設取景

	# VR-06：洞穴暖色環境光 + 帶陰影嘅太陽光，代替預設冇環境光嘅平光。
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.13, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.46, 0.4)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_world.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	# 用戶實機回饋（ALTA-150）：斜視之後 BoxMesh 要睇得出側面／立體感，
	# 曾經加過淡陰影；VR-06 加暖色溫度（洞穴太陽光唔係死白）。
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 1.1
	# 效能修正（ALTA-219 fps 調查）：呢張場景成個峽谷（岩壁／12 層梯田／
	# 切面石／雜物／門／木橋等）有幾百件個別 MeshInstance3D，實時陰影
	# 每幀都要將呢批嘢全部再畫一次落 shadow map，S8+ 實測（Time.get_ticks_usec()
	# 逐段計時 + adb logcat）淨係呢個 shadow pass 就令狂熱 fps 由持續
	# 60fps 跌返落 33～35（未達 issue 「fps ≥ 40」門檻），同狂熱物件數量
	# 完全無關（山腳未召喚任何礦工、debris 已經降到最低 cap 都係咁）。
	# ALTA-150 要求嘅「側面／立體感」主要嚟自 flat-shaded 材質
	# （SHADING_MODE_PER_VERTEX，見 VisualFactory.flat_material()）配合呢個
	# 斜射方向光——即使冇 cast shadow，唔同法線嘅面都會顯得唔同亮度，
	# 睇落仍然有塊面感；淨係少咗地面嘅投影黑影。兩者取捨之下，fps 呢個
	# issue 明文嘅硬性驗收線優先。
	light.shadow_enabled = false
	_world.add_child(light)

	# VR-06b：峽谷環境（岩壁「碗」+ 地面）——純背景裝飾，擺喺 _world
	# 底下而唔係 _placement_root，狂熱切換 _placement_root.visible 嗰陣
	# 唔會連環境一齊隱藏（同 IZM 參考一致：車場都係喺同一個峽谷入面）。
	# VR-06b 場地規格 v2：成個場地攤平做地面——site (x, y) 係地面平面，
	# site z 係高度。相機由上方 -62° 望落嚟（IZM 峽谷視角）。
	_site_root = Node3D.new()
	_site_root.name = "Site"
	_site_root.basis = SITE_BASIS
	_world.add_child(_site_root)

	_build_ground()
	_build_canyon_walls()
	_build_dressing()

	_placement_root = Node3D.new()
	_placement_root.name = "PlacementField"
	_site_root.add_child(_placement_root)

	_foothill_root = Node3D.new()
	_foothill_root.name = "Foothill"
	_foothill_root.position = _site_to_world(c.site_foothill_pos)
	_placement_root.add_child(_foothill_root)
	_rebuild_foothill_stack()

	var belt_track := VisualFactory.make_flat_box(
		Vector3(0.2, 0.03, (c.belt_head_pos - c.smelter_pos).length()), VisualFactory.PALETTE["belt"]
	)
	belt_track.name = "BeltTrack"
	var belt_mid := (c.belt_head_pos + c.smelter_pos) * 0.5
	belt_track.position = _site_to_world(belt_mid, 0.03)
	_placement_root.add_child(belt_track)
	belt_track.look_at(_placement_root.to_global(_site_to_world(c.smelter_pos)), _site_root.global_transform.basis.z)

	# ALTA-153 round2 第 6 點：帶「分段滾軸 mesh（有流動視覺）」——沿住帶
	# 本身嘅局部 Z 軸（look_at_from_position 已經令佢指向 smelter）平均
	# 擺幾條圓柱，掛做 belt_track 嘅子節點就自動跟埋個方向轉，唔使自己
	# 再算一次帶嘅角度。轉動邏輯喺 _process()。
	var belt_len: float = (c.belt_head_pos - c.smelter_pos).length()
	var roller_count := 5
	for i in range(roller_count):
		var frac: float = (float(i) / float(roller_count - 1)) - 0.5 if roller_count > 1 else 0.0
		var roller := VisualFactory.make_low_poly_cylinder(0.05, 0.22, VisualFactory.PALETTE["gear_metal"], 8, 0.6)
		roller.rotation_degrees.z = 90.0
		roller.position = Vector3(0.0, 0.02, frac * belt_len)
		belt_track.add_child(roller)
		_belt_rollers.append(roller)

	# 熔爐：藍身 + 發光藍火爐口（VR-06b 色板：爐口改藍火，同暖色洞穴做
	# 對比，見 VisualFactory.PALETTE 註解）+ 屋簷 + 一盞燈——「方形入口 +
	# 屋簷 + 一盞燈」語言（issue 視覺參考），用自己色，唔抄 IZM 藍頂。
	var smelter := Node3D.new()
	smelter.name = "Smelter"
	smelter.position = _site_to_world(c.smelter_pos, 0.3)
	var smelter_body := VisualFactory.make_metal_box(Vector3(0.7, 0.6, 0.6), VisualFactory.PALETTE["furnace_body"])
	smelter.add_child(smelter_body)
	var smelter_mouth := VisualFactory.make_metal_box(
		Vector3(0.36, 0.05, 0.3), VisualFactory.PALETTE["furnace_glow"], VisualFactory.PALETTE["furnace_glow"], 2.0
	)
	smelter_mouth.position = Vector3(0.0, -0.31, -0.08)
	smelter.add_child(smelter_mouth)
	var smelter_eave := VisualFactory.make_flat_box(Vector3(0.8, 0.26, 0.06), VisualFactory.PALETTE["entrance_eave"])
	smelter_eave.position = Vector3(0.0, -0.36, 0.33)
	smelter.add_child(smelter_eave)
	var smelter_lamp := VisualFactory.make_lamp(0.05, VisualFactory.PALETTE["lamp_warm"])
	smelter_lamp.position = Vector3(0.32, -0.34, 0.26)
	smelter.add_child(smelter_lamp)
	# 爐頂：煙囱 + 發光爐口（俯視鏡頭先見到火光）。
	var chimney := VisualFactory.make_metal_box(Vector3(0.22, 0.22, 0.3), VisualFactory.PALETTE["furnace_body"].darkened(0.2))
	chimney.position = Vector3(0.18, 0.12, 0.45)
	smelter.add_child(chimney)
	var top_glow := VisualFactory.make_metal_box(Vector3(0.3, 0.3, 0.06), Color(1.0, 0.45, 0.1), Color(1.0, 0.45, 0.1), 2.2)
	top_glow.position = Vector3(-0.15, -0.05, 0.33)
	smelter.add_child(top_glow)
	_placement_root.add_child(smelter)

	# 倉：body + 斜頂 + 一盞燈，同一套「入口 + 屋簷 + 一盞燈」語言。
	var warehouse := Node3D.new()
	warehouse.name = "Warehouse"
	warehouse.position = _site_to_world(c.warehouse_pos, 0.22)
	var warehouse_body := VisualFactory.make_flat_box(Vector3(0.7, 0.5, 0.44), VisualFactory.PALETTE["warehouse_body"])
	warehouse.add_child(warehouse_body)
	var warehouse_roof := VisualFactory.make_flat_box(Vector3(0.78, 0.58, 0.08), VisualFactory.PALETTE["warehouse_roof"])
	warehouse_roof.position = Vector3(0.0, 0.0, 0.26)
	warehouse.add_child(warehouse_roof)
	var warehouse_lamp := VisualFactory.make_lamp(0.05, VisualFactory.PALETTE["lamp_warm"])
	warehouse_lamp.position = Vector3(0.32, -0.28, 0.2)
	warehouse.add_child(warehouse_lamp)
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

	_build_region_expansion()

## VR-11：場地擴張框架——喺現有峽谷入面擺一個 UnlockPanel（見
## systems/unlock_panel.gd），代表「區域 2 入口」（field-zones-v9.png：
## 左上「200」紫色解鎖板）。區域 2 實際玩法／場地（VR-13，backlog）未
## 起，呢個板暫時淨係示範解鎖板機制本身：顯示價錢、撳落去夠錢就扣錢＋
## 記存檔，唔會真正解鎖到任何新玩法／場景（冇場景可解鎖）。已解鎖就開
## 場直接顯示「已解鎖」，唔使再撳一次。
func _build_region_expansion() -> void:
	_region2_panel = UnlockPanel.new()
	_region2_panel.name = "Region2UnlockPanel"
	_region2_panel.position = _site_to_world(REGION2_PANEL_SITE_POS, REGION2_PANEL_HEIGHT)
	_placement_root.add_child(_region2_panel)
	_region2_panel.setup("region2", c.region2_unlock_price, "區域 2　紫岩礦場", _try_unlock_region)
	if "region2" in _unlocked_regions:
		_region2_panel.mark_unlocked()

## UnlockPanel 撳落去嘅 callback。夠錢先真正扣 state.cash＋記落
## _unlocked_regions＋存檔；唔夠錢就乜都唔做（板自己會靠
## refresh_afford_state() 顯示緊「未夠錢」嘅暗色，唔使呢度另外彈提示）。
## 已經解鎖就直接跳過（板 _unlocked 之後理論上已經唔再接受撳，呢度係
## 額外防守）。
func _try_unlock_region(region_id: String, cost: float) -> void:
	if region_id in _unlocked_regions:
		return
	if state.cash < cost:
		return
	state.cash -= cost
	_unlocked_regions.append(region_id)
	EventLog.log_event("region_unlock", {"region": region_id, "cost": cost})
	SfxPlayer.play("upgrade")
	if _region2_panel != null and _region2_panel.region_id == region_id:
		_region2_panel.mark_unlocked()
	_save_game()
	_refresh_hud()

## VR-11：鏡頭可拖——觸控拖曳（手機）／滑鼠左鍵拖曳（Windows host
## 編輯器試玩）都接，累積 screen-space 嘅垂直位移落 _camera_pan，夾喺
## [0, CAMERA_MAX_PAN]。淨係影響相機位置（_update_camera_position()），
## 唔會攔截 pile chunk／解鎖板嘅 tap 判斷（嗰兩樣睇嘅係 Area3D
## input_event，同呢度嘅 _unhandled_input 係兩條獨立管道，Godot 會先派
## 去 3D 物件揀選，冇任何 3D 物件食咗先落嚟呢度）。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_apply_camera_drag(event.relative.y)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_apply_camera_drag(event.relative.y)

## 手指／滑鼠向上拖（screen_delta_y < 0，Godot 螢幕 Y 向下遞增）＝望上
## （睇多啲上面嘅區域），跟手機地圖 app 「向上掃＝望到上面更多嘢」嘅
## 慣例。
func _apply_camera_drag(screen_delta_y: float) -> void:
	_camera_pan = clampf(_camera_pan - screen_delta_y * CAMERA_DRAG_SENSITIVITY, 0.0, CAMERA_MAX_PAN)
	_update_camera_position()

func _update_camera_position() -> void:
	if _camera == null:
		return
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH_DEG), deg_to_rad(CAMERA_YAW_DEG), 0.0))
	_camera.position = _camera_base_position + basis.y * _camera_pan

## 場地規格 v2（ALTA-219）：地面／岩壁背景要冚住成個相機取景範圍
## （_camera_reference_points() 已經計埋山頂／車場兩牆），唔可以再各自
## 用「山腳↔倉」呢類窄範圍計大細——舊公式（見 git blame）算出嚟嘅底板
## 冚唔到實際山頂，中間成截冧咗冇地面冚住，露返出 WorldEnvironment 個
## 近黑背景色（用戶實機截圖 now.png／s8now.png：頂 45% 純黑嘅根源）。
## 改用同 `_build_canyon_walls()` 一致嘅邊界（下面 `_build_ground()` 嘅
## top_y／bottom_y），兩者夾埋保證相機見到嘅範圍冇一寸唔係地面／岩壁。

## VR-06b：地面——一嚿暖灰底板 + 兩三條淡車轍紋（用「decal」做法：幾嚿
## 更暗嘅幼長扁盒仔疊喺底板之上少少，代替 issue 講嘅 vertex color，
## 同一份 flat-shaded 盒仔手法，唔使起 SurfaceTool 自訂 mesh）。擺喺場地
## 中心（帶頭／爐／倉／車場之間），底板夠大冚晒中層帶睇得到嘅範圍。
## VR-06b 場地規格 v2 嘅場地裝飾：右側岩浆帶、爐前 SELL 大字、油桶方陣。
func _build_dressing() -> void:
	var dress := Node3D.new()
	dress.name = "Dressing"
	_site_root.add_child(dress)

	# 右側岩浆帶（闊 2 車闊≈1.0）由車場頂直落到倉。
	var lava_x: float = c.yard_x_range.y + 0.42
	var lava_top: float = c.site_foothill_pos.y + 0.9
	var lava_bottom: float = c.warehouse_pos.y - 0.6
	var lava := VisualFactory.make_metal_box(
		Vector3(0.5, lava_top - lava_bottom, 0.03), VisualFactory.PALETTE["lava"], VisualFactory.PALETTE["lava"], 1.8
	)
	lava.position = Vector3(lava_x, (lava_top + lava_bottom) * 0.5, 0.0)
	dress.add_child(lava)
	for _i in range(14):
		var crust := VisualFactory.make_flat_box(Vector3(rng.randf_range(0.08, 0.18), rng.randf_range(0.06, 0.14), 0.03), Color(0.3, 0.1, 0.05))
		crust.position = Vector3(lava_x + rng.randf_range(-0.2, 0.2), rng.randf_range(lava_bottom, lava_top), 0.01)
		crust.rotation.z = rng.randf_range(0.0, TAU)
		dress.add_child(crust)

	# 油桶方陣（障礙兼裝飾）喺車場左下角。
	for row in range(3):
		for col_i in range(3):
			var barrel := VisualFactory.make_low_poly_cylinder(0.11, 0.24, Color(0.2, 0.42, 0.75) if (row + col_i) % 2 == 0 else Color(0.25, 0.5, 0.85), 8, 0.35)
			barrel.rotation_degrees.x = 90.0
			barrel.position = Vector3(c.yard_x_range.x + 0.3 + float(col_i) * 0.25, c.warehouse_pos.y + 0.25 - float(row) * 0.25, 0.12)
			dress.add_child(barrel)

func _build_ground() -> void:
	var ground_root := Node3D.new()
	ground_root.name = "Ground"
	_site_root.add_child(ground_root)

	var mid_x: float = (c.yard_x_range.x + c.yard_x_range.y) * 0.5
	var top_y: float = c.site_foothill_pos.y + MOUNTAIN_DEPTH + 1.0
	# Review round 2：實機 deliver_opening.png 量到底部（爐／倉之後）有一
	# 條實色黑帶，pixel 掃描見到淨返 y≈1610–1730（螢幕高度嘅 ~5.4%）—
	# 呢度個 -0.5 margin 明顯唔夠：頂部用緊 +1.0 margin（相對 mountain_back_y
	# 基準）先冚到成個取景，底部得返 -0.5（相對 warehouse_pos 基準，扣埋
	# camera 因為橫向 fit 被逼企遠咗嘅額外空間，得返 0.15 淨 margin 遠遠
	# 唔夠），跟頂部同一個量級加大先夠。
	var bottom_y: float = c.warehouse_pos.y - 2.0
	var width: float = (c.yard_x_range.y - c.yard_x_range.x) + 3.0
	var height: float = top_y - bottom_y

	var slab := VisualFactory.make_flat_box(Vector3(width, height, 0.06), VisualFactory.PALETTE["ground_warm"])
	slab.name = "GroundSlab"
	slab.position = Vector3(mid_x, (top_y + bottom_y) * 0.5, -0.03)
	ground_root.add_child(slab)

	# 地面碰撞：碎料／波池剛體要有嘢托住（攤平之後重力向下 = site -z）。
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.2)
	col.shape = shape
	floor_body.add_child(col)
	floor_body.position = Vector3(mid_x, (top_y + bottom_y) * 0.5, -0.1)
	ground_root.add_child(floor_body)

	# 車轍紋：帶頭→爐→倉一條、車場中軸一條。
	var tread_paths: Array[Array] = [
		[c.belt_head_pos, c.smelter_pos, c.warehouse_pos],
		[Vector2(mid_x, c.car_park_max_y), Vector2(mid_x, c.yard_min_y)],
	]
	for path: Array in tread_paths:
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var seg_mid: Vector2 = (a + b) * 0.5
			var seg_len: float = (b - a).length()
			if seg_len < 0.001:
				continue
			var tread := VisualFactory.make_flat_box(Vector3(0.14, seg_len, 0.01), VisualFactory.PALETTE["ground_tread"])
			tread.position = _site_to_world(seg_mid, 0.005)
			tread.rotation.z = Vector2(0.0, 1.0).angle_to(b - a)
			ground_root.add_child(tread)

func _build_canyon_walls() -> void:
	var wall_root := Node3D.new()
	wall_root.name = "CanyonWalls"
	_site_root.add_child(wall_root)

	var left_x: float = c.yard_x_range.x - 0.55
	var right_x: float = c.yard_x_range.y + 1.05
	var back_y: float = c.site_foothill_pos.y + MOUNTAIN_DEPTH + 0.5
	var front_y: float = c.warehouse_pos.y - 0.3

	# 兩側：由前到後一排排切面大石，高 1.0–1.6（車高≈0.3 → 3–5 車高）。
	var step := 0.55
	var y: float = front_y
	while y <= back_y:
		for side in [-1.0, 1.0]:
			var base_x: float = left_x if side < 0.0 else right_x
			for layer in range(2):
				var h: float = rng.randf_range(0.9, 1.5) - float(layer) * 0.35
				var sz := Vector3(rng.randf_range(0.7, 1.1), rng.randf_range(0.5, 0.75), h)
				var tone: Color = VisualFactory.PALETTE["canyon_wall"].lerp(VisualFactory.PALETTE["canyon_wall_dark"], rng.randf() * 0.7)
				var facet := _make_rock(sz, tone)
				facet.position = Vector3(base_x + side * (0.35 + float(layer) * 0.55) + rng.randf_range(-0.1, 0.1), y + rng.randf_range(-0.12, 0.12), sz.z * 0.5 - 0.05)
				facet.rotation.z = rng.randf_range(-0.35, 0.35)
				wall_root.add_child(facet)
		y += step
	# 後方：一排高石包住山後面。
	var x: float = left_x
	while x <= right_x + 0.01:
		var sz := Vector3(rng.randf_range(0.7, 1.0), rng.randf_range(0.6, 0.9), rng.randf_range(1.4, 2.0))
		var tone: Color = VisualFactory.PALETTE["canyon_wall"].lerp(VisualFactory.PALETTE["canyon_wall_dark"], rng.randf() * 0.7)
		var facet := _make_rock(sz, tone)
		facet.position = Vector3(x + rng.randf_range(-0.1, 0.1), back_y + rng.randf_range(0.0, 0.3), sz.z * 0.5 - 0.05)
		facet.rotation.z = rng.randf_range(-0.3, 0.3)
		wall_root.add_child(facet)
		x += 0.6

## 一嚿切面岩石：低面數盒 + 頂面斜削（PrismMesh 立起嚟），size = (闊, 深, 高)。
func _make_rock(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var body := VisualFactory.make_flat_box(Vector3(size.x, size.y, size.z * 0.7), color)
	body.position = Vector3(0.0, 0.0, -size.z * 0.15)
	root.add_child(body)
	var cap := VisualFactory.make_rock_facet(Vector3(size.x, size.z * 0.3, size.y), color.lightened(0.12), rng.randf_range(0.2, 0.8))
	cap.rotation_degrees.x = 90.0
	cap.position = Vector3(0.0, 0.0, size.z * 0.35)
	root.add_child(cap)
	return root

func _tier_box_size(tier_index: int) -> Vector3:
	var t: float = float(tier_index) / float(maxi(c.miner_summon_cap, 1))
	return Vector3(MOUNTAIN_WIDTH * (1.0 - t * 0.55), MOUNTAIN_DEPTH * (1.0 - t * 0.6), FOOTHILL_TIER_HEIGHT)

func _tier_center_y(tier_index: int) -> float:
	# 每層向後縮：後緣固定喺 MOUNTAIN_DEPTH，前緣逐層退後，形成面向車場嘅梯級。
	return MOUNTAIN_DEPTH - _tier_box_size(tier_index).y * 0.5

func _tier_center_z(tier_index: int) -> float:
	return FOOTHILL_BASE_HEIGHT + float(tier_index) * FOOTHILL_TIER_HEIGHT + FOOTHILL_TIER_HEIGHT * 0.5

func _tier_center_local(tier_index: int) -> Vector3:
	return Vector3(0.0, _tier_center_y(tier_index), _tier_center_z(tier_index))

func _rebuild_foothill_stack() -> void:
	for child in _foothill_root.get_children():
		child.queue_free()
	var base := VisualFactory.make_flat_box(Vector3(MOUNTAIN_WIDTH + 0.3, MOUNTAIN_DEPTH + 0.2, FOOTHILL_BASE_HEIGHT), VisualFactory.PALETTE["cave"])
	base.position = Vector3(0.0, MOUNTAIN_DEPTH * 0.5, FOOTHILL_BASE_HEIGHT * 0.5)
	_foothill_root.add_child(base)

	var total_tiers: int = c.miner_summon_cap
	var mined_tiers: int = state.miner_count
	for i in range(total_tiers):
		var mined: bool = i < mined_tiers
		var tier_color: Color = VisualFactory.PALETTE["cave_light"] if mined else VisualFactory.PALETTE["cave"]
		var box_size := _tier_box_size(i)
		var box := VisualFactory.make_flat_box(box_size, tier_color)
		box.name = "Tier%d" % (i + 1)
		box.position = _tier_center_local(i)
		_foothill_root.add_child(box)
		# Review（round 1）：`_add_tier_rock_facets()` 一直有定義但冇 call
		# 過——梯田淨返 box 本身，睇落係「樓梯形平板」而唔係 issue 要求嘅
		# 「切面大石」語言（同 `_build_canyon_walls()` 一致嘅打散直邊做法）。
		# 每層前緣散幾嚿切面石打散直邊輪廓，box 本身留低唔改（bounding box
		# 測試／碎料落點全部跟 box，見 test_pile_debris_spawns_outside_terrace_footprint）。
		_add_tier_rock_facets(box_size, box.position, tier_color)
		# 每層前緣鋪一排雜物（油桶／木箱／輪胎／廢鐵），廢料山要似「堆滿嘢」。
		_add_tier_clutter(box_size, box.position, 3 if mined else 2)

func _add_tier_rock_facets(box_size: Vector3, box_pos: Vector3, tier_color: Color) -> void:
	var facet_count := 4
	for f in range(facet_count):
		var frac: float = (float(f) + 0.5) / float(facet_count) - 0.5
		var facet_size := Vector3(
			box_size.x / float(facet_count) * 1.6 + rng.randf_range(-0.04, 0.08),
			box_size.y * (1.05 + rng.randf_range(0.0, 0.7)),
			box_size.z * (0.5 + rng.randf_range(0.0, 0.35))
		)
		var tone: Color = tier_color.lerp(VisualFactory.PALETTE["canyon_wall_dark"], rng.randf_range(0.0, 0.4))
		var facet := VisualFactory.make_rock_facet(facet_size, tone, rng.randf())
		facet.position = box_pos + Vector3(
			frac * box_size.x + rng.randf_range(-0.03, 0.03),
			box_size.y * 0.5,
			box_size.z * 0.5 - facet_size.z * 0.3 + rng.randf_range(-0.03, 0.05)
		)
		facet.rotation.y = rng.randf_range(0.0, TAU)
		_foothill_root.add_child(facet)

## 每兩層開採咗嘅梯田加一件雜物（隨機揀木桶／木板／齒輪），擺喺嗰層
## 面頂中央附近少少 jitter。純美術裝飾，冇碰撞、唔影響任何判定。
func _add_tier_clutter(box_size: Vector3, box_pos: Vector3, count: int) -> void:
	for _i in range(count):
		var prop: Node3D
		match rng.randi_range(0, 3):
			0: # 油桶（立起）
				prop = VisualFactory.make_low_poly_cylinder(0.06, 0.12, [Color(0.75, 0.25, 0.15), Color(0.2, 0.4, 0.7), Color(0.85, 0.7, 0.2)][rng.randi_range(0, 2)], 8, 0.3)
				prop.rotation_degrees.x = 90.0
			1: # 木箱
				prop = VisualFactory.make_flat_box(Vector3(0.14, 0.14, 0.12), VisualFactory.PALETTE["bridge_wood"])
			2: # 輪胎（平放）
				prop = VisualFactory.make_low_poly_cylinder(0.08, 0.05, Color(0.12, 0.12, 0.13), 10, 0.1)
				prop.rotation_degrees.x = 90.0
			_: # 廢鐵板
				prop = VisualFactory.make_flat_box(Vector3(0.22, 0.05, 0.16), VisualFactory.PALETTE["gear_metal"])
				prop.rotation_degrees.y = rng.randf_range(-25.0, 25.0)
		prop.rotation.z = rng.randf_range(0.0, TAU)
		prop.position = box_pos + Vector3(
			rng.randf_range(-box_size.x * 0.45, box_size.x * 0.45),
			-box_size.y * 0.5 + rng.randf_range(0.05, 0.22),
			box_size.z * 0.5 + 0.06
		)
		_foothill_root.add_child(prop)

# ══════════════════════ 礦工 ══════════════════════

## 圍住山腳分佈嘅半徑——純美術造型常數（見 _place_miner_around_foothill()）。
const MINER_RING_RADIUS := 0.5

## 生一隻機械人礦工 node 落 _miners_root，圍住山腳擺好位＋開始敲擊動畫。
## `_try_summon_miner()`（單粒，召喚嗰刻）同 `_spawn_loaded_miners()`
## （開機讀存檔，一次過補晒已經召喚落嘅幾隻）共用，避免兩處各自維護一份
## 「點樣起一隻礦工」嘅邏輯。
func _spawn_miner_visual(index: int) -> void:
	# VR-06：機械人 glTF（CREDITS.md）origin 喺腳底（y=0），同舊盒仔置中
	# 唔同，企喺 y=0.1 貼地；盒仔 fallback 個樣會企得稍為浮啲，接受。
	var miner := VisualFactory.make_miner()
	miner.name = "Miner%d" % (index + 1)
	# 一定要先 add_child() 先至叫 _place_miner_around_foothill()／
	# _animate_mining()——`look_at()` 同 `create_tween()` 兩個都要求個
	# node 已經喺 scene tree 入面（唔係就 engine 拋 "!is_inside_tree()"）。
	_miners_root.add_child(miner)
	_place_miner_around_foothill(miner, index)
	_animate_mining(miner)

func _try_summon_miner() -> void:
	if not state.summon_miner():
		return
	_spawn_miner_visual(state.miner_count - 1)
	_rebuild_foothill_stack()
	_save_game() # VR-05b：召喚即存檔

## VR-05b review fix：開機讀到存檔已經有嘅礦工要即刻補返晒啲 node——
## `_build_world()` 淨係起空嘅 `_miners_root`，之前淨靠
## `_try_summon_miner()` 先會生 node，讀檔冇行過呢條 path，殺 App 重開
## HUD 話「礦工 3/12」但山腳一隻機械人都冇（實機驗收會即刻見到）。梯田
## 已經開採嘅色（`_rebuild_foothill_stack()`）唔使呢度理——`_build_world()`
## 起 `_foothill_root` 嗰陣已經讀緊 `state.miner_count`（讀檔喺
## `_build_world()` 之前套用），淨係缺咗礦工 node 本身。新玩家
## state.miner_count＝0，呢個 loop 冧一世都唔會行，可以每次都照叫，唔使
## 額外 if save_exists 判斷。
func _spawn_loaded_miners() -> void:
	for i in range(state.miner_count):
		_spawn_miner_visual(i)

## 用戶實機回饋（round2 第 5 點）：召喚後嘅礦工「圍住山腳分佈」，唔係
## 全部堆喺同一個原點嘅少少 jitter。用極座標分佈喺山腳前面半圈，面朝住
## 圓心（即係山腳本身）——先有「一齊喺度開採緊」嘅感覺，唔會個個疊晒
## 埋一堆。
##
## Review 意見（round2 修正）兩點：
## 1. 淨用前半弧（-90°~90°，即 z ≥ 0 嗰邊）：相機喺 +Z 上方望落，成圈
##    12 格擺滿 360° 嘅話，z < 0 嗰四五隻會俾梯田本身完全遮住，用戶
##    見唔到，等於白召喚。
## 2. `look_at()` 收嘅係全域座標——之前錯咗直接畀 `_miners_root` 嘅
##    local 原點 (0, miner_y, 0) 當全域用，等於望住世界原點，唔係望住
##    山腳，仲累到成隻礦工歪晒（pitch/roll 都唔啱），`_animate_mining()`
##    嘅 swing 再以呢個歪咗嘅姿勢做 base，變咗長期趴住。要用
##    `_miners_root.to_global()` 攞返正確嘅全域目標點。
func _place_miner_around_foothill(miner: Node3D, index: int) -> void:
	# 礦工企喺山腳前面一排（site -y 方向），面向山。
	var slot_count: int = maxi(c.miner_summon_cap, 1)
	var t: float = (float(index) + 0.5) / float(slot_count)
	var x: float = (t - 0.5) * (MOUNTAIN_WIDTH * 0.9) + rng.randf_range(-0.04, 0.04)
	var y: float = -0.22 - rng.randf_range(0.0, 0.12)
	miner.position = Vector3(x, y, 0.0)
	# glTF 模型 +y 向上；場地攤平後「上」係 site +z，所以先轉 90°，再繞 z 轉去面向山（+y）。
	var miner_scale: Vector3 = miner.scale
	# 實機見到 Rx(90°) 之後礦工「面朝天躺低」→ 呢個 glTF 本身 up 係 +z；淨係繞 z 轉去面向山。
	miner.basis = Basis.IDENTITY.scaled(miner_scale)

func _animate_mining(node: Node3D) -> void:
	var base_z := node.position.z
	var bob_tw := create_tween()
	bob_tw.set_loops()
	bob_tw.tween_property(node, "position:z", base_z + 0.04, 0.22).set_trans(Tween.TRANS_SINE)
	bob_tw.tween_property(node, "position:z", base_z, 0.22).set_trans(Tween.TRANS_SINE)

	var base_rot_x := node.rotation.x
	var swing_tw := create_tween()
	swing_tw.set_loops()
	swing_tw.tween_property(node, "rotation:x", base_rot_x + 0.3, 0.18).set_trans(Tween.TRANS_SINE)
	swing_tw.tween_property(node, "rotation:x", base_rot_x, 0.26).set_trans(Tween.TRANS_SINE)

# ══════════════════════ 山腳碎料：手動 scoop ══════════════════════

func _on_pile_spawn_timeout() -> void:
	if state.pile_debris.size() >= c.miner_summon_cap:
		return # 山腳未撿碎料太多就唔再生（避免場景無限脹）
	var ore_key := state.spawn_pile_debris(rng, "foothill")
	if ore_key == "":
		return
	_spawn_pile_visual(ore_key)

## Review 意見（round2 修正一）：舊生成位（y=0.55、z∈±0.3）喺 12 層梯田
## 未常駐嗰陣係安全嘅（企喺個地台頂嘅半空度），而家梯田由開場就長到
## 盡，嗰個位啱啱好陷咗入 tier1／2 個 box 入面（headless 量度 300 粒有
## 105 粒完全睇唔到）。
##
## Review 意見（round2 修正二）：修正一改咗擺喺山腳地面前排一圈（+Z
## 去到 0.95），冇再陷落梯田，但呢個俯視相機（pitch −57.5°）之下 +Z
## 會將螢幕位置推落去車場個範圍（headless 量度 300 粒有 233 粒跌咗落
## 車場跟指守衛之下，狂熱期間撳中會連車都拖埋）——一味郁 Z 去避開梯田
## 幾何，先係跌落車場範圍嘅根源。
##
## 改用「揸實 tier 0（山最前、最大嗰層）嘅高度＋淨係用佢自己嘅前面緣」
## 代替：企喺 tier 0 自己中心 y、x 揀喺 tier 0 闊度以內、z 淨係推出
## tier 0 自己嘅半深——tier 0 係全山最闊最深嗰層，前緣一定喺全部其他
## tier 前面，唔會陷落任何一層，唔使再揀「邊層先安全」（Review round 1：
## 曾經諗住喺一個 tier 範圍隨機揀，但 tier 0 本身已經滿足晒「唔陷落」＋
## 「唔跌落車場螢幕範圍」兩個條件，冇必要加呢層複雜度）。
func _spawn_pile_visual(ore_key: String) -> void:
	var chunk := VisualFactory.make_ore_chunk(PILE_CHUNK_VISUAL_SIZE, _ore_color(ore_key))
	var tier_index: int = 0
	var box_size := _tier_box_size(tier_index)
	var center := _tier_center_local(tier_index)
	var x: float = rng.randf_range(-box_size.x * 0.45, box_size.x * 0.45)
	var y: float = center.y - box_size.y * 0.5 + rng.randf_range(0.03, 0.07)
	chunk.position = Vector3(x, y, center.z + box_size.z * 0.5 + PILE_CHUNK_VISUAL_SIZE * 0.5)
	chunk.rotation_degrees.x = 90.0
	chunk.rotation.z = rng.randf_range(0.0, TAU)

	var area := Area3D.new()
	area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * PILE_CHUNK_TAP_HIT_SIZE
	col.shape = shape
	area.add_child(col)
	chunk.add_child(area)
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
	_lifetime_cash += gained # VR-05b：手動剷都計入終身 Cash（威望門檻用）
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

	# -- 頂：VR-06b 跟 issue 視覺參考重排——第一行三資源（圓 icon +
	# 數字 + 「+」掣，暫不接功能）、第二行左「礦工 n/12」pill ＋中
	# 「山腳／中層鎖住」pill ＋右設定／任務兩個方掣（先做外觀，同一行
	# flow，唔用疊層）；第三行威望進度（VR-05 重置邏輯，呢度只顯示，
	# 字冧入 slim bar 度慳位，見 round 1 review）。 --
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

	var resources_row := HBoxContainer.new()
	top_vbox.add_child(resources_row)
	_cash_label = _add_top_resource_slot(resources_row, "res://assets/icons/coin.png", Color(1.0, 0.85, 0.35))
	_components_label = _add_top_resource_slot(resources_row, "res://assets/icons/gear.png", Color(0.75, 0.78, 0.85))
	_eco_label = _add_top_resource_slot(resources_row, "res://assets/icons/eco_leaf.png", Color(0.55, 0.85, 0.5))

	# Review 意見（ALTA-214 round 1）：右上設定／任務掣之前用獨立
	# `corner_row` 疊喺 top_bar 上面（PRESET_TOP_WIDE），同 resources_row
	# 嗰行（EXPAND_FILL 佔晒全闊）疊埋一齊，Eco 格嘅「+」掣被冚住。
	# 改法：兩個掣搬入 status_row 尾（同一行 flow，唔再疊層），中間加
	# 一個 EXPAND_FILL 嘅 spacer 將 pill 推左、掣推右，唔會再撞。
	var status_row := HBoxContainer.new()
	top_vbox.add_child(status_row)
	_miner_count_label = _add_pill(status_row, "礦工 0/%d" % c.miner_summon_cap, "")
	# issue 文案要求完整數字「鎖住 · 2,000,000」，唔用 _fmt_num() 嘅
	# K/M 縮寫（嗰個係俾底部窄 HUD 用）。
	_lock_label = _add_pill(status_row, "鎖住 · %s" % _fmt_int_commas(c.unlock_price("mid")), "res://assets/icons/locked.png")

	var status_spacer := Control.new()
	status_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_spacer)

	# 右上：設定／任務兩個方掣——issue 話「先做外觀」，暫時冇接任何功能。
	status_row.add_child(_make_square_icon_button("res://assets/icons/gear.png"))
	status_row.add_child(_make_square_icon_button("res://assets/icons/star.png"))

	# Review 意見（round 1）：資源行＋pill 行＋威望 bar＋威望字四行加埋
	# 3×4 間距 ≈123px，仲超咗 TopBar 12%＝115px（720×960）。威望字冧入
	# 條 bar 度（Control 疊層：slim ProgressBar + 置中 Label overlay），
	# 由兩行縮做一行，慳返成行高度。VR-05b：bar／label 依家接返
	# _lifetime_cash／c.prestige_threshold(_prestige_count) 實際數值（見
	# _refresh_hud()），呢度淨係擺位＋初始文字。
	var prestige_wrap := Control.new()
	prestige_wrap.custom_minimum_size = Vector2(0.0, 16.0)
	top_vbox.add_child(prestige_wrap)

	_prestige_bar = ProgressBar.new()
	_prestige_bar.min_value = 0.0
	_prestige_bar.max_value = c.prestige_threshold(0)
	_prestige_bar.value = 0.0
	_prestige_bar.show_percentage = false
	_prestige_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	prestige_wrap.add_child(_prestige_bar)

	_prestige_label = Label.new()
	_prestige_label.text = "威望 0 / %s" % _fmt_num(c.prestige_threshold(0))
	_prestige_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prestige_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prestige_label.add_theme_font_size_override("font_size", 11)
	_prestige_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_prestige_label.add_theme_constant_override("outline_size", 3)
	_prestige_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	prestige_wrap.add_child(_prestige_label)

	# VR-05b：達到威望門檻先顯示嘅「拆廠搬礦」掣，平時 hidden（_refresh_hud()
	# 接 Prestige.can_prestige() 話事），唔會常駐佔 TopBar 高度預算。
	_prestige_button = Button.new()
	_prestige_button.text = "拆廠搬礦"
	_prestige_button.visible = false
	_prestige_button.pressed.connect(_show_prestige_confirm)
	top_vbox.add_child(_prestige_button)

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

	# VR-06b：三資源搬咗上頂 HUD（issue 視覺參考排法），底部淨低升級
	# 掣同「地上大字＋價錢」呢類升級／觸發按鈕，唔再重複顯示資源數字。
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

	if ResourceLoader.exists("res://assets/icons/arrowRight.png"):
		_belt_icon_arrow = load("res://assets/icons/arrowRight.png")
	if ResourceLoader.exists("res://assets/icons/checkmark.png"):
		_belt_icon_check = load("res://assets/icons/checkmark.png")

	_belt_upgrade_button = Button.new()
	_belt_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_upgrade_button(_belt_upgrade_button, "res://assets/icons/arrowRight.png")
	_belt_upgrade_button.pressed.connect(func() -> void:
		if state.upgrade_belt():
			EventLog.log_event("upgrade", {"track": "belt", "level": state.belt_level})
			SfxPlayer.play("upgrade")
			_save_game()
	)
	upgrades_row.add_child(_belt_upgrade_button)

	_miner_upgrade_button = Button.new()
	_miner_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_upgrade_button(_miner_upgrade_button, "res://assets/icons/plus.png")
	_miner_upgrade_button.pressed.connect(func() -> void:
		if state.upgrade_miner_level():
			EventLog.log_event("upgrade", {"track": "miner", "level": state.miner_level})
			SfxPlayer.play("upgrade")
			_save_game()
	)
	upgrades_row.add_child(_miner_upgrade_button)

	_refine_upgrade_button = Button.new()
	_refine_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_upgrade_button(_refine_upgrade_button, "res://assets/icons/wrench.png")
	_refine_upgrade_button.pressed.connect(func() -> void:
		if state.upgrade_refine():
			EventLog.log_event("upgrade", {"track": "refine", "level": state.refine_level})
			SfxPlayer.play("upgrade")
			_save_game()
	)
	upgrades_row.add_child(_refine_upgrade_button)

	_build_offline_panel(hud)
	_build_prestige_confirm_panel(hud)

## VR-05b：離線報告／威望確認兩個彈窗共用嘅底——scrim（擋背後撳掣）+
## CenterContainer 置中一張深色圓角卡片，同 _make_circular_icon()／
## _add_pill() 同一套色板（VR-06b pill／icon 風格）。回傳
## {overlay, vbox}：overlay 預設 hidden，顯示／隱藏由呼叫方自己揸；
## vbox 俾呼叫方塞內容。
func _build_modal_card(hud: CanvasLayer, node_name: String) -> Dictionary:
	var overlay := Control.new()
	overlay.name = node_name
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	hud.add_child(overlay)

	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.6)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP # 擋住背後嘅撳掣
	overlay.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.1, 0.95)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(260.0, 0.0)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	return {"overlay": overlay, "vbox": vbox}

## VR-05b：離線結算面板——開機讀到存檔就彈（見 _run_offline_settlement()），
## 浣熊經理文案（data/offline_report.gd）+ 收成金額 + 「收下」／「×2」
## 兩個掣（issue：「×2」先顯示但灰，rewarded 接駁留 VR-07）。
func _build_offline_panel(hud: CanvasLayer) -> void:
	var modal := _build_modal_card(hud, "OfflinePanel")
	_offline_panel = modal["overlay"]
	var vbox: VBoxContainer = modal["vbox"]

	_offline_message_label = Label.new()
	_offline_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_offline_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offline_message_label.custom_minimum_size = Vector2(220.0, 0.0)
	vbox.add_child(_offline_message_label)

	var yield_row := HBoxContainer.new()
	yield_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(yield_row)
	yield_row.add_child(_make_circular_icon("res://assets/icons/coin.png", Color(1.0, 0.85, 0.35)))
	_offline_yield_label = Label.new()
	_offline_yield_label.add_theme_font_size_override("font_size", 20)
	yield_row.add_child(_offline_yield_label)

	var buttons_row := HBoxContainer.new()
	vbox.add_child(buttons_row)

	_offline_double_button = Button.new()
	_offline_double_button.text = "×2（睇廣告）"
	_offline_double_button.disabled = true # rewarded 廣告接駁留 VR-07，呢度淨係擺位＋停用
	_offline_double_button.tooltip_text = "未接（VR-07）"
	_offline_double_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_row.add_child(_offline_double_button)

	_offline_claim_button = Button.new()
	_offline_claim_button.text = "收下"
	_offline_claim_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offline_claim_button.pressed.connect(_on_offline_claim_pressed)
	buttons_row.add_child(_offline_claim_button)

## VR-05b：威望重置確認面板——撳「拆廠搬礦」先彈，講清楚清乜留乜同
## 重置後嘅新倍率，避免玩家手快手震清咗都唔知。
func _build_prestige_confirm_panel(hud: CanvasLayer) -> void:
	var modal := _build_modal_card(hud, "PrestigeConfirmPanel")
	_prestige_confirm_panel = modal["overlay"]
	var vbox: VBoxContainer = modal["vbox"]

	_prestige_confirm_label = Label.new()
	_prestige_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_prestige_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prestige_confirm_label.custom_minimum_size = Vector2(240.0, 0.0)
	vbox.add_child(_prestige_confirm_label)

	var buttons_row := HBoxContainer.new()
	vbox.add_child(buttons_row)

	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(func() -> void: _prestige_confirm_panel.visible = false)
	buttons_row.add_child(cancel_button)

	var confirm_button := Button.new()
	confirm_button.text = "確認重置"
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(_do_prestige_reset)
	buttons_row.add_child(confirm_button)

## VR-06b：頂列資源一格——圓 icon（見 _make_circular_icon()）+ 數值
## label + 「+」掣（跟 issue 視覺參考：暫不接功能，未來 rewarded 廣告
## 加碼接落呢個掣，VR-07 範圍）。回傳數值 label 俾 _refresh_hud() 更新。
func _add_top_resource_slot(parent: HBoxContainer, icon_path: String, tint: Color) -> Label:
	var slot := HBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slot)
	slot.add_child(_make_circular_icon(icon_path, tint))
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(lbl)
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(24.0, 24.0)
	add_btn.tooltip_text = "睇廣告加碼（未接，VR-07）"
	slot.add_child(add_btn)
	return lbl

## VR-06b：圓形 icon 底——PanelContainer + 圓角 StyleBoxFlat（半徑等於
## 一半闊高即係正圓），代替之前方形 TextureRect，跟 issue 視覺參考
## 「三資源各一圓 icon」。
func _make_circular_icon(icon_path: String, tint: Color) -> Control:
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.13, 0.11, 0.9)
	style.set_corner_radius_all(16)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(32.0, 32.0)
	badge.add_child(VisualFactory.make_icon(icon_path, 20.0, tint))
	return badge

## VR-06b：pill——深色圓角底 + （可選 icon）+ label，代替之前純文字行，
## 跟 issue 視覺參考「礦工 n/12」「山腳／中層鎖住」兩個 pill。回傳
## label 俾 _refresh_hud() 更新文字。
func _add_pill(parent: HBoxContainer, initial_text: String, icon_path: String = "") -> Label:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.1, 0.85)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var row := HBoxContainer.new()
	panel.add_child(row)
	if icon_path != "":
		row.add_child(VisualFactory.make_icon(icon_path, 14.0, Color(0.9, 0.85, 0.75)))
	var label := Label.new()
	label.text = initial_text
	row.add_child(label)
	return label

## VR-06b：右上設定／任務方掣——issue 話「先做外觀」，暫時冇連任何
## pressed 訊號。
func _make_square_icon_button(icon_path: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(34.0, 34.0)
	if ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path)
	btn.add_theme_constant_override("icon_max_width", 20)
	return btn

## 升級按鈕統一加 icon（Kenney Game Icons，見 CREDITS.md），icon 大細
## 用 theme constant 夾住，唔會俾原生 50x50 PNG 谷爆粒按鈕。
func _style_upgrade_button(button: Button, icon_path: String) -> void:
	if ResourceLoader.exists(icon_path):
		button.icon = load(icon_path)
	button.add_theme_constant_override("icon_max_width", 22)

func _refresh_hud() -> void:
	_cash_label.text = _fmt_num(state.cash)
	_components_label.text = _fmt_num(state.components)
	_eco_label.text = _fmt_num(state.eco)
	_miner_count_label.text = "礦工 %d/%d" % [state.miner_count, c.miner_summon_cap]

	if _region2_panel != null:
		_region2_panel.refresh_afford_state(state.cash) # VR-11：解鎖板「夠唔夠錢」嘅暗／亮色跟返即時 Cash

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
		var belt_text := "帶 Lv%d → 升級 %s" % [state.belt_level, _fmt_num(state.next_belt_cost())]
		if _belt_upgrade_button.text != belt_text:
			_belt_upgrade_button.text = belt_text
		_belt_upgrade_button.disabled = not affordable
		_set_afford_color(_belt_upgrade_button, affordable)
		# 威望重置（VR-05）會將帶等級打番去 1，換返箭嘴（唔會停留喺
		# 上鋪封頂嗰刻嘅剔號）。
		# 效能修正（ALTA-219 fps 調查）：_refresh_hud() 本身每幀都 call——
		# 之前呢度每幀都行一次 ResourceLoader.exists()／load()，喺
		# Android pck 入面查／攞一個 texture 資源，實測（S8+，adb logcat
		# Performance.TIME_PROCESS）單係呢兩句每幀就食成 20+ms，係狂熱
		# fps 跌到 13～15（門檻 40）嘅主因之一。改用 _build_hud() 起嗰陣
		# 預先 load() 一次嘅 _belt_icon_arrow／_belt_icon_check（見該處），
		# 呢度淨係揀返個已經攞好嘅 reference，唔再 touch ResourceLoader。
		if _belt_upgrade_button.icon != _belt_icon_arrow:
			_belt_upgrade_button.icon = _belt_icon_arrow
	else:
		_belt_upgrade_button.text = "帶 Lv%d（封頂）" % state.belt_level
		_belt_upgrade_button.disabled = true
		_clear_afford_color(_belt_upgrade_button) # 封頂，唔係等錢
		# 封頂之後箭嘴 icon 冇意思，換做剔號（同一 icon_max_width 樣式）。
		if _belt_upgrade_button.icon != _belt_icon_check:
			_belt_upgrade_button.icon = _belt_icon_check

	var miner_lv_affordable := state.cash >= state.next_miner_level_cost()
	var miner_text := "礦工 Lv%d → 升級 %s" % [state.miner_level, _fmt_num(state.next_miner_level_cost())]
	if _miner_upgrade_button.text != miner_text:
		_miner_upgrade_button.text = miner_text
	_miner_upgrade_button.disabled = not miner_lv_affordable
	_set_afford_color(_miner_upgrade_button, miner_lv_affordable)

	var refine_affordable := state.cash >= state.next_refine_level_cost()
	var refine_text := "精煉 Lv%d → 升級 %s" % [state.refine_level, _fmt_num(state.next_refine_level_cost())]
	if _refine_upgrade_button.text != refine_text:
		_refine_upgrade_button.text = refine_text
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

	# VR-05b：威望 bar／label／「拆廠搬礦」掣接返 _lifetime_cash 同
	# c.prestige_threshold(_prestige_count)（之前 VR-06b 淨係擺位，固定
	# 顯示 0）。
	var prestige_threshold := c.prestige_threshold(_prestige_count)
	_prestige_bar.max_value = prestige_threshold
	_prestige_bar.value = clampf(_lifetime_cash, 0.0, prestige_threshold)
	_prestige_label.text = "威望 %s / %s" % [_fmt_num(_lifetime_cash), _fmt_num(prestige_threshold)]
	_prestige_button.visible = Prestige.can_prestige(c, {"lifetime_cash": _lifetime_cash, "prestige_count": _prestige_count})

## 用戶實機回饋（ALTA-150）：升級掣全部灰晒，撞唔到分清楚係「等緊
## 錢」定「壞咗」。夠錢就轉返正常／綠色，唔夠錢價錢轉紅色，等玩家知
## 道等緊儲夠錢，唔係壞咗。（撞上限／封頂嘅掣唔叫呢個，維持預設灰色。）
##
## 效能修正（ALTA-219 fps 調查）：`_refresh_hud()` 每幀都 call，之前呢
## 兩個 function 每幀都無條件 add/remove_theme_color_override()——實測
## （S8+，Time.get_ticks_usec() 逐段計時）帶／礦工／精煉三個「有 icon」
## 嘅升級掣，單係呢兩句每幀就食成 7～9ms（冇 icon 嘅召喚掣淨係 ~1.3ms），
## 三個掣加埋成 23ms，係狂熱 fps 跌到 13～15（門檻 40）嘅主因。呢度加
## `_afford_color_cache` 記低上次套用嗰個狀態，狀態冇變就即刻 return，
## 唔再逐幀重複 touch theme override（affordable 真正改變嗰幾幀先真係
## 重新上色，畫面行為完全一樣）。
var _afford_color_cache: Dictionary = {} # Button -> true/false/null(未套用或已清)

func _set_afford_color(btn: Button, affordable: bool) -> void:
	if _afford_color_cache.get(btn) == affordable:
		return
	_afford_color_cache[btn] = affordable
	var color := Color(0.4, 0.9, 0.4) if affordable else Color(0.95, 0.35, 0.3)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_disabled_color", color)

func _clear_afford_color(btn: Button) -> void:
	if _afford_color_cache.get(btn) == null:
		return
	_afford_color_cache[btn] = null
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

extends Resource
class_name GameConstants

## Junkpile Tycoon 數值總表（VR-02，來源：VEIN-RUSH-內容總結.docx + ALTA-149 規格留言）。
##
## 標記：
##   docx = docx 已定案數值／行為，唔准改
##   TUNE = docx 冇寫，Coder 定嘅預設值；上架後遠端設定（VR-08）可覆寫
##
## 用法：GameConstants.new() 攞預設值。遠端設定覆寫（VR-08，見
## systems/remote_constants.gd + worker/）淨係將 REMOTE_TUNABLE_FIELDS
## 白名單入面嘅欄位用 set() 覆寫喺同一個個體度，所有取值／計算一律經由
## 呢個個體嘅方法或屬性，唔好假設呢度係常數（const）唔會變。

const SAVE_KEY := "junkpile-save-v1" # docx：存檔鍵（原 vein-rush-save-v1 改名）

# ══════════════════════ A. docx 已定案（唔准改動）══════════════════════

## -- A1. 三資源 --
enum Resource3 { CASH, COMPONENTS, ECO }

@export var trash_meter_cap: int = 20 # docx：Trash Meter 上限，貨跌落坑唔計分

## -- A2. 礦物階價值 --
@export var ore_tier_value: Dictionary = {
	"stone": 1, "coal": 2, "copper": 4, "gold": 8, "diamond": 18, "crown": 40,
} # docx：石頭1／煤炭2／銅4／金8／鑽18／皇冠40

## -- A3. 場地座標（世界單位）--
@export var site_foothill_pos: Vector2 = Vector2(0.85, 0.72)  # docx：山腳，初始
@export var site_mid_pos: Vector2 = Vector2(0.52, 2.18)       # docx：中層，解鎖 1
@export var site_upper_pos: Vector2 = Vector2(0.28, 3.48)     # docx：上層，解鎖 2
@export var car_park_max_y: float = 0.08                      # docx：車場上限，車唔上山
@export var belt_head_pos: Vector2 = Vector2(0.85, -0.05)     # docx：單一入口
@export var smelter_pos: Vector2 = Vector2(1.85, -1.55)       # docx
@export var warehouse_pos: Vector2 = Vector2(1.85, -2.18)     # docx

@export var screen_aspect: Vector2 = Vector2(3.0, 4.0) # docx：畫面 3:4
@export var screen_kx: float = 0.82  # docx
@export var screen_ky: float = 0.40  # docx
@export var screen_cy: float = 0.52  # docx
## docx §6：正交相機約 55°／45°，即斜視 2.5D——用戶實機回饋（ALTA-150）
## 見場景之前用 rotation=0（正面平視），BoxMesh 睇落係死板 2D 色塊，
## 冚返呢兩個角度先睇到盒仔側面／立體感。
@export var screen_camera_pitch_deg: float = -55.0 # docx
@export var screen_camera_yaw_deg: float = 45.0    # docx
@export var hud_top: int = 12    # docx
@export var hud_mid: int = 66    # docx
@export var hud_bottom: int = 22 # docx

## -- A4. 帶升級（接通後層 / 統一回收）--
@export var belt_connect_lv: Dictionary = {"east": 1, "mid": 5, "west": 10} # docx：東／中／西接通等級
@export var belt_collect_lv: int = 8 # docx：後層碎料一齊送回收；已 belted 碎料不可 scoop

## -- A5. 倍數門（y ≈ -1.08）--
@export var gate_y: float = -1.08 # docx
@export var gates: Dictionary = {
	"main": {"x": -0.55, "mult": 2.0},
	"mid": {"x": 0.85, "mult": 3.0},
	"west": {"x": 1.85, "mult": 4.0},
	"peak": {"x": 1.85, "y": -1.72, "mult": 5.0},
} # docx

## -- A6. 半自動升級 --
@export var miner_summon_cap: int = 12 # docx：召喚礦工上限
@export var manager_card_cost: Dictionary = {"shaft": 450, "lift": 900, "store": 1400} # docx
@export var frenzy_merge_disabled_during: bool = true # docx：狂熱期間合併關閉

# ══════════════ B. 數值規格 v2（留存導向，2026-09-12，全部 TUNE）══════════════
# 取代原 B 部（v1）。狂熱改用放置收入公式＋免費冷卻觸發，唔再係固定 COST。
# 全部標 TUNE，日後遠端設定可覆寫。

## -- 放置收入基礎 --
@export var ore_rate_per_miner: float = 0.5 # TUNE：每礦工每秒出礦（ore/s）

@export var ore_distribution: Dictionary = {
	"foothill": {"stone": 0.6, "coal": 0.3, "copper": 0.1},
	"mid": {"coal": 0.4, "copper": 0.4, "gold": 0.2},
	"upper": {"gold": 0.5, "diamond": 0.4, "crown": 0.1},
} # TUNE：各層礦物階分佈

## -- 礦工：召喚（上限 miner_summon_cap） --
@export var miner_cost_base: float = 15.0 # TUNE：召喚第 n 隻 = base × mult^(n-1)
@export var miner_cost_mult: float = 1.4  # TUNE

## 開場資金——用戶實機回饋（ALTA-150，2026-09-12）：開場 Cash 0 < 第一個
## 礦工價 15，冇初始礦工之下要撳好多下碎料先買到，違反首節腳本
## 「~20s 第一個礦工」。改為開場 Cash 直接等如第一個礦工價，令玩家一
## 開場撳「召喚礦工」就買得到，20 秒內完成首次購買。
@export var starting_cash: float = miner_cost_base # TUNE

## -- 礦工等級（無上限線，取代舊版召喚價曲線嘅定位）--
@export var miner_level_cost_base: float = 25.0  # TUNE：第 n 級價 = base × mult^n
@export var miner_level_cost_mult: float = 1.20  # TUNE
@export var miner_level_speed_mult: float = 1.08 # TUNE：每級速度倍率

## -- 帶：產能上限 + 升級價 --
@export var belt_cap_lv1: float = 2.5    # TUNE：Lv1 產能上限（ore/s）
@export var belt_step: float = 0.25      # TUNE：每級 +25%
@export var belt_level_cap: int = 10     # TUNE：Lv10 上限
@export var belt_cost_base: float = 60.0 # TUNE：第 n 級價 = base × mult^(n-1)
@export var belt_cost_mult: float = 1.5  # TUNE

## -- 精煉等級（無上限線，取代「爐升級」；爐本身唔限流）--
@export var refine_cost_base: float = 300.0 # TUNE：第 n 級價 = base × mult^n
@export var refine_cost_mult: float = 1.7   # TUNE
@export var refine_value_mult: float = 1.12 # TUNE：每級礦值倍率

## -- 狂熱（v2：放置收入 ×5 ×120s，免費觸發，10 分鐘冷卻）--
@export var frenzy_duration_secs: float = 120.0      # TUNE
@export var frenzy_mult: float = 5.0                 # TUNE
@export var frenzy_cooldown_secs: float = 600.0      # TUNE：一般冷卻 10 分鐘
@export var frenzy_first_cooldown_secs: float = 90.0 # TUNE：首次冷卻縮短
@export var gear_drop_interval_secs: float = 8.0     # TUNE：狂熱期間每 8 秒 1 粒閃齒輪
@export var frenzy_manual_eff: float = 1.0           # TUNE：狂熱期間玩家推堆效率＝放置收入，VR-04 實測後調

## -- Eco --
@export var eco_gain_hazard_per_item: float = 1.0     # TUNE：高危廢料入爐每粒
@export var eco_gain_perfect_sort_bonus: float = 10.0 # TUNE：狂熱 120 秒零掉坑
@export var eco_gain_daily_goal_bonus: float = 5.0    # TUNE：每日目標每條

## -- 主戰車 / 碎片 --
@export var car_capacity: int = 30          # TUNE
@export var car_speed: float = 3.0          # TUNE
@export var debris_rigidbody_cap: int = 300 # TUNE：VR-04 實機（S8+，bench/fps_bench.tscn）100/200/300 平均 60.8/60.8fps、最低 58–59fps 全部 ≥40fps 門檻，見留言報告
@export var ai_driver_eff: float = 0.4      # TUNE：AI 司機效率，差過玩家（docx 只講質性描述）

## -- 溢滿條 --
@export var trash_meter_decay_per_sec: float = -1.0 # TUNE：回落速率（上限 20 為 docx）

## -- 離線公式（v2：0–2h／2–6h／6–8h，上限 8h）--
@export var offline_bands: Array[Dictionary] = [
	{"duration_secs": 7200.0, "rate": 1.0},  # 0–2h：100%
	{"duration_secs": 14400.0, "rate": 0.7}, # 2–6h：70%
	{"duration_secs": 7200.0, "rate": 0.4},  # 6–8h：40%
] # TUNE
@export var offline_cap_secs: float = 28800.0  # TUNE：牆鐘上限 8 小時（= bands 總和）
@export var offline_min_gap_secs: float = 30.0 # TUNE：極短空隙門檻，< 30 秒當 0

## -- 層解鎖（第一版顯示鎖住 + 價錢，唔開放）--
@export var unlock_mid_price: float = 2000000.0    # TUNE
@export var unlock_upper_price: float = 30000000.0 # TUNE

## -- 威望重置（拆廠搬礦）--
@export var prestige_base: float = 15000000.0     # TUNE：門檻 = base × growth^n
@export var prestige_growth: float = 6.0          # TUNE
@export var prestige_bonus_per_reset: float = 0.5 # TUNE：永久 +50% 收入／次

## -- Rewarded 廣告額度 --
@export var rewarded_offline_x2_per_day: int = 3   # TUNE
@export var rewarded_extra_frenzy_per_day: int = 2 # TUNE


# ══════════════ C. VR-03 放置場灰模：視覺／節奏（TUNE）══════════════
# 淨係影響場景視覺同手動 scoop 節奏，唔影響任何價格曲線／收益公式。

@export var pile_debris_spawn_interval_secs: float = 2.5 # TUNE：山腳每幾耐生一粒可剷碎料
@export var belt_visual_travel_secs: float = 3.0          # TUNE：帶上碎料由 BELT_HEAD 行到 SMELTER 嘅視覺時間


# ══════════════ D. VR-04 狂熱車場：物件／關卡數值（全部 TUNE） ══════════════
# docx 對呢張只有質性描述（跟指、剷斗剛體堆、刺滾筒、UPGRADE 墊、窄岩浆＋
# 木橋，見附件），冇實數；場地座標／gates／frenzy_* 已經喺 A5／B 部定咗，
# 呢度淨係補返場景擺位同物件數值。跟 gate_y／gates／car_park_max_y 同一個
# 世界座標系（同放置場共用一個 3D world，門盡頭即係 smelter_pos 附近）。

## -- 車場範圍 --
## 設計取態（docx 冇實數，淨係質性描述，見 frenzy_yard_view.gd 開頭
## 註解）：car_park_max_y 讀做「車 y 嘅上限」，車由呢度開始不斷向落
## （+car_descent_speed）掃落成個車場，中途經過滾筒／木橋／四道門，
## 去到 yard_min_y 一輪completed 就返回頂再落——即「不斷落嚟緊嘅
## 剷斗」，唔係揸住車留喺頂。呢個先解釋到點解木橋／滾筒都要車親身
## 經過（唔即死＝車跌落岩浆唔會令狂熱完場，只加溢滿）。
@export var yard_x_range: Vector2 = Vector2(-1.1, 2.3) # TUNE：跟指橫向可去嘅範圍，包晒四道門 x
@export var yard_min_y: float = -1.9                   # TUNE：車場最深（近爐前），碎料過咗呢度即入爐兌現
@export var yard_spawn_y: float = 0.02                 # TUNE：車＋碎料初始生成 y（< car_park_max_y）
@export var car_descent_speed: float = 0.4             # TUNE：車向落嘅巡航速度，去到 yard_min_y 即刻返頂再落

## -- 散幣／藍波（車場入面被推嘅剛體） --
@export var scrap_coin_value: float = 2.0      # TUNE：散幣基礎值
@export var scrap_barrel_value: float = 1.0    # TUNE：藍波基礎值（未過刺滾筒），故意平過散幣
@export var scrap_gold_value: float = 6.0      # TUNE：藍波過咗刺滾筒轉做金幣之後嘅值
@export var barrel_spawn_ratio: float = 0.35   # TUNE：生成池入面藍波佔比，其餘係散幣
@export var debris_spawn_interval_secs: float = 0.08 # TUNE：狂熱期間隔幾耐生一粒新碎料（未撞 cap 先生）
@export var debris_fake_fall_speed: float = 1.4      # TUNE：假物理（位置插值）落速，低階機用嚟代替剛體
@export var debris_gravity_scale: float = 0.12       # TUNE：實機 playtest 發現預設重力（9.8）跌 spawn_y→yard_min_y 成個車場淨使 <1s，車追唔切；夾細落速等剛體有時間畀車撞／過滾筒／過門

## -- 刺滾筒（藍波 → 金幣） --
@export var spike_roller_pos: Vector2 = Vector2(0.65, -0.5)            # TUNE
@export var spike_roller_half_extents: Vector3 = Vector3(0.5, 0.3, 0.25) # TUNE

## -- 窄岩浆 + 木橋（車跌落唔即死，只加溢滿；溢滿上限見 A1 trash_meter_cap） --
@export var lava_bridge_y: float = -0.78                        # TUNE
@export var lava_bridge_safe_x_range: Vector2 = Vector2(-0.22, 0.22) # TUNE：木橋安全闊度
@export var lava_fall_overflow_amount: float = 6.0              # TUNE：跌一次溢滿條加幾多
@export var lava_fall_stun_secs: float = 0.6                    # TUNE：跌落之後車短暫定住先返回橋面

## -- UPGRADE 墊（即換模型，灰模用色塊／大細分身分，冇實際換 mesh） --
@export var upgrade_pad_pos: Vector2 = Vector2(-0.9, -0.95) # TUNE
@export var upgrade_pad_rearm_secs: float = 6.0             # TUNE：同一墊重複觸發嘅冷卻
@export var car_upgrade_tiers: Array[Dictionary] = [
	{"name": "拖拉機", "scale": 1.0, "speed_mult": 1.0, "push_mult": 1.0, "color": Color(0.55, 0.15, 0.15)},
	{"name": "剷泥車", "scale": 1.15, "speed_mult": 1.15, "push_mult": 1.3, "color": Color(0.75, 0.55, 0.1)},
	{"name": "裝甲車", "scale": 1.3, "speed_mult": 1.3, "push_mult": 1.7, "color": Color(0.35, 0.55, 0.75)},
] # TUNE：UPGRADE 墊逐級升嘅三級

## -- 齒輪（狂熱期間每 gear_drop_interval_secs 一粒，只計玩家親手攔截） --
@export var gear_component_reward: float = 1.0   # TUNE：每粒齒輪兌 Components
@export var gear_pickup_window_secs: float = 4.0 # TUNE：粒齒輪冇喺呢段時間內截到就消失，唔計分

## -- 幀數自動降級 --
## S8+ 實機 bench/fps_bench.tscn 報告（見留言）：100/200/300 個碎片
## 剛體平均 fps 分別係 57.6／60.8／60.8，最低 fps 58–59（100 嗰組首
## 1 秒 warmup 之後見過一次 1.0fps 嘅離群值，懷疑係首次生成嗰刻嘅
## GC／shader compile 一次性 hitch，200／300 兩組冇再見過，唔計入
## 「持續」低幀）。三組全部遠高於 40fps 門檻，所以 debris_rigidbody_cap
## 定 300（見上面）；降級梯度留返做真正落場（HUD／belt tween／齒輪／
## 滾筒轉動一齊跑）嗰陣嘅安全網，唔係跟返 bench 嗰三個純剛體數。
@export var frenzy_fps_sample_interval_secs: float = 1.0 # TUNE：隔幾耐取樣一次 fps
@export var frenzy_fps_low_threshold: float = 40.0       # TUNE：docx 驗收線（< 40fps 自動減粒子／碎片）
@export var frenzy_fps_low_streak_to_degrade: int = 2    # TUNE：連續幾多次低於門檻先降級，避免單幀抖動
@export var frenzy_debris_degrade_steps: Array[int] = [200, 100, 50] # TUNE：debris_rigidbody_cap（tier 0＝300）之後逐級降嘅上限
@export var frenzy_fake_physics_min_tier: int = 3 # TUNE：跌到呢一級（0=debris_rigidbody_cap，1..=frenzy_debris_degrade_steps）先轉用假物理（位置插值代替剛體）


# ══════════════ E. VR-08 遠端覆寫白名單（純量 TUNE 欄位） ══════════════
# 只有呢度列出嘅名先會俾 systems/remote_constants.gd 嘅 RemoteConstants
# 覆寫（型別 float／int，`set()` 直接寫喺同一個個體，見上面用法註解）。
# Dictionary／Array／Vector／Color 嘅 TUNE 欄位（ore_distribution、
# offline_bands、yard_x_range、spike_roller_pos、spike_roller_half_extents、
# lava_bridge_safe_x_range、upgrade_pad_pos、car_upgrade_tiers、
# frenzy_debris_degrade_steps）呢期未支援遠端覆寫——結構化覆寫要另外
# 設計 schema／夾範圍，超出呢個 issue 範圍，維持本機預設。
#
# ⚠️ test/test_constants_remote_tunable.gd 會掃描呢個檔案嘅 `# TUNE`
# 純量欄位，同呢個名單逐一對數——加／刪一個純量 TUNE 欄位都要同步改呢度，
# 唔係就測試會 fail（防止漏咗白名單或者漏咗清走已刪走嘅欄位）。
const REMOTE_TUNABLE_FIELDS: Array[String] = [
	"ore_rate_per_miner", "miner_cost_base", "miner_cost_mult", "starting_cash",
	"miner_level_cost_base", "miner_level_cost_mult", "miner_level_speed_mult",
	"belt_cap_lv1", "belt_step", "belt_level_cap", "belt_cost_base", "belt_cost_mult",
	"refine_cost_base", "refine_cost_mult", "refine_value_mult", "frenzy_duration_secs",
	"frenzy_mult", "frenzy_cooldown_secs", "frenzy_first_cooldown_secs",
	"gear_drop_interval_secs", "frenzy_manual_eff", "eco_gain_hazard_per_item",
	"eco_gain_perfect_sort_bonus", "eco_gain_daily_goal_bonus", "car_capacity", "car_speed",
	"debris_rigidbody_cap", "ai_driver_eff", "trash_meter_decay_per_sec",
	"offline_cap_secs", "offline_min_gap_secs", "unlock_mid_price", "unlock_upper_price",
	"prestige_base", "prestige_growth", "prestige_bonus_per_reset",
	"rewarded_offline_x2_per_day", "rewarded_extra_frenzy_per_day",
	"pile_debris_spawn_interval_secs", "belt_visual_travel_secs", "yard_min_y",
	"yard_spawn_y", "car_descent_speed", "scrap_coin_value", "scrap_barrel_value",
	"scrap_gold_value", "barrel_spawn_ratio", "debris_spawn_interval_secs",
	"debris_fake_fall_speed", "debris_gravity_scale", "lava_bridge_y",
	"lava_fall_overflow_amount", "lava_fall_stun_secs", "upgrade_pad_rearm_secs",
	"gear_component_reward", "gear_pickup_window_secs", "frenzy_fps_sample_interval_secs",
	"frenzy_fps_low_threshold", "frenzy_fps_low_streak_to_degrade",
	"frenzy_fake_physics_min_tier",
]


# ══════════════════════════ 計算方法 ══════════════════════════

## 離線收益：banded yield + 回撥保護（elapsed < 0 → 0）+ 極短空隙保護
## （elapsed < offline_min_gap_secs → 0）+ 牆鐘上限（offline_cap_secs）。
## 唔模擬穿門物理，唔用剩餘狂熱 ×2 成段。
func compute_offline_yield(base_rate_per_sec: float, elapsed_secs: float) -> float:
	if elapsed_secs < 0.0:
		return 0.0 # 回撥當 0
	if elapsed_secs < offline_min_gap_secs:
		return 0.0 # 極短空隙當 0
	var remaining: float = minf(elapsed_secs, offline_cap_secs)
	var total := 0.0
	for band: Dictionary in offline_bands:
		var band_secs: float = minf(remaining, band["duration_secs"])
		total += band_secs * band["rate"] * base_rate_per_sec
		remaining -= band_secs
		if remaining <= 0.0:
			break
	return total

## 單一門嘅倍數；查唔到嘅門名回傳 1.0（冇效果）。
func gate_multiplier(gate_id: String) -> float:
	var gate: Dictionary = gates.get(gate_id, {})
	return gate.get("mult", 1.0)

## 連續過幾道門，倍數相乘（例如 main → mid = ×2 × ×3 = ×6）。
func combined_gate_multiplier(gate_ids: Array) -> float:
	var result := 1.0
	for gate_id in gate_ids:
		result *= gate_multiplier(gate_id)
	return result

## 召喚第 n 隻礦工嘅價錢（n 由 1 開始；上限見 miner_summon_cap）。
func miner_summon_cost(n: int) -> float:
	return miner_cost_base * pow(miner_cost_mult, n - 1)

## 礦工等級（無上限）第 n 級升級價。
func miner_level_cost(n: int) -> float:
	return miner_level_cost_base * pow(miner_level_cost_mult, n)

## 精煉等級（無上限）第 n 級升級價。
func refine_level_cost(n: int) -> float:
	return refine_cost_base * pow(refine_cost_mult, n)

## 帶升級（Lv1~belt_level_cap）第 n 級價錢。
func belt_upgrade_cost(n: int) -> float:
	return belt_cost_base * pow(belt_cost_mult, n - 1)

## 帶 Lv n（夾在 1~belt_level_cap 之間）嘅產能上限（ore/s）。
func belt_capacity_at_level(n: int) -> float:
	var lvl: int = clampi(n, 1, belt_level_cap)
	return belt_cap_lv1 * pow(1.0 + belt_step, lvl - 1)

## 第 n 次威望重置門檻（n 由 0 開始，即第一次重置用 n=0）。
func prestige_threshold(n: int) -> float:
	return prestige_base * pow(prestige_growth, n)

## 解鎖層價錢；layer 係 "mid" 或 "upper"，其餘回傳 0。
func unlock_price(layer: String) -> float:
	match layer:
		"mid":
			return unlock_mid_price
		"upper":
			return unlock_upper_price
		_:
			return 0.0

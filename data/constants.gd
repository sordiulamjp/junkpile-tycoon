extends Resource
class_name GameConstants

## Junkpile Tycoon 數值總表（VR-02，來源：VEIN-RUSH-內容總結.docx + ALTA-149 規格留言）。
##
## 標記：
##   docx = docx 已定案數值／行為，唔准改
##   TUNE = docx 冇寫，Coder 定嘅預設值；上架後遠端設定（VR-08）可覆寫
##
## 用法：GameConstants.new() 攞預設值。遠端設定覆寫時載入同結構嘅
## GameConstants 執行個體（例如覆寫過 @export 欄位嘅 .tres），所有取值／
## 計算一律經由呢個個體嘅方法或屬性，唔好假設呢度係常數（const）唔會變。

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

## -- Eco --
@export var eco_gain_hazard_per_item: float = 1.0     # TUNE：高危廢料入爐每粒
@export var eco_gain_perfect_sort_bonus: float = 10.0 # TUNE：狂熱 120 秒零掉坑
@export var eco_gain_daily_goal_bonus: float = 5.0    # TUNE：每日目標每條

## -- 主戰車 / 碎片 --
@export var car_capacity: int = 30          # TUNE
@export var car_speed: float = 3.0          # TUNE
@export var debris_rigidbody_cap: int = 150 # TUNE：待 VR-04 實測
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

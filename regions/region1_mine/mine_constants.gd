extends Resource
class_name MineConstants

## ALTA-228（VR-12）區域 1 礦坑數值表。
##
## 抄 GameConstants（data/constants.gd）嘅曲線風格套用落三段：
##   礦層開採速度 → 抄 miner_level 曲線（無上限，速度乘倍率／級）
##   升降機運載   → 抄 belt 曲線（capacity，Lv1~cap 封頂）
##   倉庫收集     → 抄 belt 曲線（capacity，Lv1~cap 封頂）
## ore_tier_value 跟 GameConstants 同一套數值（docx：石1／煤2／銅4／
## 金8／鑽18／皇冠40），呢度重覆一份而唔係 import GameConstants，係因為
## 呢個區域仲未經 VR-11 接落共用 autoload，故意唔拉跨區域依賴（見
## regions/region1_mine/region1_mine.gd 頂部註解）。
##
## 全部 TUNE（呢張 issue 冇 docx 數值可跟，Coder 定嘅預設值，日後可調）。

@export var ore_tier_value: Dictionary = {
	"stone": 1, "coal": 2, "copper": 4, "gold": 8, "diamond": 18, "crown": 40,
}

## 礦層 1–3 各自嘅礦物分佈（issue 明文：層1 石／煤、層2 銅／金、層3 鑽／皇冠）。
## 索引 0..2 對應礦層 1..3。層 4 未開放採礦，冇分佈。
@export var layer_ore_distribution: Array[Dictionary] = [
	{"stone": 0.6, "coal": 0.4},
	{"copper": 0.6, "gold": 0.4},
	{"diamond": 0.6, "crown": 0.4},
]

## 開場已解鎖礦層數——issue 驗收「3 層全開」，層 1–3 由開場已經可採，
## 淨係層 4 鎖住（見 layer4_unlock_price）。
const UNLOCKED_LAYER_COUNT := 3

## -- 礦層 4：鎖住顯示解鎖價（呢期唔開放購買，見 region1_mine.gd） --
@export var layer4_unlock_price: float = 8000000.0

## -- 礦層開採速度（每層獨立等級，無上限，抄 miner_level 曲線） --
@export var layer_base_rate: float = 0.6         # TUNE：Lv0 每層 ore/s
@export var layer_level_speed_mult: float = 1.08 # TUNE：每級速度倍率
@export var layer_level_cost_base: float = 20.0  # TUNE：第 n 級價 = base × mult^n（n 由 0 開始）
@export var layer_level_cost_mult: float = 1.20  # TUNE

## -- 升降機：運載量／速度（capacity 曲線，抄 belt，Lv1~cap 封頂） --
@export var elevator_cap_lv1: float = 1.8   # TUNE：Lv1 運載上限（ore/s）
@export var elevator_step: float = 0.25     # TUNE：每級 +25%
@export var elevator_level_cap: int = 10    # TUNE：Lv10 封頂
@export var elevator_cost_base: float = 50.0 # TUNE：第 n 級價 = base × mult^(n-1)
@export var elevator_cost_mult: float = 1.5  # TUNE

## -- 倉庫：收集速度（capacity 曲線，抄 belt，Lv1~cap 封頂） --
@export var warehouse_cap_lv1: float = 1.5    # TUNE
@export var warehouse_step: float = 0.22      # TUNE
@export var warehouse_level_cap: int = 10     # TUNE
@export var warehouse_cost_base: float = 40.0 # TUNE
@export var warehouse_cost_mult: float = 1.45 # TUNE

## -- 三段未平衡嘅緩衝上限（issue：「升降機慢→礦塞地底，地面慢→升降機停」）--
## 地底排隊（已採出但升降機未搬走）爆咗即「塞爆」，超出嘅份量截斷唔採
## （underground_backlog 夾喺 0~cap，唔會無限疊）。
@export var underground_backlog_cap: float = 40.0
## 升降機運到地面等緊倉庫收嘅緩衝，爆咗即升降機冇位再落嚟接，等於停運。
@export var ground_backlog_cap: float = 30.0

## 開場資金＝三段第一級升級入面最平嗰個（呢度即 layer_level_cost_base，
## 20 < elevator_cost_base 50 < warehouse_cost_base 40）；跟 GameConstants
## starting_cash 嘅做法（ALTA-150 實機回饋：開場即夠買一個升級，
## 20 秒內完成首次購買）。
@export var starting_cash: float = minf(minf(layer_level_cost_base, elevator_cost_base), warehouse_cost_base)


# ══════════════════════════ 計算方法 ══════════════════════════

## 礦層 n（第 n 級，由 0 開始）出礦速度（ore/s）。
func layer_rate_at_level(level: int) -> float:
	return layer_base_rate * pow(layer_level_speed_mult, level)

## 礦層升到 level+1 嘅價錢（level 係升級前嘅現有等級）。
func layer_level_cost(level: int) -> float:
	return layer_level_cost_base * pow(layer_level_cost_mult, level)

## 升降機 Lv n（夾喺 1~elevator_level_cap）嘅運載上限（ore/s）。
func elevator_capacity_at_level(n: int) -> float:
	var lvl: int = clampi(n, 1, elevator_level_cap)
	return elevator_cap_lv1 * pow(1.0 + elevator_step, lvl - 1)

## 升降機由 Lv n 升到 n+1 嘅價錢。
func elevator_upgrade_cost(n: int) -> float:
	return elevator_cost_base * pow(elevator_cost_mult, n - 1)

## 倉庫 Lv n（夾喺 1~warehouse_level_cap）嘅收集上限（ore/s）。
func warehouse_capacity_at_level(n: int) -> float:
	var lvl: int = clampi(n, 1, warehouse_level_cap)
	return warehouse_cap_lv1 * pow(1.0 + warehouse_step, lvl - 1)

## 倉庫由 Lv n 升到 n+1 嘅價錢。
func warehouse_upgrade_cost(n: int) -> float:
	return warehouse_cost_base * pow(warehouse_cost_mult, n - 1)

## 礦層 idx（0..2）嘅平均礦值（未經任何倍率），揾唔到就 0。
func layer_average_ore_value(idx: int) -> float:
	if idx < 0 or idx >= layer_ore_distribution.size():
		return 0.0
	var dist: Dictionary = layer_ore_distribution[idx]
	var total := 0.0
	for ore_key: String in dist:
		var weight: float = dist[ore_key]
		var value: float = ore_tier_value.get(ore_key, 0)
		total += weight * value
	return total

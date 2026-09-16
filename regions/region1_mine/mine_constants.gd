extends Resource
class_name MineConstants

## ALTA-228（VR-12）區域 1（開場）場內礦坑數值表。
##
## Reviewer round 1 修正（2026-09-14）：跟返 Analyst 16:48「區域 1 規格
## （用戶決定：A+B；開場 1 層開 2 層鎖；色調跟 IG）」留言，取代第一版
## （獨立場景、3 層全開、自成一格 cash）嘅舊設計。「同一場地，由下向上
## 擴張」（VR-11／ALTA-227，唔係獨立場景）——呢個 class 純粹係數值表，
## 唔擁有 Cash：夠唔夠錢、扣邊個欄位由呼叫方（regions/region1_mine/
## mine_zone.gd）用 GameState.cash（main.gd 揸嘅共用錢包）決定，跟
## systems/unlock_panel.gd 同一分工（該檔案頂部註解解釋咗點解要咁分）。

## -- 色調（IG 廣告 DdEYh2HMRW1，用戶 2026-09-14 決定） --
const PALETTE := {
	"wall": "#7A4AB0", "wall_light": "#9A62C8", "wall_dark": "#5E3A8C",
	"ground": "#5C5060",
	"layer1": "#8C7A6A", "layer2": "#5A4636", "layer3": "#3A2A44",
	"ore_silver": "#C9CFD6", "ore_gold": "#F2B830",
	"pad": "#6E3CA0", "shovel_preview": "#B4E1F0",
	"furnace": "#2E2E33", "furnace_fire": "#FF7A1E",
}

const LAYER_COUNT := 3
## 礦層幾何（issue：層 1 最前最低、高 0.35；層 2／3 各向後退 0.9、各 +0.35 高）。
const LAYER_HEIGHT_STEP := 0.35
const LAYER_DEPTH_STEP := 0.9

## -- 層解鎖：層 1 開場已開（cost=0，唔使解鎖），層 2／3 鎖住，撳
## UnlockPanel 買（一定要順序解鎖，唔可以跳層 2 直接解鎖層 3）。 --
@export var layer_unlock_cost: Array[float] = [0.0, 250.0, 1200.0] # TUNE
@export var layer_unlock_ore: Array[float] = [0.0, 80.0, 300.0]     # TUNE：礦料成本（用戶 2026-09-17：部分升級要礦料）

## -- 每層開採速度（每層獨立等級，無上限，抄 miner_level 曲線） --
@export var layer_base_rate: float = 0.6         # TUNE：Lv0 每層 ore/s
@export var layer_level_speed_mult: float = 1.08 # TUNE
@export var layer_level_cost_base: float = 20.0  # TUNE：第 n 級價 = base × mult^n（n 由 0 開始）
@export var layer_level_cost_mult: float = 1.20  # TUNE

## -- 礦車路軌運載（issue 標題：「礦車＝升降機」，即原設計嘅運載段，
## 抄 belt capacity 曲線，Lv1~cap 封頂） --
@export var cart_cap_lv1: float = 1.8    # TUNE
@export var cart_step: float = 0.25      # TUNE
@export var cart_level_cap: int = 10     # TUNE
@export var cart_cost_base: float = 50.0 # TUNE
@export var cart_cost_mult: float = 1.5  # TUNE
@export var cart_ore_per_level: float = 12.0 # TUNE：礦車每級礦料成本 = 12 × 目標等級

## -- 倉庫收集（＝地面收集，抄 belt 曲線） --
@export var warehouse_cap_lv1: float = 1.5    # TUNE
@export var warehouse_step: float = 0.22      # TUNE
@export var warehouse_level_cap: int = 10     # TUNE
@export var warehouse_cost_base: float = 40.0 # TUNE
@export var warehouse_cost_mult: float = 1.45 # TUNE

## -- 三段未平衡嘅緩衝上限（issue：「升降機慢→礦塞地底，地面慢→升降機停」，
## 呢版即「礦車慢→礦塞層台，倉庫慢→礦車停」） --
@export var underground_backlog_cap: float = 40.0
@export var ground_backlog_cap: float = 30.0

## -- 地面礦堆（issue：「礦粒瀉落地面成堆（銀多金少）」） --
@export var ore_value_silver: float = 3.0            # TUNE
@export var ore_value_gold: float = 9.0              # TUNE
@export var pile_silver_ratio: float = 0.75          # TUNE：堆入面銀嘅比例，其餘金
@export var pile_spawn_interval_secs: float = 3.0    # TUNE
@export var pile_cap: int = 16                        # TUNE：地面堆未撿上限，避免場景無限脹

## -- 推堆墊（issue：150 鏟斗／500 熔爐賣礦／1000 大鏟斗，逐級加 tap
## 收礦倍率；跟現有 car_upgrade_tiers 風格，但呢度用 Cash 買唔係免費
## 駛過） --
@export var push_tier_cost: Array[float] = [150.0, 500.0, 1000.0]     # TUNE
@export var push_tier_ore: Array[float] = [0.0, 60.0, 150.0]          # TUNE：鏟斗 tier 礦料成本
@export var push_tier_scoop_mult: Array[float] = [1.0, 1.8, 3.0]      # TUNE
@export var push_tier_names: Array[String] = ["鏟斗", "熔爐賣礦", "大鏟斗"]

## -- 狂熱（issue：「沿用 FrenzyState」——唔開獨立計時器，直接讀 main.gd
## 現有嘅 frenzy.active，狂熱期間撳礦堆值 ×frenzy_income_mult，跟現有
## GameConstants.frenzy_mult 同一數量級） --
@export var frenzy_income_mult: float = 5.0 # TUNE


# ══════════════════════════ 計算方法 ══════════════════════════

func layer_rate_at_level(level: int) -> float:
	return layer_base_rate * pow(layer_level_speed_mult, level)

func layer_level_cost(level: int) -> float:
	return layer_level_cost_base * pow(layer_level_cost_mult, level)

func cart_capacity_at_level(n: int) -> float:
	var lvl: int = clampi(n, 1, cart_level_cap)
	return cart_cap_lv1 * pow(1.0 + cart_step, lvl - 1)

func cart_upgrade_cost(n: int) -> float:
	return cart_cost_base * pow(cart_cost_mult, n - 1)

func warehouse_capacity_at_level(n: int) -> float:
	var lvl: int = clampi(n, 1, warehouse_level_cap)
	return warehouse_cap_lv1 * pow(1.0 + warehouse_step, lvl - 1)

func warehouse_upgrade_cost(n: int) -> float:
	return warehouse_cost_base * pow(warehouse_cost_mult, n - 1)

## ore_key："silver" 或 "gold"，其餘回傳 0。
func ore_value(ore_key: String) -> float:
	match ore_key:
		"silver":
			return ore_value_silver
		"gold":
			return ore_value_gold
		_:
			return 0.0

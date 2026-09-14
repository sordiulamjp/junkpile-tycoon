extends Resource
class_name Region2Constants

## ALTA-229（VR-13）區域 2「外圍險路」數值表。
##
## PLAN v3（parent ALTA-147，用戶 2026-09-14 拍板合併為 2 區）：由「200」
## 紫色解鎖板（main.gd `_region2_panel`，VR-11 已起）進入，一條環繞區域 1
## 上方嘅路——左邊車道向上串聯 ×2→×3→×4 發光透明板（倍數相乘）、灰磚牆
## （撞爛先過，×3 後先夠力）；頂部轉右一條金河，外側岩浆，中段 100 lb
## 木橋限重（超重斷橋）；路尾 ×5 板 → 礦站（賣出倍數後嘅礦，比熔爐賺
## 多），沿路 UPGRADE 小屋 200／500。
##
## 跟 regions/region1_mine/mine_constants.gd 同一分工：呢個 class 純粹係
## 數值表，唔擁有 Cash——夠唔夠錢、扣邊個欄位由呼叫方（region2_zone.gd）
## 對住 GameState.cash 決定。冇註冊落 GameConstants.REMOTE_TUNABLE_FIELDS
## （VR-08 遠端覆寫淨係管 GameConstants，MineConstants／呢個都係跟本機
## 預設，同 mine_constants.gd 頂部註解一致）。

## -- 色調（issue：門道段紫岩、金河段紅啡岩 + 岩浆） --
const PALETTE := {
	"gate_pass": "#7A4AB0", "gate_pass_dark": "#5E3A8C",
	"gate_glow": "#B47CF0", # ×2／×3／×4／×5 發光透明板嘅發光色
	"brick_wall": "#8C7A6A", "brick_rubble": "#5A4636",
	"river_gold": "#D9A63C", "river_bed": "#6B4A3A",
	"lava": "#FF5A1F",
	"bridge_wood": "#8B5A2B",
	"station": "#5E3A8C", "station_roof": "#3A2A44",
}

## -- 串聯發光倍數板（issue：×2→×3→×4，路尾再加一塊 ×5） -- TUNE
@export var gate_multipliers: Array[float] = [2.0, 3.0, 4.0, 5.0]

## -- 灰磚牆：企喺 ×3（index 1）之後、×4（index 2）之前，「×3 後撞爛
## 先過」——車攞齊 ×2／×3 已經夠衝力，唔使額外解鎖／升級先撞得爛。 --
@export var wall_break_after_gate_index: int = 1

## -- 100 lb 木橋限重（issue：超重斷橋，貨清零唔記錢） -- TUNE
@export var base_cart_weight_lb: float = 40.0
@export var ore_load_weight_lb: float = 6.0
@export var ore_load_count: int = 8
@export var bridge_weight_limit_lb: float = 100.0

## -- 礦站賣價：賣出嘅係經過哂倍數板嘅原礦，issue 明文「比熔爐賺多」
## ——`station_price_bonus_mult` 保證即使冚晒 ×2~×5 之前（gates_passed=0），
## 礦站基本price 都要好過熔爐（regions/region1_mine/mine_constants.gd
## 嘅 blended (ore_value_silver+ore_value_gold)*0.5）。 -- TUNE
@export var base_ore_value: float = 4.0
@export var station_price_bonus_mult: float = 1.6

## -- UPGRADE 小屋（issue：200／500，沿路），效果同 region1 推堆墊
## push_tier 一致風格：買咗就加成礦站賣價，唔改木橋限重（限重係場地
## 固定物理值，唔可以升級）。 -- TUNE
@export var shack_tier_cost: Array[float] = [200.0, 500.0]
@export var shack_tier_output_mult: Array[float] = [1.3, 1.8]

## -- 自動出貨週期：呢度冧「同一場地擴張」框架下嘅被動收入段，冇獨立
## 跟指車仔，一車行完全程（entrance → 4 道門 → 磚牆 → 木橋 → 礦站）
## 先自動出下一車。 -- TUNE
@export var cycle_interval_secs: float = 6.0


# ══════════════════════════ 計算方法 ══════════════════════════

## 已經連續攞咗頭 `gates_passed` 道門（0-based 累乘），第一道門未攞就
## 係 ×1（未加成）。
func multiplier_after_gates(gates_passed: int) -> float:
	var mult := 1.0
	for i in range(clampi(gates_passed, 0, gate_multipliers.size())):
		mult *= gate_multipliers[i]
	return mult

## 磚牆一定要攞齊 ×2／×3（即 `wall_break_after_gate_index + 1` 道門）
## 先夠衝力撞爛，唔可以一開場未攞任何門就撞——同 region1
## `can_unlock_layer()` 一樣嘅「一定要順序」判斷風格。
func can_break_wall(gates_passed: int) -> bool:
	return gates_passed > wall_break_after_gate_index

func cart_weight_lb() -> float:
	return base_cart_weight_lb + ore_load_weight_lb * float(ore_load_count)

func can_cross_bridge(weight_lb: float) -> bool:
	return weight_lb <= bridge_weight_limit_lb

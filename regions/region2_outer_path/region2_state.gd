extends RefCounted
class_name Region2State

## ALTA-229（VR-13）區域 2「外圍險路」核心數值狀態：自動出貨車行完
## entrance → ×2→×3→×4 門 → 磚牆 → 金河木橋 → ×5 門 → 礦站一個循環，
## 賣出嘅 Cash 由呼叫方（region2_zone.gd）加落 GameState.cash（呢個
## class 唔擁有 cash，跟 regions/region1_mine/mine_state.gd 同一分工）。
##
## 純邏輯，唔掛靠 SceneTree，方便 GUT 直接 new() 測試。

var c: Region2Constants

## UPGRADE 小屋 tier（0..c.shack_tier_cost.size()，已買咗幾多級）。
var shack_tier: int = 0

var _cycle_timer: float = 0.0
var runs_completed: int = 0
var runs_lost_to_bridge: int = 0

func _init(constants: Region2Constants = null) -> void:
	c = constants if constants != null else Region2Constants.new()


# ══════════════════════ 倍數板：相乘 ══════════════════════

func current_multiplier(gates_passed: int) -> float:
	return c.multiplier_after_gates(gates_passed)


# ══════════════════════ 灰磚牆：×3 後撞爛先過 ══════════════════════

func can_break_wall(gates_passed: int) -> bool:
	return c.can_break_wall(gates_passed)


# ══════════════════════ 100 lb 木橋：超重斷橋 ══════════════════════

func cart_weight_lb() -> float:
	return c.cart_weight_lb()

func can_cross_bridge(weight_lb: float) -> bool:
	return c.can_cross_bridge(weight_lb)


# ══════════════════════ UPGRADE 小屋（200／500） ══════════════════════

func shack_output_mult() -> float:
	if shack_tier <= 0:
		return 1.0
	return c.shack_tier_output_mult[shack_tier - 1]

func can_upgrade_shack() -> bool:
	return shack_tier < c.shack_tier_cost.size()

func next_shack_cost() -> float:
	if not can_upgrade_shack():
		return INF
	return c.shack_tier_cost[shack_tier]

func apply_shack_upgrade() -> void:
	shack_tier += 1


# ══════════════════════ 礦站：賣出倍數後嘅礦，比熔爐賺多 ══════════════════════

## base_ore_value：一份原礦嘅底值（跟 region1 嘅
## `(ore_value_silver + ore_value_gold) * 0.5` 同一量級，見
## test/test_region2_state.gd 直接同 MineConstants 對比）；gates_passed：
## 呢車行到礦站之前實際攞咗幾多道門（順序累乘，唔可以跳）。
func sell_at_station(base_ore_value: float, gates_passed: int) -> float:
	return base_ore_value * current_multiplier(gates_passed) * shack_output_mult() * c.station_price_bonus_mult


# ══════════════════════ 一次完整出貨（entrance → 礦站） ══════════════════════

## 行一次全程：呢版無隨機失敗，磚牆／全部門一定攞齊（`can_break_wall()`
## 淨係記錄「攞齊 ×2／×3 先撞得爛」呢條規則，唔會喺呢個確定性模擬入面
## 令成車停低）——真正嘅風險淨係木橋超重：唔夠秤就斷橋，貨清零、
## 呢車冇 Cash。回傳畀呼叫方（`tick()`／區域 2 場景）判斷點樣提示玩家。
func run_convoy_cycle() -> Dictionary:
	var gates_passed := c.gate_multipliers.size()
	var weight := cart_weight_lb()
	if not can_cross_bridge(weight):
		runs_lost_to_bridge += 1
		return {"cash_gain": 0.0, "bridge_broke": true, "gates_passed": gates_passed, "weight_lb": weight}
	var cash := sell_at_station(c.base_ore_value, gates_passed)
	runs_completed += 1
	return {"cash_gain": cash, "bridge_broke": false, "gates_passed": gates_passed, "weight_lb": weight}

## 每幀推進出貨週期計時器，夠鐘（`c.cycle_interval_secs`）就自動行一次
## `run_convoy_cycle()`。回傳 `cash_gain`（呼叫方自己加落 GameState.cash，
## 冇出貨嗰幀係 0）同 `cycle_completed`（畀場景決定使唔使觸發視覺／音效）。
func tick(delta: float) -> Dictionary:
	_cycle_timer += delta
	if _cycle_timer < c.cycle_interval_secs:
		return {"cash_gain": 0.0, "cycle_completed": false, "bridge_broke": false}
	_cycle_timer -= c.cycle_interval_secs
	var result := run_convoy_cycle()
	return {
		"cash_gain": result["cash_gain"], "cycle_completed": true, "bridge_broke": result["bridge_broke"],
	}

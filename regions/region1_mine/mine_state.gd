extends RefCounted
class_name MineState

## ALTA-228（VR-12）區域 1（開場）場內礦坑核心數值狀態：礦層（1 開場已
## 開，2／3 鎖住順序解鎖）→ 礦車路軌 → 倉庫 → Cash 三段管線 + 地面礦堆
## tap 收礦。
##
## Reviewer round 1 修正：呢個 class 唔再擁有 cash／starting_cash——夠唔
## 夠錢、扣邊個欄位由呼叫方（mine_zone.gd／main.gd）對住 GameState.cash
## 決定，`tick()`／`scoop_pile()` 淨係回傳「賺咗幾多」畀呼叫方自己加落
## state.cash，`apply_*_upgrade()` 淨係郁等級唔扣錢——跟 UnlockPanel
## 「顯示＋回呼，唔識錢包形狀」嘅分工一致。
##
## 純邏輯，唔掛靠 SceneTree，方便 GUT 直接 new() 測試（跟 systems/game_state.gd
## 同一風格）。

const BALANCE_TOLERANCE := 0.05 # 三段產能相差 < 5%（相對最大值）當已平衡，冇瓶頸警示

var c: MineConstants

## 層 1 開場已解鎖；層 2／3 要順序解鎖（唔可以跳層 2 解鎖層 3）。
var layer_unlocked: Array[bool] = [true, false, false]
var layer_level: Array[int] = [0, 0, 0] # 每層開採速度等級，無上限

var cart_level: int = 1      # Lv1~c.cart_level_cap
var warehouse_level: int = 1 # Lv1~c.warehouse_level_cap
var push_tier: int = 0       # 0..c.push_tier_cost.size()（已買咗幾多級鏟斗）

var underground_backlog: float = 0.0 # 已採出、等緊礦車搬嘅層台存量
var ground_backlog: float = 0.0      # 礦車搬咗、等緊倉庫收嘅地面存量

var pile_ore: Array[String] = [] # 地面礦堆未撿嘅粒（"silver" / "gold"）

func _init(constants: MineConstants = null) -> void:
	c = constants if constants != null else MineConstants.new()


# ══════════════════════ 礦層：解鎖 + 開採速度 ══════════════════════

func layer_rate(idx: int) -> float:
	if idx < 0 or idx >= layer_unlocked.size() or not layer_unlocked[idx]:
		return 0.0
	return c.layer_rate_at_level(layer_level[idx])

func total_mine_output() -> float:
	var total := 0.0
	for idx in range(layer_unlocked.size()):
		total += layer_rate(idx)
	return total

## 層 idx 嘅解鎖價；層 1（idx 0）恆常 0（已開）。
func layer_unlock_cost(idx: int) -> float:
	return c.layer_unlock_cost[idx]

func layer_unlock_ore(idx: int) -> float:
	return c.layer_unlock_ore[idx] if idx < c.layer_unlock_ore.size() else 0.0

func next_cart_ore_cost() -> float:
	return c.cart_ore_per_level * float(cart_level)

func next_push_tier_ore() -> float:
	if not can_upgrade_push_tier():
		return INF
	return c.push_tier_ore[push_tier] if push_tier < c.push_tier_ore.size() else 0.0

## 一定要順序解鎖——層 idx 要解鎖，前一層（idx-1）一定要已經解鎖咗。
func can_unlock_layer(idx: int) -> bool:
	if idx <= 0 or idx >= layer_unlocked.size():
		return false
	if layer_unlocked[idx]:
		return false
	return layer_unlocked[idx - 1]

func apply_layer_unlock(idx: int) -> void:
	layer_unlocked[idx] = true

func next_layer_speed_cost(idx: int) -> float:
	return c.layer_level_cost(layer_level[idx])

func apply_layer_speed_upgrade(idx: int) -> void:
	layer_level[idx] += 1


# ══════════════════════ 礦車路軌：運載量／速度 ══════════════════════

func cart_capacity() -> float:
	return c.cart_capacity_at_level(cart_level)

func can_upgrade_cart() -> bool:
	return cart_level < c.cart_level_cap

func next_cart_cost() -> float:
	return c.cart_upgrade_cost(cart_level)

func apply_cart_upgrade() -> void:
	cart_level += 1


# ══════════════════════ 倉庫：收集速度 ══════════════════════

func warehouse_capacity() -> float:
	return c.warehouse_capacity_at_level(warehouse_level)

func can_upgrade_warehouse() -> bool:
	return warehouse_level < c.warehouse_level_cap

func next_warehouse_cost() -> float:
	return c.warehouse_upgrade_cost(warehouse_level)

func apply_warehouse_upgrade() -> void:
	warehouse_level += 1


# ══════════════════════ 推堆墊：鏟斗 tier ══════════════════════

func can_upgrade_push_tier() -> bool:
	return push_tier < c.push_tier_cost.size()

func next_push_tier_cost() -> float:
	if not can_upgrade_push_tier():
		return INF
	return c.push_tier_cost[push_tier]

func next_push_tier_name() -> String:
	if not can_upgrade_push_tier():
		return ""
	return c.push_tier_names[push_tier]

func apply_push_tier_upgrade() -> void:
	push_tier += 1

## 現時鏟斗級數對應嘅 tap 收礦倍率（未買任何一級即 Lv0 = ×1）。
func scoop_value_mult() -> float:
	if push_tier <= 0:
		return 1.0
	return c.push_tier_scoop_mult[push_tier - 1]


# ══════════════════════ 地面礦堆：生成 + tap 收礦 ══════════════════════

## 隨機生成一粒地面礦堆（銀多金少，見 c.pile_silver_ratio），已經夠
## c.pile_cap 就乜都唔做、回傳 ""。
func spawn_pile(rng: RandomNumberGenerator) -> String:
	if pile_ore.size() >= c.pile_cap:
		return ""
	var ore_key := "silver" if rng.randf() < c.pile_silver_ratio else "gold"
	pile_ore.append(ore_key)
	return ore_key

## tap 收指定嘅一粒礦（畫面上撳緊嗰粒對應嘅 ore_key）；揾唔到就回傳 0，
## 保證唔會撳走「唔屬於呢粒」嘅份量。值 = 礦物基礎值 × 鏟斗 tier 倍率 ×
## （狂熱期間 c.frenzy_income_mult，見 tick() 同一個 frenzy_active 參數）。
func scoop_pile(ore_key: String, frenzy_active: bool = false) -> float:
	var idx := pile_ore.find(ore_key)
	if idx == -1:
		return 0.0
	pile_ore.remove_at(idx)
	var value: float = c.ore_value(ore_key) * scoop_value_mult()
	if frenzy_active:
		value *= c.frenzy_income_mult
	return value


# ══════════════════════ 瓶頸偵測（UI／HUD 提示用） ══════════════════════

## "layers"／"cart"／"warehouse"／"balanced"。
func bottleneck_stage() -> String:
	var mine_out := total_mine_output()
	var cart := cart_capacity()
	var ware := warehouse_capacity()
	var lo: float = minf(mine_out, minf(cart, ware))
	var hi: float = maxf(mine_out, maxf(cart, ware))
	if hi <= 0.0:
		return "balanced"
	if (hi - lo) / hi < BALANCE_TOLERANCE:
		return "balanced"
	if is_equal_approx(lo, mine_out):
		return "layers"
	if is_equal_approx(lo, cart):
		return "cart"
	return "warehouse"


# ══════════════════════ 每幀模擬：礦層 → 層台緩衝 → 礦車 → 地面緩衝 → 倉庫 → Cash ══════════════════════

## 推進一幀。回傳呢一幀嘅各段流量同 cash_gain——呼叫方自己加落
## GameState.cash（呢個 class 唔再自己揸一份 cash，見檔頭註解）。
func tick(delta: float) -> Dictionary:
	var mined := total_mine_output() * delta
	var underground_room := maxf(c.underground_backlog_cap - underground_backlog, 0.0)
	var accepted := minf(mined, underground_room)
	var jammed := mined - accepted
	underground_backlog += accepted

	var cart_want := cart_capacity() * delta
	var ground_room := maxf(c.ground_backlog_cap - ground_backlog, 0.0)
	var lifted := minf(cart_want, minf(underground_backlog, ground_room))
	underground_backlog -= lifted
	ground_backlog += lifted
	var cart_idle := ground_room <= 0.0 and underground_backlog > 0.0

	var ware_want := warehouse_capacity() * delta
	var collected := minf(ware_want, ground_backlog)
	ground_backlog -= collected
	# 倉庫收貨兌現，值跟地面礦堆同一套（銀多金少，呢度用加權平均：層 1/2/3
	# 分別偏銀／混合／偏金？呢期未細分層台礦物階，統一用銀金各半嘅均值，
	# 跟礦堆嘅視覺分佈（pile_silver_ratio）保持同一數量級但唔重複讀
	# pile_silver_ratio（嗰個係「地面堆」專屬，呢度係「過咗倉庫」專屬，
	# 故意分開，日後可以各自調）。
	var blended_value: float = (c.ore_value_silver + c.ore_value_gold) * 0.5
	# 用戶 2026-09-17：倉庫收集嘅礦照變現金，同時計入「礦料」庫存（部分升級要礦料）
	var cash_gain := collected * blended_value
	var ore_gain := collected

	return {
		"mined": mined, "jammed": jammed, "lifted": lifted, "collected": collected,
		"cash_gain": cash_gain, "ore_gain": ore_gain, "cart_idle": cart_idle,
		"underground_backlog": underground_backlog, "ground_backlog": ground_backlog,
	}

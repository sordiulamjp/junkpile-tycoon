extends RefCounted
class_name MineState

## ALTA-228（VR-12）區域 1 礦坑核心數值狀態：礦層（3 層已開＋1 層鎖住）
## → 升降機 → 倉庫 → Cash 三段管線。
##
## 純邏輯，唔掛靠 SceneTree，方便 GUT 直接 new() 測試（跟 systems/game_state.gd
## 同一風格）。場景（region1_mine.gd）每幀 call tick(delta)，然後用呢個
## 物件嘅屬性更新畫面／HUD。全部數值一律經 MineConstants（`c`），呢度冇
## 任何 hardcode 數字。
##
## 三段瓶頸模型（issue 原文）：「升降機慢→礦塞地底，地面慢→升降機停」——
## 用兩個緩衝池模擬：underground_backlog（已採出等升降機搬）、
## ground_backlog（升降機搬咗等倉庫收）。兩池都有上限，爆咗即係「塞爆」／
## 「停運」，bottleneck_stage() 揾返邊一段係而家嘅產能樽頸畀 UI 提示用。

const BALANCE_TOLERANCE := 0.05 # 三段產能相差 < 5%（相對最大值）當已平衡，冇瓶頸警示

var c: MineConstants

var cash: float = 0.0

## 礦層 1–3 各自等級（無上限，索引 0..2）；layer_level.size() == 3 即
## 「3 層全開」——呢期冇漸進解鎖機制，開場已經三層齊採。
var layer_level: Array[int] = [0, 0, 0]

var elevator_level: int = 1 # Lv1~c.elevator_level_cap
var warehouse_level: int = 1 # Lv1~c.warehouse_level_cap

## 地底排隊中嘅礦量（已採出、未俾升降機搬走），夾喺 0~c.underground_backlog_cap。
var underground_backlog: float = 0.0
## 地面等緊倉庫收嘅礦量（升降機搬咗、未兌 Cash），夾喺 0~c.ground_backlog_cap。
var ground_backlog: float = 0.0

func _init(constants: MineConstants = null) -> void:
	c = constants if constants != null else MineConstants.new()
	cash = c.starting_cash # 跟 GameConstants 做法：開場即夠買第一級升級（20 秒內首購）


# ══════════════════════ 礦層：開採速度 ══════════════════════

func layer_rate(idx: int) -> float:
	if idx < 0 or idx >= layer_level.size():
		return 0.0
	return c.layer_rate_at_level(layer_level[idx])

func total_mine_output() -> float:
	var total := 0.0
	for idx in range(layer_level.size()):
		total += layer_rate(idx)
	return total

func next_layer_cost(idx: int) -> float:
	return c.layer_level_cost(layer_level[idx])

## 升級礦層 idx（0..2）嘅開採速度；冇上限，唔夠錢就乜都唔做，回傳 false。
func upgrade_layer(idx: int) -> bool:
	if idx < 0 or idx >= layer_level.size():
		return false
	var cost := next_layer_cost(idx)
	if cash < cost:
		return false
	cash -= cost
	layer_level[idx] += 1
	return true

## 已採出嘅礦按各層出礦速度佔比加權嘅平均礦值（冇出礦就 0）。
func blended_ore_value() -> float:
	var mine_out := total_mine_output()
	if mine_out <= 0.0:
		return 0.0
	var total := 0.0
	for idx in range(layer_level.size()):
		var share: float = layer_rate(idx) / mine_out
		total += share * c.layer_average_ore_value(idx)
	return total


# ══════════════════════ 升降機：運載量／速度 ══════════════════════

func elevator_capacity() -> float:
	return c.elevator_capacity_at_level(elevator_level)

func can_upgrade_elevator() -> bool:
	return elevator_level < c.elevator_level_cap

func next_elevator_cost() -> float:
	return c.elevator_upgrade_cost(elevator_level)

func upgrade_elevator() -> bool:
	if not can_upgrade_elevator():
		return false
	var cost := next_elevator_cost()
	if cash < cost:
		return false
	cash -= cost
	elevator_level += 1
	return true


# ══════════════════════ 倉庫：收集速度 ══════════════════════

func warehouse_capacity() -> float:
	return c.warehouse_capacity_at_level(warehouse_level)

func can_upgrade_warehouse() -> bool:
	return warehouse_level < c.warehouse_level_cap

func next_warehouse_cost() -> float:
	return c.warehouse_upgrade_cost(warehouse_level)

func upgrade_warehouse() -> bool:
	if not can_upgrade_warehouse():
		return false
	var cost := next_warehouse_cost()
	if cash < cost:
		return false
	cash -= cost
	warehouse_level += 1
	return true


# ══════════════════════ 瓶頸偵測（UI 提示用） ══════════════════════

## 揾返三段（"layers" 礦層出礦／"elevator" 升降機運載／"warehouse" 倉庫
## 收集）入面產能最細嗰段；相差 < BALANCE_TOLERANCE（相對最大值）當
## "balanced"，唔畀 UI 閃瓶頸警示。
func bottleneck_stage() -> String:
	var mine_out := total_mine_output()
	var elev := elevator_capacity()
	var ware := warehouse_capacity()
	var lo: float = minf(mine_out, minf(elev, ware))
	var hi: float = maxf(mine_out, maxf(elev, ware))
	if hi <= 0.0:
		return "balanced"
	if (hi - lo) / hi < BALANCE_TOLERANCE:
		return "balanced"
	if is_equal_approx(lo, mine_out):
		return "layers"
	if is_equal_approx(lo, elev):
		return "elevator"
	return "warehouse"


# ══════════════════════ 每幀模擬：礦層 → 地底緩衝 → 升降機 → 地面緩衝 → 倉庫 → Cash ══════════════════════

## 推進一幀。回傳呢一幀嘅各段流量，方便場景畫動畫／debug。
func tick(delta: float) -> Dictionary:
	# 1) 礦層出礦，入地底緩衝池；池滿咗（升降機長期追唔切）就截斷＝塞爆，
	#    截斷嘅份量算做 jammed，唔會神秘消失得無聲無息（UI 可以用嚟報警）。
	var mined := total_mine_output() * delta
	var underground_room := maxf(c.underground_backlog_cap - underground_backlog, 0.0)
	var accepted := minf(mined, underground_room)
	var jammed := mined - accepted
	underground_backlog += accepted

	# 2) 升降機由地底緩衝攞礦上地面緩衝；同時受自己運載上限、地底存量、
	#    地面緩衝剩餘空間三者夾住——地面緩衝爆咗（倉庫追唔切）升降機
	#    就算有運載力都冇位落，等於停咗（elevator_idle）。
	var elev_want := elevator_capacity() * delta
	var ground_room := maxf(c.ground_backlog_cap - ground_backlog, 0.0)
	var lifted := minf(elev_want, minf(underground_backlog, ground_room))
	underground_backlog -= lifted
	ground_backlog += lifted
	var elevator_idle := ground_room <= 0.0 and underground_backlog > 0.0

	# 3) 倉庫由地面緩衝收貨兌 Cash，受自己收集上限、地面存量夾住。
	var ware_want := warehouse_capacity() * delta
	var collected := minf(ware_want, ground_backlog)
	ground_backlog -= collected
	var cash_gain := collected * blended_ore_value()
	cash += cash_gain

	return {
		"mined": mined, "jammed": jammed, "lifted": lifted, "collected": collected,
		"cash_gain": cash_gain, "elevator_idle": elevator_idle,
		"underground_backlog": underground_backlog, "ground_backlog": ground_backlog,
	}

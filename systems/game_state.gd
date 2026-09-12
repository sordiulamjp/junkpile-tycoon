extends RefCounted
class_name GameState

## VR-03：放置場核心數值狀態（山腳 + 帶 + 爐 + 礦工 + 三條升級線）。
##
## 純邏輯，唔掛靠 SceneTree，方便 GUT 直接 new() 測試。場景（main.gd）
## 每幀call tick(delta)，然後用呢個物件嘅屬性更新畫面／HUD。
## 全部數值一律經 GameConstants（`c`），呢度冇任何 hardcode 數字。

var c: GameConstants

var cash: float = 0.0
var components: float = 0.0
var eco: float = 0.0

var miner_count: int = 0     # 已召喚礦工數，上限 c.miner_summon_cap
var miner_level: int = 0     # 礦工等級（無上限），速度 ×c.miner_level_speed_mult／級
var belt_level: int = 1      # 帶等級，1~c.belt_level_cap（Lv10 封頂）
var refine_level: int = 0    # 精煉等級（無上限），礦值 ×c.refine_value_mult／級

## 山腳未撿嘅碎料（等緊玩家手動 scoop）；同帶上面嘅碎料係兩個獨立池，
## 已經送咗上帶嘅唔會再入返呢個 array——即「已 belted 碎料不可 scoop」。
var pile_debris: Array[String] = []

func _init(constants: GameConstants = null) -> void:
	c = constants if constants != null else GameConstants.new()


# ══════════════════════ 礦工：召喚 ══════════════════════

func can_summon_miner() -> bool:
	return miner_count < c.miner_summon_cap

func next_miner_cost() -> float:
	return c.miner_summon_cost(miner_count + 1)

## 召喚一個礦工；唔夠錢或者撞上限就乜都唔做，回傳 false。
func summon_miner() -> bool:
	if not can_summon_miner():
		return false
	var cost := next_miner_cost()
	if cash < cost:
		return false
	cash -= cost
	miner_count += 1
	return true


# ══════════════════════ 礦工等級（速度） ══════════════════════

func next_miner_level_cost() -> float:
	return c.miner_level_cost(miner_level + 1)

func upgrade_miner_level() -> bool:
	var cost := next_miner_level_cost()
	if cash < cost:
		return false
	cash -= cost
	miner_level += 1
	return true

## 每個礦工每秒出礦量（ore/s），已計入礦工等級速度倍率。
func miner_ore_rate() -> float:
	return c.ore_rate_per_miner * pow(c.miner_level_speed_mult, miner_level)


# ══════════════════════ 帶升級 ══════════════════════

func can_upgrade_belt() -> bool:
	return belt_level < c.belt_level_cap

func next_belt_cost() -> float:
	return c.belt_upgrade_cost(belt_level)

## 帶升一級；已經封頂（Lv10）就乜都唔做，回傳 false。帶升到尾都係
## 同一條幹線，淨係 belt_capacity_at_level() 個數值變大，唔會加分支。
func upgrade_belt() -> bool:
	if not can_upgrade_belt():
		return false
	var cost := next_belt_cost()
	if cash < cost:
		return false
	cash -= cost
	belt_level += 1
	return true

func belt_capacity() -> float:
	return c.belt_capacity_at_level(belt_level)


# ══════════════════════ 精煉等級 ══════════════════════

func next_refine_level_cost() -> float:
	return c.refine_level_cost(refine_level + 1)

func upgrade_refine() -> bool:
	var cost := next_refine_level_cost()
	if cash < cost:
		return false
	cash -= cost
	refine_level += 1
	return true

func refine_multiplier() -> float:
	return pow(c.refine_value_mult, refine_level)


# ══════════════════════ 礦物價值 ══════════════════════

## 某層礦物分佈嘅期望值（未經精煉倍率）；`site` 對應
## c.ore_distribution 嘅 key（"foothill" / "mid" / "upper"）。
func average_ore_value(site: String = "foothill") -> float:
	var dist: Dictionary = c.ore_distribution.get(site, {})
	var total := 0.0
	for ore_key: String in dist:
		var weight: float = dist[ore_key]
		var value: float = c.ore_tier_value.get(ore_key, 0)
		total += weight * value
	return total


# ══════════════════════ 手動 scoop（山腳碎料） ══════════════════════

## 隨機喺山腳生成一粒未撿碎料，放入 pile_debris 等玩家㩒。
func spawn_pile_debris(rng: RandomNumberGenerator, site: String = "foothill") -> String:
	var dist: Dictionary = c.ore_distribution.get(site, {})
	var keys: Array = dist.keys()
	if keys.is_empty():
		return ""
	var roll := rng.randf()
	var acc := 0.0
	for ore_key: String in keys:
		acc += dist[ore_key]
		if roll <= acc:
			pile_debris.append(ore_key)
			return ore_key
	var fallback: String = keys[keys.size() - 1]
	pile_debris.append(fallback)
	return fallback

## 手動剷起山腳第一粒未撿碎料，直接兌現金（唔過爐、冇精煉倍率）。
## 冇碎料可剷就回傳 0——已經上咗帶嘅碎料唔會出現喺呢個 pool，
## 所以呢個方法本身已經滿足「已 belted 碎料不可 scoop」。
func scoop_first() -> float:
	if pile_debris.is_empty():
		return 0.0
	var ore_key: String = pile_debris.pop_front()
	var value: float = c.ore_tier_value.get(ore_key, 0)
	cash += value
	return value

## 剷起指定礦物階嘅其中一粒（畫面上玩家㩒緊嗰粒對應嘅 ore_key）。
## 揾唔到就乜都唔做，回傳 0——保證唔會剷走「唔屬於呢粒」嘅份量。
func scoop_ore(ore_key: String) -> float:
	var idx := pile_debris.find(ore_key)
	if idx == -1:
		return 0.0
	pile_debris.remove_at(idx)
	var value: float = c.ore_tier_value.get(ore_key, 0)
	cash += value
	return value


## 觸發嗰刻嘅放置收入（Cash/s），穩態值——同 tick() 用同一條夾帶產能
## 上限嘅公式，但唔帶 delta，俾 VR-04 狂熱計「收益基準＝放置收入 ×5 ×120s」用。
func current_income_rate() -> float:
	var mined_rate: float = float(miner_count) * miner_ore_rate()
	var fed_rate: float = minf(mined_rate, belt_capacity())
	return fed_rate * average_ore_value("foothill") * refine_multiplier()


# ══════════════════════ 每幀模擬：礦工 → 帶（上限）→ 爐 → Cash ══════════════════════

## 推進一幀。礦工自動出礦，受帶產能上限夾住（帶未升級就會有 overflow，
## 鼓勵升帶）；入到爐嘅份量按精煉等級加成兌 Cash，同時計返少少 Eco。
func tick(delta: float) -> Dictionary:
	var mined := float(miner_count) * miner_ore_rate() * delta
	var cap := belt_capacity() * delta
	var fed := minf(mined, cap)
	var overflow := maxf(mined - fed, 0.0)
	var ore_value := average_ore_value("foothill")
	var cash_gain := fed * ore_value * refine_multiplier()
	var eco_gain := fed * c.eco_gain_hazard_per_item
	cash += cash_gain
	eco += eco_gain
	return {"mined": mined, "fed": fed, "overflow": overflow, "cash_gain": cash_gain, "eco_gain": eco_gain}

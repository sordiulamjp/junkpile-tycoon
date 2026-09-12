extends RefCounted
class_name FrenzyState

## VR-04：狂熱車場核心數值狀態（跟指車、剛體堆、倍數門、滾筒、木橋、
## UPGRADE 墊、齒輪、幀數自動降級）。
##
## 同 GameState 一樣，純邏輯、唔掛靠 SceneTree，方便 GUT 直接 new() 測試；
## 3D 表現（frenzy_yard_view.gd）每幀 call tick()／advance_car() 等方法，
## 自己淨係負責畫面同輸入轉接。全部數值經 GameConstants（`c`）攞，
## 呢度冇任何 hardcode 數字。
##
## 觸發（v2）：免費、唔收 Cash（舊 docx 250 Cash 已被 ALTA-149 v2 取代）。
## 冷卻：一般 c.frenzy_cooldown_secs（600s），但*第一次*觸發前只需要
## c.frenzy_first_cooldown_secs（90s）——呢個縮短淨係影響「開局到第一次
## 撳到」，之後每次結束都係用返一般冷卻，所以淨係喺 _init() 初始化，
## end() 唔使再分支。

var c: GameConstants

var active: bool = false
var time_remaining: float = 0.0
var cooldown_remaining: float = 0.0

## 呢次狂熱嘅「收益基準」＝觸發嗰刻放置收入 ×frenzy_mult ×duration；
## FRENZY_MANUAL_EFF 應該調到玩家正常推堆嘅 cash_earned 大致貼近呢個數。
var frenzy_reference_total: float = 0.0
var cash_earned: float = 0.0
var components_earned: float = 0.0
var eco_bonus_earned: float = 0.0

## -- 車 --
var car_x: float = 0.0
var car_tier: int = 0        # index into c.car_upgrade_tiers，UPGRADE 墊逐級升
var pad_cooldown: float = 0.0

## -- 溢滿條（窄岩浆＋木橋跌落唔即死，只加溢滿；上限 c.trash_meter_cap）--
var overflow: float = 0.0
var _had_overflow: bool = false # 呢次狂熱有冇跌過一次，決定完場零掉坑 Eco 花紅

## -- 齒輪（狂熱期間每 gear_drop_interval_secs 一粒） --
var gear_timer: float = 0.0

## -- 幀數自動降級（S8+ 實測結果寫入 constants 嘅 degrade 曲線）--
var fps_low_streak: int = 0
var debris_tier: int = 0 # 0＝debris_rigidbody_cap；1.. index入 c.frenzy_debris_degrade_steps


func _init(constants: GameConstants = null) -> void:
	c = constants if constants != null else GameConstants.new()
	cooldown_remaining = c.frenzy_first_cooldown_secs


# ══════════════════════ 觸發／冷卻／倒數 ══════════════════════

func can_start() -> bool:
	return not active and cooldown_remaining <= 0.0

## 免費觸發，唔收 Cash（v2）。base_income_rate 係觸發嗰刻嘅放置收入
## （Cash/s，由 GameState.current_income_rate() 攞），用嚟計收益基準。
func start(base_income_rate: float) -> bool:
	if not can_start():
		return false
	active = true
	time_remaining = c.frenzy_duration_secs
	frenzy_reference_total = base_income_rate * c.frenzy_mult * c.frenzy_duration_secs
	cash_earned = 0.0
	components_earned = 0.0
	eco_bonus_earned = 0.0
	overflow = 0.0
	_had_overflow = false
	car_tier = 0
	pad_cooldown = 0.0
	gear_timer = 0.0
	debris_tier = 0
	fps_low_streak = 0
	return true

## 時間到（或者外部強制）完場：轉入一般冷卻，結算零掉坑 Eco 花紅。
func end() -> void:
	if not active:
		return
	active = false
	cooldown_remaining = c.frenzy_cooldown_secs
	if not _had_overflow:
		eco_bonus_earned += c.eco_gain_perfect_sort_bonus

## 推進一幀。回傳事件字典俾場景反應：ended（呢幀啱啱完場）、
## gear_spawn（呢幀應該生一粒新齒輪）。
func tick(delta: float) -> Dictionary:
	var events := {"ended": false, "gear_spawn": false}
	if active:
		overflow = maxf(overflow + c.trash_meter_decay_per_sec * delta, 0.0)
		pad_cooldown = maxf(pad_cooldown - delta, 0.0)
		gear_timer += delta
		if gear_timer >= c.gear_drop_interval_secs:
			gear_timer -= c.gear_drop_interval_secs
			events["gear_spawn"] = true
		time_remaining = maxf(time_remaining - delta, 0.0)
		if time_remaining <= 0.0:
			end()
			events["ended"] = true
	else:
		cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
	return events


# ══════════════════════ 跟指車 ══════════════════════

func current_tier() -> Dictionary:
	var idx := clampi(car_tier, 0, c.car_upgrade_tiers.size() - 1)
	return c.car_upgrade_tiers[idx]

## 車跟指移動，夾喺 yard_x_range 之內；速度受 car_speed × 車輛等級
## speed_mult 影響（UPGRADE 墊升級之後跟得更貼）。回傳新嘅 car_x。
func advance_car(delta: float, target_x: float) -> float:
	var clamped_target: float = clampf(target_x, c.yard_x_range.x, c.yard_x_range.y)
	var speed: float = c.car_speed * float(current_tier().get("speed_mult", 1.0))
	var max_step: float = speed * delta
	var diff: float = clamped_target - car_x
	if absf(diff) <= max_step:
		car_x = clamped_target
	else:
		car_x += signf(diff) * max_step
	return car_x

## UPGRADE 墊即換模型：逐級升，去到尾一級之後留喺度（唔循環）。
## 冷卻中（pad_cooldown > 0）或者未狂熱就撳唔到。
func try_upgrade_pad() -> bool:
	if not active or pad_cooldown > 0.0:
		return false
	car_tier = mini(car_tier + 1, c.car_upgrade_tiers.size() - 1)
	pad_cooldown = c.upgrade_pad_rearm_secs
	return true


# ══════════════════════ 散幣／藍波／刺滾筒／倍數門 ══════════════════════

func roll_spawn_kind(rng: RandomNumberGenerator) -> String:
	return "barrel" if rng.randf() < c.barrel_spawn_ratio else "coin"

func base_value_for_kind(kind: String) -> float:
	match kind:
		"barrel": return c.scrap_barrel_value
		"gold": return c.scrap_gold_value
		_: return c.scrap_coin_value

## 藍波過刺滾筒轉做金幣；散幣／已經係金幣嘅原地不動（冪等，滾筒可以
## 重複踫到都唔會再改變）。
func apply_roller(kind: String) -> String:
	return "gold" if kind == "barrel" else kind

## 一粒碎料兌現：連續過幾道門（passed_gates 由場景記低），倍數相乘，
## 再乘 FRENZY_MANUAL_EFF（實測後調嘅玩家推堆效率）。唔喺狂熱期間
## 兌現嘅（例如場景手民之誤喺完場之後先call到）一律唔計分。
func score_item(base_value: float, passed_gates: Array) -> float:
	if not active:
		return 0.0
	var mult: float = c.combined_gate_multiplier(passed_gates)
	var awarded: float = base_value * mult * c.frenzy_manual_eff
	cash_earned += awarded
	return awarded


# ══════════════════════ 窄岩浆 + 木橋 ══════════════════════

func is_bridge_safe_x(x: float) -> bool:
	return x >= c.lava_bridge_safe_x_range.x and x <= c.lava_bridge_safe_x_range.y

## 跌落一次：加溢滿（上限 trash_meter_cap），唔即死，記低「呢次狂熱
## 跌過」令完場攞唔到零掉坑花紅。回傳新溢滿值。
func register_lava_fall() -> float:
	if active:
		overflow = minf(overflow + c.lava_fall_overflow_amount, float(c.trash_meter_cap))
		_had_overflow = true
	return overflow


# ══════════════════════ 齒輪 ══════════════════════

## 玩家親手截到一粒齒輪（gear_pickup_window_secs 之內），兌 Components；
## 未狂熱截唔到分。
func register_gear_catch() -> float:
	if not active:
		return 0.0
	components_earned += c.gear_component_reward
	return c.gear_component_reward


# ══════════════════════ 幀數自動降級 ══════════════════════

## 每 frenzy_fps_sample_interval_secs 取樣一次（場景負責計時 call 呢個
## 方法）。連續 frenzy_fps_low_streak_to_degrade 次低於門檻先降一級，
## 避免單幀抖動就誤降；達標一次就重置連續計數（唔會自動升返級——
## 一次狂熱入面降咗就降咗，避免嚟回震盪）。
func sample_fps(fps: float) -> void:
	if not active:
		return
	if fps < c.frenzy_fps_low_threshold:
		fps_low_streak += 1
		if fps_low_streak >= c.frenzy_fps_low_streak_to_degrade:
			fps_low_streak = 0
			debris_tier = mini(debris_tier + 1, c.frenzy_debris_degrade_steps.size())
	else:
		fps_low_streak = 0

func current_debris_cap() -> int:
	if debris_tier <= 0:
		return c.debris_rigidbody_cap
	var idx := clampi(debris_tier - 1, 0, c.frenzy_debris_degrade_steps.size() - 1)
	return c.frenzy_debris_degrade_steps[idx]

func is_fake_physics() -> bool:
	return debris_tier >= c.frenzy_fake_physics_min_tier

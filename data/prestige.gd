extends RefCounted
class_name Prestige

## VR-05：威望重置（拆廠搬礦，跟 Analyst v2）。
## 門檻 = GameConstants.prestige_threshold(prestige_count)，累計賺到（lifetime_cash）
## 就可以重置。重置會清礦工／升級／Cash，但保留 prestige_count（+1）同
## lifetime_cash；每重置一次，永久收入 +50%（累加，唔係複合）。

## 依家個存檔夠唔夠門檻做威望重置。
static func can_prestige(constants: GameConstants, state: Dictionary) -> bool:
	var threshold := constants.prestige_threshold(int(state.get("prestige_count", 0)))
	return float(state.get("lifetime_cash", 0.0)) >= threshold

## 執行威望重置，回傳新狀態：礦工／升級／Cash 歸零，prestige_count +1，
## lifetime_cash 保留（呢個係終身統計，唔隨重置清零）。
## 呼叫方負責先用 can_prestige() check 門檻——呢度唔擋，方便測試同 debug 指令。
static func reset(state: Dictionary) -> Dictionary:
	var new_state := SaveManager.default_state()
	new_state["prestige_count"] = int(state.get("prestige_count", 0)) + 1
	new_state["lifetime_cash"] = float(state.get("lifetime_cash", 0.0))
	new_state["last_save_unix"] = state.get("last_save_unix", Time.get_unix_time_from_system())
	return new_state

## 永久收入倍率：1.0 + prestige_bonus_per_reset × 重置次數（線性累加）。
static func income_multiplier(constants: GameConstants, prestige_count: int) -> float:
	return 1.0 + constants.prestige_bonus_per_reset * float(prestige_count)

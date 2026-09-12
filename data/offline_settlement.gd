extends RefCounted
class_name OfflineSettlement

## VR-05：離線結算入口。負責「經過咗幾多秒」呢層時間管理同串接
## GameConstants.compute_offline_yield() 嘅 banded yield 公式，再套威望永久
## 倍率（Prestige.income_multiplier）。唔喺呢層做礦工／帶／精煉嘅產能公式
## （見 VR-01/VR-03）——嗰啲加埋之後嘅「每秒收入」由呼叫方（production 系統）
## 算好，經 raw_base_rate_per_sec 傳入。

## 離線經過咗幾多秒。時間回撥（now_unix < last_save_unix）當 0——
## 呢個係防刷嘅第一道閘（跟住 GameConstants.compute_offline_yield 仲有
## 極短空隙、牆鐘上限兩道）。
static func settle_offline_secs(last_save_unix: float, now_unix: float) -> float:
	var elapsed := now_unix - last_save_unix
	if elapsed < 0.0:
		return 0.0
	return elapsed

## 完整離線結算：回傳更新後嘅 state（cash／lifetime_cash／last_save_unix）
## 同一份結算報告（elapsed_secs／capped_secs／cash_yield），畀 UI／浣熊經理
## 發糧文案用。raw_base_rate_per_sec 係離線嗰刻嘅放置收入（未計威望倍率）。
##
## VR-05b（ALTA-216）備註：main.gd 已經接咗呢個流程——開機見到有存檔
## 就叫 settle()，彈浣熊經理發糧面板，撳「收下」先入帳同補
## EventLog.log_event("offline_claim", …)（見 main.gd
## _run_offline_settlement()／_on_offline_claim_pressed()）。
static func settle(
	constants: GameConstants,
	state: Dictionary,
	now_unix: float,
	raw_base_rate_per_sec: float
) -> Dictionary:
	var last_save_unix: float = state.get("last_save_unix", now_unix)
	var elapsed := settle_offline_secs(last_save_unix, now_unix)
	var prestige_count: int = int(state.get("prestige_count", 0))
	var effective_rate := raw_base_rate_per_sec * Prestige.income_multiplier(constants, prestige_count)
	var cash_yield := constants.compute_offline_yield(effective_rate, elapsed)

	var new_state := state.duplicate(true)
	new_state["cash"] = float(state.get("cash", 0.0)) + cash_yield
	new_state["lifetime_cash"] = float(state.get("lifetime_cash", 0.0)) + cash_yield
	new_state["last_save_unix"] = now_unix

	return {
		"state": new_state,
		"elapsed_secs": elapsed,
		"capped_secs": minf(elapsed, constants.offline_cap_secs),
		"cash_yield": cash_yield,
	}

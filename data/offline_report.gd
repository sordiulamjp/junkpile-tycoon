extends RefCounted
class_name OfflineReport

## VR-05：浣熊經理離線發糧文案。淨係負責文字內容，版面／彈窗由 UI 層
## （之後嘅 issue）自己套。分三級：冇經過時間、經過咗但冇收成、正常有收成
## （撞到 8 小時上限再加一句）。

static func raccoon_message(cash_yield: float, elapsed_secs: float, cap_secs: float) -> String:
	if elapsed_secs <= 0.0:
		return "浣熊經理：「咁快返嚟？礦場都仲未凍過吸！」"
	if cash_yield <= 0.0:
		return "浣熊經理：「你走得太耐都好，走得太快都好，呢鑊冇嘢執到喎。」"
	if elapsed_secs >= cap_secs:
		return "浣熊經理：「執到成 8 個鐘嘅貨，我隻手都攰！幫你賺咗 $%s。」" % _format_cash(cash_yield)
	return "浣熊經理：「你唔喺度嗰陣，我幫手睇實個礦場！賺咗 $%s。」" % _format_cash(cash_yield)

static func _format_cash(amount: float) -> String:
	return "%d" % roundi(amount) # 千分位／單位縮寫留畀 UI 數字元件處理（VR-05 唔包 UI）

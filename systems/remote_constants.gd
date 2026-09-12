extends RefCounted
class_name RemoteConstants

## VR-08：遠端 constants 覆寫嘅純邏輯（sanitize／apply）。搬 yaing
## meta/ + Cloudflare Worker + KV 模式（見 worker/README.md）：App 開機
## GET 一個 JSON，覆寫 GameConstants.REMOTE_TUNABLE_FIELDS 白名單入面嘅
## 純量（float／int）欄位，失敗／壞 JSON 一律 fallback 用本機預設。
##
## 呢個 class 淨係做「畀你一個 parsed JSON（可能亂七八糟），洗返得淨嘅
## overrides」同「套用喺一個 GameConstants」，冇任何網絡 I/O，方便 GUT
## 唔使開網絡都測到「合併」「壞 JSON fallback」。真正發 HTTP request
## 嗰部分見 systems/remote_constants_loader.gd。

## 由 parsed JSON（Variant，可能係 null／字串／陣列／亂七八糟嘅結構）
## 攞出得淨嘅覆寫 Dictionary：淨保留白名單內、型別係數字（int／float）、
## 唔係 NaN／Infinity 嘅 key；其餘（唔喺白名單、型別唔啱、壞數）全部
## 忽略——單一個 key 壞唔會累到其餘啱嘅 key 一齊唔覆寫。
## int 欄位（例如 belt_level_cap）會 round 埋先寫返（JSON 冇 int／float
## 之分，Godot 嘅 JSON.parse_string 一律讀做 float）。
static func sanitize_overrides(parsed: Variant) -> Dictionary:
	var out := {}
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var defaults := GameConstants.new()
	for key: String in GameConstants.REMOTE_TUNABLE_FIELDS:
		if not parsed.has(key):
			continue
		var raw: Variant = parsed[key]
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			continue
		var num := float(raw)
		if not is_finite(num):
			continue
		if typeof(defaults.get(key)) == TYPE_INT:
			out[key] = int(round(num))
		else:
			out[key] = num
	return out


## 將已經 sanitize 過嘅 overrides 套用喺 base 嘅一份 duplicate，回傳新
## 個體（唔改動傳入嗰個 base）。冇喺 overrides 出現嘅欄位維持 base 原值。
static func apply_overrides(base: GameConstants, overrides: Dictionary) -> GameConstants:
	var result: GameConstants = base.duplicate(true)
	for key: String in overrides:
		result.set(key, overrides[key])
	return result

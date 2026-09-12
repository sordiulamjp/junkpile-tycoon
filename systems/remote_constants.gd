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


# ══════════════ 本機 cache：「App 重開即生效」要靠佢，唔淨係靠背景 fetch ══════════════
# Review 意見（ALTA-155）：main.gd 開機順序係 `c = GameConstants.new()` →
# 起 GameState／FrenzyState／pile timer → 世界／HUD 起晒之後先背景 fetch。
# 有幾個 TUNE 欄位喺 GameState/FrenzyState._init() 或者 Timer.wait_time
# 果陣已經俾讀走（starting_cash、frenzy_first_cooldown_secs、
# pile_debris_spawn_interval_secs），background fetch 嗰陣先 set() 落 `c`
# 已經太遲——就算改咗遠端 JSON、重開幾多次呢幾個欄位都唔會生效。
#
# 解法：每次 fetch 成功（包括伺服器話「而家冇任何覆寫」嗰種空結果）就將
# sanitize 好嘅 overrides 寫落 user:// 做 cache；下次開機 main.gd 喺
# `c = GameConstants.new()` 之後、構造任何讀 `c` 嘅物件之前，就同步讀返
# cache 套用落 `c`——咁樣所有白名單欄位（包括呢三個）先至真正「重開即
# 生效」，離線都用返上次成功攞到嘅值。
const CACHE_PATH := "user://remote_constants_cache.json"

## 讀返上次成功 fetch 存低嘅 overrides（冇 cache／讀壞都回傳空 Dictionary，
## 唔會拋錯）。讀返嚟嗰陣會再 sanitize 一次——cache 檔案本身壞咗／俾人手
## 改壞都唔會套用到壞值，同網絡嗰條 fallback 路一致嘅企位。
static func read_cache() -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	return sanitize_overrides(JSON.parse_string(text))

## 存低呢次成功 fetch 攞到嘅 overrides（可以係空 Dictionary——代表伺服器
## 而家冇任何覆寫，下次開機應該用返純本機預設，唔係維持舊 cache）。
static func write_cache(overrides: Dictionary) -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(overrides))
	file.close()

static func clear_cache() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(CACHE_PATH)

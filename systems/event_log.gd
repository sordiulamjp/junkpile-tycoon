extends RefCounted
class_name EventLog

## VR-08：本機事件 log。session_start／frenzy_start／frenzy_end／
## offline_claim／upgrade／prestige（同 remote_config，見
## systems/remote_constants_loader.gd）逐行寫 JSON 落 user://events.jsonl
## （JSON Lines：一行一個事件，逐行 append／讀取，唔使成個檔案重新
## parse）。跟 data/save_manager.gd 同一種風格：全部 static、直接讀寫
## user:// 檔案，唔使 autoload。
##
## 有行數上限（MAX_LINES），寫爆就自動滾動保留最新嗰批，唔會無限脹大；
## debug 畫面（debug/event_log_debug.gd）可以匯出（export_text）／
## 清除（clear）。

const LOG_PATH := "user://events.jsonl"
const MAX_LINES := 500 # 自動滾動上限；超過就淨保留最新呢咁多行

## 遊戲事件類型（描述性白名單，唔會擋住新類型——log_event() 對未列出
## 嘅 type 一樣照寫，方便日後擴充，唔使兩處同步）。
const EVENT_TYPES := [
	"session_start", "frenzy_start", "frenzy_end", "offline_claim", "upgrade", "prestige",
	"rewarded_offline_x2", "rewarded_extra_frenzy", "remove_ads_purchased", "remove_ads_restored",
]


## 寫一行事件：{ts, version, type, data}。ts 用 unix 秒（Time.get_unix_time_from_system()），
## version 讀 project.godot 嘅 `application/config/version`（出新版記得同
## export_presets.cfg 嘅 version/name 一齊改，兩處冇自動同步；冇設就 fallback
## 做 1，唔會拋錯）。壞唔到：讀／寫檔失敗都靜靜哋吞（跟 SaveManager 一樣，
## log 系統本身唔可以搞到遊戲行為受影響）。
static func log_event(type: String, data: Dictionary = {}) -> void:
	var entry := {
		"ts": Time.get_unix_time_from_system(),
		"version": ProjectSettings.get_setting("application/config/version", 1),
		"type": type,
		"data": data,
	}
	var lines := _read_lines()
	lines.append(JSON.stringify(entry))
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES, lines.size())
	_write_lines(lines)


## debug 畫面「匯出」：回傳成個 log 檔嘅原始文字（逐行 JSON），畀 UI
## 存做檔案／經 FileDialog 複製出去。冇 log 就回傳空字串。
static func export_text() -> String:
	if not FileAccess.file_exists(LOG_PATH):
		return ""
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## debug 畫面「清除」：刪走成個 log 檔。
static func clear() -> void:
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.remove_absolute(LOG_PATH)


## 讀返 parsed 事件陣列（逐行 JSON.parse_string），跳過壞行（單行格式
## 壞咗唔會累到成個 log 讀唔到）。
static func read_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in _read_lines():
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append(parsed)
	return out


## 目前有幾多行（未過濾壞行，同 _read_lines() 一致）。
static func count() -> int:
	return _read_lines().size()


static func _read_lines() -> Array[String]:
	var lines: Array[String] = []
	if not FileAccess.file_exists(LOG_PATH):
		return lines
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return lines
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		if line.strip_edges() != "":
			lines.append(line)
	return lines


static func _write_lines(lines: Array[String]) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	for line in lines:
		file.store_line(line)
	file.close()

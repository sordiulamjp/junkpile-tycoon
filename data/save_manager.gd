extends RefCounted
class_name SaveManager

## VR-05：本機存檔。JSON 格式，寫入 user://save-v1.json，頂層鍵用
## GameConstants.SAVE_KEY（"junkpile-save-v1"）包住實際狀態，方便日後
## 換檔案格式時仍可以喺同一個檔案入面認到呢個鍵。
##
## 版本 + 遷移框架：state 入面嘅 "version" 欄位記低存檔格式版本；
## 讀檔時經 _migrate() 由舊版本一路陞級到 CURRENT_VERSION。新增/改動存檔
## 欄位時，CURRENT_VERSION += 1，並喺 _migrate() 加一段新嘅 `if version < N`
## 分支嚟補齊／轉換欄位——唔好改舊分支嘅邏輯，保證舊存檔一路陞級落嚟都啱。
##
## VR-08 備註：main.gd 而家仲未有喺開機／退出叫 load_state()／save_state()
## （見 data/offline_settlement.gd、data/prestige.gd 同一備註）——嗰段
## 遊戲流程接駁仲未起，超出 VR-08 範圍。

const SAVE_PATH := "user://save-v1.json"
const CURRENT_VERSION := 1

## 全新存檔嘅預設狀態。
static func default_state() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"last_save_unix": Time.get_unix_time_from_system(),
		"cash": 0.0,
		"components": 0.0,
		"eco": 0.0,
		"lifetime_cash": 0.0,
		"prestige_count": 0,
		"miners": 0,
		"miner_level": 0,
		"belt_level": 1,
		"refine_level": 0,
	}

## 存檔：寫入 {SAVE_KEY: state} 做 JSON。失敗（例如冇寫入權限）回傳 FileAccess 錯誤碼。
static func save_state(state: Dictionary) -> Error:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({GameConstants.SAVE_KEY: state}))
	file.close()
	return OK

## 讀檔：檔案唔存在／格式壞咗一律當新玩家，回傳預設狀態（唔拋錯、唔卡死）。
## 讀到嘅舊版本存檔會經 _migrate() 陞級。
static func load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return default_state()
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return default_state()
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has(GameConstants.SAVE_KEY):
		return default_state()
	var data: Variant = parsed[GameConstants.SAVE_KEY]
	if typeof(data) != TYPE_DICTIONARY:
		return default_state()
	return _migrate(data)

## 刪走本機存檔（威望重置唔用呢個——重置係覆寫，唔係刪檔；呢個係畀測試／
## debug 用嘅完全重來）。
static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

## 由 data["version"] 一路陞級到 CURRENT_VERSION，缺咗嘅欄位補返預設值。
static func _migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("version", 0))
	if version < 1:
		# v0（未有 version 欄位嘅舊存檔／殘缺存檔）-> v1：補齊全部預設欄位。
		var defaults := default_state()
		for key: String in defaults:
			if not data.has(key):
				data[key] = defaults[key]
		version = 1
	# 未來新版本喺呢度逐級加：if version < 2: ... version = 2
	data["version"] = version
	return data

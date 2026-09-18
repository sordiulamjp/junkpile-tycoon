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
## VR-05b（ALTA-216）備註：main.gd 已經接咗呢個流程——_ready() 開機讀
## load_state()，升級／召喚／狂熱完場／每 30s／退背景／關閉視窗全部會
## save_state()（見 main.gd _save_game() 同埋佢嘅呼叫點）。
##
## VR-11（ALTA-227）備註：「同一場地，由下向上擴張」（field-zones-v9.png）
## ——唔係獨立場景，一個存檔仍然係呢個 flat dict，新增 unlocked_regions
## 記低已解鎖咗邊幾個區域（見 v1→v2 遷移分支）。
##
## ALTA-228（VR-12）備註：區域 1（開場）場內礦坑（regions/region1_mine/
## mine_zone.gd）加咗 "mine_zone" 子 dict（層解鎖／等級、礦車／倉庫
## 等級、推堆墊 tier，見 v2→v3 遷移分支）。
##
## ALTA-229（VR-13）備註：區域 2 外圍險路（regions/region2_outer_path/
## region2_zone.gd）加咗 "region2_zone" 子 dict（UPGRADE 小屋 tier，見
## v3→v4 遷移分支）。
##
## ALTA-285（VR-07a）備註：加咗 "monetization" 子 dict（兩個 rewarded 位
## 每日額度 + 去廣告 IAP 擁有狀態，見 systems/monetization_state.gd，
## v4→v5 遷移分支）。

const SAVE_PATH := "user://save-v1.json"
const CURRENT_VERSION := 5

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
		"unlocked_regions": ["region1"],
		"mine_zone": {
			"layer_unlocked": [true, false, false],
			"layer_level": [0, 0, 0],
			"cart_level": 1,
			"warehouse_level": 1,
			"push_tier": 0,
		},
		"region2_zone": {
			"shack_tier": 0,
		},
		"monetization": {
			"ads_removed": false,
			"quota_day": 0,
			"offline_x2_used_today": 0,
			"extra_frenzy_used_today": 0,
		},
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
	if version < 2:
		# v1 -> v2（VR-11）：加 unlocked_regions。舊存檔本身已經有區域 1
		# 嘅進度（冧一世都喺度玩緊嗰個場地），所以當佢區域 1 已解鎖，唔使
		# 由頭嚟過。
		if not data.has("unlocked_regions"):
			data["unlocked_regions"] = ["region1"]
		version = 2
	if version < 3:
		# v2 -> v3（ALTA-228）：加 mine_zone（層 1 開場已開，層 2／3 鎖、
		# 礦車／倉庫 Lv1、推堆墊未買）。
		if not data.has("mine_zone"):
			data["mine_zone"] = {
				"layer_unlocked": [true, false, false],
				"layer_level": [0, 0, 0],
				"cart_level": 1,
				"warehouse_level": 1,
				"push_tier": 0,
			}
		version = 3
	if version < 4:
		# v3 -> v4（ALTA-229）：加 region2_zone（UPGRADE 小屋未買）。
		if not data.has("region2_zone"):
			data["region2_zone"] = {"shack_tier": 0}
		version = 4
	if version < 5:
		# v4 -> v5（ALTA-285）：加 monetization（未去廣告、額度未用）。
		if not data.has("monetization"):
			data["monetization"] = {
				"ads_removed": false,
				"quota_day": 0,
				"offline_x2_used_today": 0,
				"extra_frenzy_used_today": 0,
			}
		version = 5
	# 未來新版本喺呢度逐級加：if version < 6: ... version = 6
	data["version"] = version
	return data

extends GutTest

## VR-08：res://systems/event_log.gd 單元測試。
## 覆蓋：寫入／讀返、行數上限自動滾動、匯出／清除、壞行唔會累到成個
## log 讀唔到。

func before_each() -> void:
	EventLog.clear()

func after_each() -> void:
	EventLog.clear()


func test_log_event_writes_one_line() -> void:
	EventLog.log_event("session_start")
	assert_eq(EventLog.count(), 1)

func test_read_events_returns_type_and_data() -> void:
	EventLog.log_event("upgrade", {"track": "belt", "level": 3})
	var events := EventLog.read_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "upgrade")
	assert_eq(events[0]["data"]["track"], "belt")
	assert_eq(int(events[0]["data"]["level"]), 3)
	assert_true(events[0].has("ts"), "每行都應該帶時間戳")
	assert_true(events[0].has("version"), "每行都應該帶版本")

func test_events_are_appended_in_order() -> void:
	EventLog.log_event("session_start")
	EventLog.log_event("frenzy_start")
	EventLog.log_event("frenzy_end")
	var events := EventLog.read_events()
	assert_eq(events.size(), 3)
	assert_eq(events[0]["type"], "session_start")
	assert_eq(events[1]["type"], "frenzy_start")
	assert_eq(events[2]["type"], "frenzy_end")

func test_rotation_keeps_only_max_lines_newest_first_dropped() -> void:
	# 寫 MAX_LINES + 5 個事件，data.i 由 0 開始遞增，方便驗證「保留最新」。
	var total := EventLog.MAX_LINES + 5
	for i in range(total):
		EventLog.log_event("upgrade", {"i": i})
	assert_eq(EventLog.count(), EventLog.MAX_LINES, "超過上限應該自動滾動去返上限")
	var events := EventLog.read_events()
	assert_eq(int(events[0]["data"]["i"]), 5, "最舊嗰 5 個應該俾滾走")
	assert_eq(int(events[events.size() - 1]["data"]["i"]), total - 1, "最新一個應該保留")

func test_export_text_matches_written_events() -> void:
	EventLog.log_event("session_start")
	EventLog.log_event("frenzy_start")
	var text := EventLog.export_text()
	var lines := text.split("\n", false)
	assert_eq(lines.size(), 2)

func test_export_text_empty_when_no_log() -> void:
	assert_eq(EventLog.export_text(), "")

func test_clear_removes_all_events() -> void:
	EventLog.log_event("session_start")
	EventLog.clear()
	assert_eq(EventLog.count(), 0)
	assert_eq(EventLog.read_events().size(), 0)

func test_read_events_skips_corrupt_lines() -> void:
	# 直接寫一行壞 JSON 落 log 檔（模擬手動改壞／寫入中斷），讀返嚟唔應該
	# 累到成個 log 讀唔到，亦唔應該拋錯。
	var file := FileAccess.open(EventLog.LOG_PATH, FileAccess.WRITE)
	file.store_line("{ 呢一行唔係合法 JSON")
	file.store_line(JSON.stringify({"ts": 1.0, "version": 1, "type": "session_start", "data": {}}))
	file.close()
	var events := EventLog.read_events()
	assert_engine_error_count(1, "壞行預期觸發一次引擎解析錯誤，但唔應該累到成個 log 讀唔到")
	assert_eq(events.size(), 1, "壞行應該跳過，得返啱嗰行")
	assert_eq(events[0]["type"], "session_start")

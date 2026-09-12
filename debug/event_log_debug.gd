extends Control

## VR-08 debug 畫面：睇／匯出／清除 user://events.jsonl（EventLog，見
## systems/event_log.gd）。跟 `ads/ad_test.tscn`、`bench/fps_bench.tscn`
## 同一個做法：唔搶 `run/main_scene`，出 APK 前臨時將 project.godot 嘅
## run/main_scene 改去 res://debug/event_log_debug.tscn，或者 Godot
## editor 開呢個 scene 撳 F6（Run Current Scene）睇。

const EXPORT_PATH := "user://events_export.jsonl" # 匯出用固定檔名，方便 adb pull

@onready var _status_label: Label = %StatusLabel
@onready var _log_view: TextEdit = %LogView
@onready var _refresh_button: Button = %RefreshButton
@onready var _export_button: Button = %ExportButton
@onready var _clear_button: Button = %ClearButton


func _ready() -> void:
	_refresh_button.pressed.connect(_refresh)
	_export_button.pressed.connect(_on_export_pressed)
	_clear_button.pressed.connect(_on_clear_pressed)
	_refresh()


func _refresh() -> void:
	var text := EventLog.export_text()
	_log_view.text = text
	_set_status("%d 行（%s）" % [EventLog.count(), EventLog.LOG_PATH])


## 將現有 log 複製一份去固定檔名 EXPORT_PATH（同 user://events.jsonl 內容
## 一樣），俾人用 `adb pull` 攞——同 bench/fps_bench.gd 匯出報告嘅做法一致。
func _on_export_pressed() -> void:
	var text := EventLog.export_text()
	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("匯出失敗：寫唔到 %s" % EXPORT_PATH)
		return
	file.store_string(text)
	file.close()
	_set_status("已匯出 %d 行 → %s（adb pull 攞）" % [EventLog.count(), EXPORT_PATH])


func _on_clear_pressed() -> void:
	EventLog.clear()
	_refresh()
	_set_status("已清除 log")


func _set_status(text: String) -> void:
	_status_label.text = text
	print("[EventLogDebug] ", text)

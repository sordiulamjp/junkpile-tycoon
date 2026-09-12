extends GutTest

## VR-05：res://data/offline_report.gd 單元測試。
## 浣熊經理文案唔驗證死實文字內容（美術/文案可以再調），淨係驗證三級
## 分支揀啱、金額有出現喺文字入面。

func test_no_elapsed_time_message() -> void:
	var msg := OfflineReport.raccoon_message(0.0, 0.0, 28800.0)
	assert_string_contains(msg, "浣熊經理")

func test_elapsed_but_no_yield_message() -> void:
	var msg := OfflineReport.raccoon_message(0.0, 10.0, 28800.0)
	assert_string_contains(msg, "浣熊經理")
	assert_false(msg.contains("$"), "冇收成唔應該顯示金額")

func test_normal_yield_message_contains_amount() -> void:
	var msg := OfflineReport.raccoon_message(1234.0, 3600.0, 28800.0)
	assert_string_contains(msg, "1234")

func test_capped_yield_message_mentions_cap() -> void:
	var msg := OfflineReport.raccoon_message(50000.0, 28800.0, 28800.0)
	assert_string_contains(msg, "8 個鐘")
	assert_string_contains(msg, "50000")

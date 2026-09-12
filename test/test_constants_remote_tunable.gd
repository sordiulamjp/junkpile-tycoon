extends GutTest

## VR-08：GameConstants.REMOTE_TUNABLE_FIELDS 白名單要同 constants.gd
## 入面實際嘅 `# TUNE` 純量（float／int）欄位保持一致——加／刪一個純量
## TUNE 欄位而漏咗同步改白名單，呢個測試會 fail（見 constants.gd 白名單
## 頂嘅註解）。掃描源碼文字（`@export var <name>: <float|int> = ... # TUNE`），
## Dictionary／Array／Vector／Color 型別本身唔會俾呢條 regex 揀中，同
## 白名單刻意排除結構化 TUNE 欄位嘅設計一致。

func test_remote_tunable_fields_match_scalar_tune_exports_in_source() -> void:
	var file := FileAccess.open("res://data/constants.gd", FileAccess.READ)
	assert_not_null(file, "讀唔到 res://data/constants.gd")
	var text := file.get_as_text()
	file.close()

	var regex := RegEx.new()
	var err := regex.compile("@export var (\\w+): (float|int) = .*# TUNE")
	assert_eq(err, OK, "regex compile 失敗")

	var found: Array[String] = []
	for m in regex.search_all(text):
		found.append(m.get_string(1))
	found.sort()

	var whitelist: Array[String] = GameConstants.REMOTE_TUNABLE_FIELDS.duplicate()
	whitelist.sort()

	assert_eq(
		found, whitelist,
		"REMOTE_TUNABLE_FIELDS 白名單同 constants.gd 嘅純量 # TUNE 欄位對唔上，" +
		"加／刪咗欄位記得同步改 constants.gd 嘅 REMOTE_TUNABLE_FIELDS"
	)

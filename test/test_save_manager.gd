extends GutTest

## VR-05：res://data/save_manager.gd 單元測試。
## 覆蓋：預設狀態、存讀 round-trip（模擬「殺 App 重開資源不變」）、
## 檔案缺失／格式壞咗當新玩家、版本遷移框架。

func before_each() -> void:
	SaveManager.delete_save()

func after_each() -> void:
	SaveManager.delete_save()

const EPS := 0.001


func test_default_state_has_current_version() -> void:
	var state := SaveManager.default_state()
	assert_eq(state["version"], SaveManager.CURRENT_VERSION)
	assert_eq(state["cash"], 0.0)
	assert_eq(state["prestige_count"], 0)

func test_load_without_save_file_returns_default() -> void:
	var state := SaveManager.load_state()
	assert_eq(state["version"], SaveManager.CURRENT_VERSION)
	assert_eq(state["cash"], 0.0)

func test_save_then_load_round_trip_preserves_resources() -> void:
	# 對應驗收「殺 App 重開資源不變」：存檔再讀返嚟嘅資源數值應該同存之前一樣。
	var state := SaveManager.default_state()
	state["cash"] = 12345.5
	state["components"] = 678.0
	state["eco"] = 9.0
	state["lifetime_cash"] = 99999.0
	state["prestige_count"] = 3
	state["miners"] = 7
	state["miner_level"] = 15
	state["belt_level"] = 4
	state["refine_level"] = 2

	var err := SaveManager.save_state(state)
	assert_eq(err, OK)

	var loaded := SaveManager.load_state()
	assert_almost_eq(loaded["cash"], 12345.5, EPS)
	assert_almost_eq(loaded["components"], 678.0, EPS)
	assert_almost_eq(loaded["eco"], 9.0, EPS)
	assert_almost_eq(loaded["lifetime_cash"], 99999.0, EPS)
	# JSON 冇 int/float 之分，數量類欄位讀返嚟一律 float——用 int() 轉返先比較。
	assert_eq(int(loaded["prestige_count"]), 3)
	assert_eq(int(loaded["miners"]), 7)
	assert_eq(int(loaded["miner_level"]), 15)
	assert_eq(int(loaded["belt_level"]), 4)
	assert_eq(int(loaded["refine_level"]), 2)

func test_load_corrupt_file_falls_back_to_default() -> void:
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ 唔係合法 json ]]]")
	file.close()

	var state := SaveManager.load_state()
	assert_engine_error_count(1, "壞咗嘅 JSON 預期觸發一次引擎解析錯誤，但要 fallback 唔可以拋去 caller")
	assert_eq(state["version"], SaveManager.CURRENT_VERSION)
	assert_eq(state["cash"], 0.0)

func test_load_missing_save_key_falls_back_to_default() -> void:
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"some-other-key": {"cash": 1.0}}))
	file.close()

	var state := SaveManager.load_state()
	assert_eq(state["version"], SaveManager.CURRENT_VERSION)
	assert_eq(state["cash"], 0.0)


# ── 版本遷移框架 ─────────────────────────────────────────────

func test_migration_backfills_missing_fields_from_v0() -> void:
	# 模擬冇 version 欄位（v0）、殘缺嘅舊存檔
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({GameConstants.SAVE_KEY: {"cash": 500.0}}))
	file.close()

	var state := SaveManager.load_state()
	assert_eq(state["version"], SaveManager.CURRENT_VERSION, "應該陞級到最新版本")
	assert_almost_eq(state["cash"], 500.0, EPS, "已有嘅欄位唔應該畀遷移覆蓋")
	assert_eq(state["prestige_count"], 0, "缺咗嘅欄位應該補返預設值")
	assert_has(state, "lifetime_cash")
	assert_has(state, "last_save_unix")

func test_migration_is_idempotent_on_current_version() -> void:
	var state := SaveManager.default_state()
	state["cash"] = 42.0
	var migrated := SaveManager._migrate(state)
	assert_eq(migrated["version"], SaveManager.CURRENT_VERSION)
	assert_almost_eq(migrated["cash"], 42.0, EPS)

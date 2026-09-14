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
	assert_eq(state["unlocked_regions"], ["region1"]) # VR-11：新玩家開場只解鎖咗區域 1

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
	state["unlocked_regions"] = ["region1", "region2"]

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
	assert_eq(loaded["unlocked_regions"], ["region1", "region2"])

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

## VR-11（ALTA-227）：v1 存檔（VR-05 原本嗰個形狀，冇 unlocked_regions）
## 陞級到 v2 應該補返 unlocked_regions=["region1"]——舊存檔本身已經有
## 區域 1 嘅進度，唔應該當佢乜都未解鎖。
func test_migration_v1_to_v2_backfills_unlocked_regions() -> void:
	var v1_state := {
		"version": 1,
		"last_save_unix": Time.get_unix_time_from_system(),
		"cash": 500.0,
		"components": 0.0,
		"eco": 0.0,
		"lifetime_cash": 500.0,
		"prestige_count": 0,
		"miners": 2,
		"miner_level": 0,
		"belt_level": 1,
		"refine_level": 0,
	}
	var migrated := SaveManager._migrate(v1_state)
	assert_eq(migrated["version"], SaveManager.CURRENT_VERSION)
	assert_eq(migrated["unlocked_regions"], ["region1"])
	assert_almost_eq(migrated["cash"], 500.0, EPS, "遷移唔應該影響現有欄位")

func test_migration_v1_to_v2_does_not_overwrite_existing_unlocked_regions() -> void:
	var state := {"version": 1, "unlocked_regions": ["region1", "region2"]}
	var migrated := SaveManager._migrate(state)
	assert_eq(migrated["unlocked_regions"], ["region1", "region2"])

## ALTA-228（VR-12）：v2 存檔（VR-11 嗰個形狀，冇 mine_zone）陞級到 v3
## 應該補返預設 mine_zone（層 1 開、層 2／3 鎖、礦車／倉庫 Lv1、推堆墊未買）。
func test_migration_v2_to_v3_backfills_mine_zone() -> void:
	var v2_state := {"version": 2, "cash": 500.0, "unlocked_regions": ["region1"]}
	var migrated := SaveManager._migrate(v2_state)
	assert_eq(migrated["version"], SaveManager.CURRENT_VERSION)
	var mine_zone: Dictionary = migrated["mine_zone"]
	assert_eq(mine_zone["layer_unlocked"], [true, false, false])
	assert_eq(mine_zone["push_tier"], 0)
	assert_almost_eq(migrated["cash"], 500.0, EPS, "遷移唔應該影響現有欄位")

func test_migration_v2_to_v3_does_not_overwrite_existing_mine_zone() -> void:
	var state := {"version": 2, "mine_zone": {"layer_unlocked": [true, true, false], "push_tier": 2}}
	var migrated := SaveManager._migrate(state)
	assert_eq(migrated["mine_zone"]["layer_unlocked"], [true, true, false])
	assert_eq(migrated["mine_zone"]["push_tier"], 2)

## ALTA-229（VR-13）：v3 存檔（VR-12 嗰個形狀，冇 region2_zone）陞級到
## v4 應該補返預設 region2_zone（UPGRADE 小屋未買）。
func test_migration_v3_to_v4_backfills_region2_zone() -> void:
	var v3_state := {"version": 3, "cash": 500.0, "unlocked_regions": ["region1", "region2"]}
	var migrated := SaveManager._migrate(v3_state)
	assert_eq(migrated["version"], SaveManager.CURRENT_VERSION)
	assert_eq(migrated["region2_zone"]["shack_tier"], 0)
	assert_almost_eq(migrated["cash"], 500.0, EPS, "遷移唔應該影響現有欄位")

func test_migration_v3_to_v4_does_not_overwrite_existing_region2_zone() -> void:
	var state := {"version": 3, "region2_zone": {"shack_tier": 2}}
	var migrated := SaveManager._migrate(state)
	assert_eq(migrated["region2_zone"]["shack_tier"], 2)

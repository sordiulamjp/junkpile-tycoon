extends GutTest

## VR-08：res://systems/remote_constants.gd 單元測試（純邏輯，冇網絡）。
## 覆蓋驗收「GUT 覆蓋合併／壞 JSON fallback」：
##   - 白名單內、型別啱嘅欄位先會覆寫，其餘（docx 欄位／結構化 TUNE／
##     唔喺白名單）一律唔理
##   - 壞 JSON（null／字串／陣列／唔啱型別／NaN／Infinity）全部 fallback，
##     唔會拋錯，亦唔會累到其餘啱嘅 key 一齊唔覆寫
##   - apply_overrides() 淨改 overrides 入面有嘅欄位，其餘維持 base 原值，
##     亦唔會改到傳入嗰個 base 本身（duplicate）
##   - 本機 cache（read_cache／write_cache）：Review 意見（ALTA-155）—
##     starting_cash 呢類喺 GameState._init() 已經俾讀走嘅欄位，淨係靠
##     background fetch set() 落 `c` 太遲，一定要有 cache 俾 main.gd
##     喺構造 GameState 之前同步讀返套用，先叫「重開即生效」

var c: GameConstants

func before_each() -> void:
	c = GameConstants.new()
	RemoteConstants.clear_cache()

func after_each() -> void:
	RemoteConstants.clear_cache()

const EPS := 0.001


# ── sanitize_overrides：合併／白名單 ──────────────────────────

func test_sanitize_accepts_whitelisted_scalar_field() -> void:
	var overrides := RemoteConstants.sanitize_overrides({"miner_cost_base": 20.0})
	assert_eq(overrides.size(), 1)
	assert_almost_eq(overrides["miner_cost_base"], 20.0, EPS)

func test_sanitize_ignores_unknown_key() -> void:
	var overrides := RemoteConstants.sanitize_overrides({"this_is_not_a_real_field": 999.0})
	assert_true(overrides.is_empty())

func test_sanitize_ignores_docx_locked_field() -> void:
	# trash_meter_cap 係 docx 已定案（A 部），唔喺 REMOTE_TUNABLE_FIELDS 白名單。
	assert_false(GameConstants.REMOTE_TUNABLE_FIELDS.has("trash_meter_cap"))
	var overrides := RemoteConstants.sanitize_overrides({"trash_meter_cap": 999})
	assert_true(overrides.is_empty())

func test_sanitize_ignores_structured_tune_field() -> void:
	# offline_bands 係 TUNE 但係 Array[Dictionary]，呢期未支援遠端覆寫。
	assert_false(GameConstants.REMOTE_TUNABLE_FIELDS.has("offline_bands"))
	var overrides := RemoteConstants.sanitize_overrides({"offline_bands": []})
	assert_true(overrides.is_empty())

func test_sanitize_rounds_int_field() -> void:
	var overrides := RemoteConstants.sanitize_overrides({"belt_level_cap": 12.7})
	assert_eq(overrides["belt_level_cap"], 13)

func test_sanitize_merges_multiple_valid_and_invalid_keys() -> void:
	var overrides := RemoteConstants.sanitize_overrides({
		"miner_cost_base": 25.0,
		"frenzy_mult": 6.0,
		"bogus_field": "haha",
	})
	assert_eq(overrides.size(), 2)
	assert_almost_eq(overrides["miner_cost_base"], 25.0, EPS)
	assert_almost_eq(overrides["frenzy_mult"], 6.0, EPS)


# ── 壞 JSON fallback：一個壞唔會累到其餘 ──────────────────────

func test_sanitize_rejects_non_dictionary_top_level() -> void:
	assert_true(RemoteConstants.sanitize_overrides(null).is_empty())
	assert_true(RemoteConstants.sanitize_overrides("唔係 dictionary").is_empty())
	assert_true(RemoteConstants.sanitize_overrides([1, 2, 3]).is_empty())
	assert_true(RemoteConstants.sanitize_overrides(42).is_empty())

func test_sanitize_rejects_wrong_type_value() -> void:
	var overrides := RemoteConstants.sanitize_overrides({"miner_cost_base": "咁都得？"})
	assert_true(overrides.is_empty())

func test_sanitize_rejects_nan_and_infinity() -> void:
	var overrides := RemoteConstants.sanitize_overrides({
		"miner_cost_base": NAN,
		"frenzy_mult": INF,
		"belt_step": -INF,
	})
	assert_true(overrides.is_empty())

func test_sanitize_one_bad_key_does_not_block_other_valid_keys() -> void:
	var overrides := RemoteConstants.sanitize_overrides({
		"miner_cost_base": NAN,       # 壞
		"frenzy_mult": 8.0,           # 啱
		"unknown_field": 1.0,        # 唔喺白名單
	})
	assert_eq(overrides.size(), 1)
	assert_almost_eq(overrides["frenzy_mult"], 8.0, EPS)


# ── apply_overrides：套用／唔改 base ──────────────────────────

func test_apply_overrides_sets_only_given_fields() -> void:
	var result := RemoteConstants.apply_overrides(c, {"miner_cost_base": 99.0})
	assert_almost_eq(result.miner_cost_base, 99.0, EPS)
	assert_almost_eq(result.miner_cost_mult, c.miner_cost_mult, EPS, "冇覆寫嘅欄位應該維持原值")

func test_apply_overrides_does_not_mutate_base() -> void:
	var original_cost: float = c.miner_cost_base
	RemoteConstants.apply_overrides(c, {"miner_cost_base": 12345.0})
	assert_almost_eq(c.miner_cost_base, original_cost, EPS, "base 本身唔應該被改")

func test_apply_empty_overrides_is_no_op() -> void:
	var result := RemoteConstants.apply_overrides(c, {})
	assert_almost_eq(result.miner_cost_base, c.miner_cost_base, EPS)
	assert_almost_eq(result.frenzy_mult, c.frenzy_mult, EPS)


# ── 本機 cache：read_cache／write_cache／clear_cache ──────────

func test_read_cache_without_file_returns_empty() -> void:
	assert_true(RemoteConstants.read_cache().is_empty())

func test_write_then_read_cache_round_trip() -> void:
	RemoteConstants.write_cache({"miner_cost_base": 42.0, "belt_level_cap": 7})
	var cached := RemoteConstants.read_cache()
	assert_almost_eq(cached["miner_cost_base"], 42.0, EPS)
	assert_eq(cached["belt_level_cap"], 7)

func test_write_empty_cache_then_read_is_empty() -> void:
	# 伺服器話「而家冇任何覆寫」都要照寫落 cache（見 main.gd
	# _on_remote_constants_loaded()）——下次讀返嚟應該係空，唔係當冇寫過。
	RemoteConstants.write_cache({"miner_cost_base": 1.0})
	RemoteConstants.write_cache({})
	assert_true(RemoteConstants.read_cache().is_empty())

func test_read_cache_resanitizes_and_drops_bad_keys() -> void:
	# 模擬 cache 檔案俾人手改壞／版本升級後白名單收窄：讀返嚟一樣要淨返
	# 啱嘅 key，唔會將壞值套用出去。
	var file := FileAccess.open(RemoteConstants.CACHE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"miner_cost_base": 5.0, "not_a_real_field": 999.0}))
	file.close()
	var cached := RemoteConstants.read_cache()
	assert_eq(cached.size(), 1)
	assert_almost_eq(cached["miner_cost_base"], 5.0, EPS)

func test_read_cache_corrupt_file_falls_back_to_empty() -> void:
	var file := FileAccess.open(RemoteConstants.CACHE_PATH, FileAccess.WRITE)
	file.store_string("{ 壞咗嘅 JSON")
	file.close()
	var cached := RemoteConstants.read_cache()
	assert_engine_error_count(1, "壞 cache 預期觸發一次引擎解析錯誤，但唔可以拋去 caller")
	assert_true(cached.is_empty())

func test_clear_cache_removes_file() -> void:
	RemoteConstants.write_cache({"miner_cost_base": 1.0})
	RemoteConstants.clear_cache()
	assert_true(RemoteConstants.read_cache().is_empty())

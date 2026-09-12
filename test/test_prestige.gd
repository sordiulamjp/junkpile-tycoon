extends GutTest

## VR-05：res://data/prestige.gd 單元測試。
## 覆蓋：門檻判斷、重置清礦工/升級/Cash 但保留 prestige_count/lifetime_cash、
## 永久收入倍率隨重置次數遞增，同倍率實際套用去離線結算嘅效果。

var c: GameConstants

func before_each() -> void:
	c = GameConstants.new()

const EPS := 0.001

func _state(overrides: Dictionary = {}) -> Dictionary:
	var s := SaveManager.default_state()
	for key in overrides:
		s[key] = overrides[key]
	return s


# ── 門檻判斷 ─────────────────────────────────────────────────

func test_can_prestige_false_below_threshold() -> void:
	var state := _state({"lifetime_cash": c.prestige_threshold(0) - 1.0})
	assert_false(Prestige.can_prestige(c, state))

func test_can_prestige_true_at_threshold() -> void:
	var state := _state({"lifetime_cash": c.prestige_threshold(0)})
	assert_true(Prestige.can_prestige(c, state))

func test_can_prestige_threshold_grows_after_reset() -> void:
	# 門檻 = base × growth^n，重置一次後（n=1）門檻應該係第一次嘅 6 倍
	var state := _state({"prestige_count": 1, "lifetime_cash": c.prestige_threshold(0)})
	assert_false(Prestige.can_prestige(c, state), "第二次重置門檻應該高過第一次")
	state["lifetime_cash"] = c.prestige_threshold(1)
	assert_true(Prestige.can_prestige(c, state))


# ── 重置：清礦工/升級/Cash，保留 prestige_count/lifetime_cash ──────

func test_reset_clears_cash_and_upgrades_but_keeps_lifetime_and_count() -> void:
	var state := _state({
		"cash": 99999999.0,
		"components": 500.0,
		"miners": 12,
		"miner_level": 40,
		"belt_level": 10,
		"refine_level": 20,
		"lifetime_cash": 20000000.0,
		"prestige_count": 2,
	})
	var new_state := Prestige.reset(state)

	assert_eq(new_state["prestige_count"], 3, "prestige_count 應該 +1")
	assert_almost_eq(new_state["lifetime_cash"], 20000000.0, EPS, "lifetime_cash 唔清零")
	assert_eq(new_state["cash"], 0.0)
	assert_eq(new_state["components"], 0.0)
	assert_eq(new_state["miners"], 0)
	assert_eq(new_state["miner_level"], 0)
	assert_eq(new_state["belt_level"], 1)
	assert_eq(new_state["refine_level"], 0)

func test_reset_from_zero_starts_first_prestige() -> void:
	var new_state := Prestige.reset(_state())
	assert_eq(new_state["prestige_count"], 1)


# ── 永久收入倍率 ─────────────────────────────────────────────

func test_income_multiplier_no_reset_is_one() -> void:
	assert_almost_eq(Prestige.income_multiplier(c, 0), 1.0, EPS)

func test_income_multiplier_scales_linearly_per_reset() -> void:
	assert_almost_eq(Prestige.income_multiplier(c, 1), 1.5, EPS)
	assert_almost_eq(Prestige.income_multiplier(c, 2), 2.0, EPS)
	assert_almost_eq(Prestige.income_multiplier(c, 4), 3.0, EPS)


# ── 倍率實際套用喺離線結算 ───────────────────────────────────

func test_prestige_bonus_applies_to_offline_yield() -> void:
	var no_reset := _state({"last_save_unix": 0.0, "prestige_count": 0})
	var one_reset := _state({"last_save_unix": 0.0, "prestige_count": 1})

	var base_result := OfflineSettlement.settle(c, no_reset, 3600.0, 10.0)
	var boosted_result := OfflineSettlement.settle(c, one_reset, 3600.0, 10.0)

	assert_almost_eq(boosted_result["cash_yield"], base_result["cash_yield"] * 1.5, EPS)

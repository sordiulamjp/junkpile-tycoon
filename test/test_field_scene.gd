extends GutTest

## ALTA-228（field.tscn 萬向車重做）Reviewer round 3：「新入口場景零測試」
## ——`run/main_scene` 已經切去 scenes/field.tscn，但呢個場景之前一個
## smoke test 都冇。跟 test_mine_zone.gd 同一風格：真係起場景，測真實
## callback，唔淨係喺呢度重新斷言一次數值公式。
##
## 車物理（真實碰撞／`body_entered`）依賴引擎每幀嘅 physics broadphase，
## GUT 嘅 simulate() 純粹直接 call `_physics_process()`，唔會行到真正
## 一個 physics tick——同 test_mine_zone.gd 一致做法：直接 call 返個
## private handler（`_on_sell_area_entered()` / UnlockPanel
## `_on_body_entered()`），唔靠引擎真正觸發 Area3D signal。

var field: Node3D
const EPS := 0.001

func before_each() -> void:
	SaveManager.delete_save()
	Wallet.reset()

func after_each() -> void:
	if is_instance_valid(field):
		field.free()
	SaveManager.delete_save()
	Wallet.reset()

func _load_field() -> Node3D:
	var scene: PackedScene = load("res://scenes/field.tscn")
	field = scene.instantiate()
	add_child_autofree(field)
	return field


# ── 場景載入：唔係獨立零件，係 run/main_scene 真身 ──────────

func test_field_scene_loads_and_builds_car_mine_hud() -> void:
	_load_field()
	assert_true(field.is_inside_tree())
	assert_not_null(field._car)
	assert_not_null(field.mine)
	assert_not_null(field._hud)
	assert_true(field._car is CharacterBody3D)

func test_tick_advances_mine_income_into_shared_state_cash() -> void:
	_load_field()
	var cash_before: float = field.state.cash
	field.mine.tick(1.0)
	assert_gt(field.state.cash, cash_before, "層 1 開場已經出緊礦，一幀之後 Cash 應該加咗")


# ── 搖桿向量 → 車郁（用戶 18:41 規格：萬向移動） ─────────────

func test_joystick_vector_moves_car_in_input_direction() -> void:
	_load_field()
	var start_y: float = field._car.position.y
	field._joy_down = true
	field._joy_vec = Vector2(0.0, 1.0) # site +y（撳「前」）
	for _i in range(30):
		field._physics_process(1.0 / 30.0)
	assert_gt(field._car.position.y, start_y, "撳搖桿向前應該推車郁")

func test_wasd_keys_vec_moves_car_when_joystick_not_down() -> void:
	_load_field()
	var start_x: float = field._car.position.x
	field._joy_down = false
	field._keys_vec = Vector2(1.0, 0.0) # D／→
	for _i in range(30):
		field._physics_process(1.0 / 30.0)
	assert_gt(field._car.position.x, start_x, "冇撳搖桿嗰陣 WASD 都應該郁到車")

# ── 礦粒入 SellArea → cash 加（鏟斗 tier 倍率） ──────────────

func _fake_ore_body(tier: String) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_meta("slot", {"tier": tier})
	add_child_autofree(body)
	return body

func test_ore_entering_sell_area_credits_cash_at_base_tier() -> void:
	_load_field()
	field.state.cash = 0.0
	var body := _fake_ore_body("silver")
	field._on_sell_area_entered(body)
	assert_almost_eq(field.state.cash, field.mine.state.c.ore_value("silver"), EPS)

## Round 2 review 揪出嘅 off-by-one：舊碼 `push_tier_scoop_mult[clampi(push_tier,0,2)]`
## 喺 push_tier=1 嗰陣會攞咗「下一級」嘅倍率（等同預支未買嘅升級）。
func test_ore_sell_value_uses_current_push_tier_not_next_one() -> void:
	_load_field()
	field.state.cash = 1000000.0
	for _p in field.mine._layer_unlock_panels + field.mine._push_panels + field._dep_panels: _p.ore_fed = _p.ore_cost # 2026-09-17：礦直接推入升級格，呢度當已推夠
	field.mine._on_push_tap("push0", field.mine.state.c.push_tier_cost[0]) # push_tier -> 1
	field.state.cash = 0.0

	var body := _fake_ore_body("gold")
	field._on_sell_area_entered(body)

	var expected: float = field.mine.state.c.ore_value("gold") * field.mine.state.c.push_tier_scoop_mult[0]
	assert_almost_eq(field.state.cash, expected, EPS)


# ── 墊／解鎖板：車駛入即觸發，唔使撳掣（用戶 18:41 規格） ────

func test_push_pad_triggers_on_character_body_entry_not_just_tap() -> void:
	_load_field()
	field.state.cash = field.mine.state.c.push_tier_cost[0]
	var pad: UnlockPanel = field.mine._push_panels[0]

	pad._on_body_entered(autofree(CharacterBody3D.new()))

	assert_eq(field.mine.state.push_tier, 1, "車駛入推堆墊應該同撳掣一樣觸發購買")

func test_layer_unlock_panel_triggers_on_character_body_entry() -> void:
	_load_field()
	field.state.cash = field.mine.state.layer_unlock_cost(1)
	for _p in field.mine._layer_unlock_panels + field.mine._push_panels + field._dep_panels: _p.ore_fed = _p.ore_cost # 2026-09-17：礦直接推入升級格，呢度當已推夠
	var panel: UnlockPanel = field.mine._layer_unlock_panels[0] # 對應層 2（idx1）

	panel._on_body_entered(autofree(CharacterBody3D.new()))

	assert_true(field.mine.state.layer_unlocked[1], "車駛入層解鎖板應該同撳掣一樣觸發解鎖")

func test_body_entered_ignores_non_character_bodies() -> void:
	_load_field()
	field.state.cash = field.mine.state.c.push_tier_cost[0]
	var pad: UnlockPanel = field.mine._push_panels[0]

	pad._on_body_entered(autofree(RigidBody3D.new())) # 礦粒唔應該誤觸發

	assert_eq(field.mine.state.push_tier, 0)

## Reviewer round 4：舊位（掛喺 `_layer_center(idx)` 上面、z=層高+0.3）
## 離地 0.85 起跳，企喺已經有實心 collider 嘅層 1 台後面——上面
## `test_layer_unlock_panel_triggers_on_character_body_entry()` 直接 call
## `_on_body_entered()` 繞過咗幾何，測唔到「車實際去唔去到」。呢個補返
## 個幾何斷言：z 一定要跌入車 collision box 嘅高度範圍（先撞得到），y
## 一定要企喺層 1 collider 嘅 y 範圍（[0, DEPTH_STEP]）前面（先唔會俾層
## 台實心體擋住條路）。
func test_layer_unlock_panel_is_geometrically_reachable_by_car() -> void:
	_load_field()
	var panel: UnlockPanel = field.mine._layer_unlock_panels[0]
	var car_half_z: float = 0.13 # field.gd _build_car() 車 collision box z size 0.26 嘅一半

	assert_between(
		panel.position.z, field._car.position.z - car_half_z, field._car.position.z + car_half_z,
		"解鎖板 z 要跌入車 collision box 嘅高度範圍先撞得到"
	)
	assert_lt(
		panel.position.y, 0.0,
		"解鎖板一定要企喺層 1 collider（y ∈ [0, DEPTH_STEP]）前面，車先去得到"
	)


# ── 存檔：統一去返共用 Wallet／"cash" 欄位，唔再自成一格 ─────

func test_save_writes_shared_cash_field_not_a_private_field_cash_key() -> void:
	_load_field()
	field.state.cash = 4242.0
	field.state.components = 3.0
	field.state.eco = 2.0

	field._save_game()

	var saved := SaveManager.load_state()
	assert_almost_eq(float(saved.get("cash", -1.0)), 4242.0, EPS, "應該寫落共用 \"cash\" 欄位")
	assert_false(saved.has("field_cash"), "唔應該再有私家 field_cash 欄位")
	assert_almost_eq(Wallet.cash, 4242.0, EPS, "存檔之前應該同步埋 Wallet")

func test_reload_after_save_restores_cash_through_wallet() -> void:
	_load_field()
	field.state.cash = 777.0
	field._save_game()
	field.free()

	_load_field()
	assert_almost_eq(field.state.cash, 777.0, EPS, "重開應該經 Wallet 讀返共用 cash")


# ── 熔爐／層台：加咗 collider，車唔應該直穿（Reviewer round 3 次要項） ─

func _find_static_body(root: Node) -> StaticBody3D:
	for child in root.get_children():
		if child is StaticBody3D:
			return child
	return null

func test_furnace_body_has_a_static_collider() -> void:
	_load_field()
	var furnace: Node3D = field._site.get_node("Furnace")
	assert_not_null(_find_static_body(furnace), "熔爐本體應該有 StaticBody3D 擋住車")

func test_layer_platforms_have_static_colliders() -> void:
	_load_field()
	for idx in range(MineConstants.LAYER_COUNT):
		var collider: Node = field.mine._layer_root.get_node_or_null("LayerCollider%d" % idx)
		assert_not_null(collider, "層 %d 應該有 collider" % idx)
		assert_true(collider is StaticBody3D)


# ══════════════════════ ALTA-241（VR-16）掛機自動化 ══════════════════════
# 淨係直接 call 私家 handler／tick 方法斷言結果，跟呢個檔案一直以嚟嘅
# 風格一致（唔靠引擎真正行 physics/tween 一個完整循環）。

# ── 離線結算：接返三段管線嘅速率，唔計 AI 司機／運輸隊嘅收入 ────────

func test_settle_offline_shows_panel_with_pipeline_based_yield() -> void:
	_load_field()
	var rate: float = field._pipeline_rate()
	var now := Time.get_unix_time_from_system()

	field._settle_offline({"last_save_unix": now - 3600.0})

	var expected: float = rate * 3600.0 # 首 2 小時 100%（OfflineSettlement 分段）
	assert_true(field._offline_panel.visible, "有離線時間就應該彈浣熊經理面板")
	assert_almost_eq(field._offline_pending, expected, 5.0)

func test_settle_offline_no_panel_without_prior_last_save_unix() -> void:
	_load_field()
	field._settle_offline({}) # 冇存檔（第一次開場）唔應該有離線結算
	assert_false(field._offline_panel.visible)
	assert_eq(field._offline_pending, 0.0)

func test_offline_claim_button_credits_pending_cash_and_hides_panel() -> void:
	_load_field()
	field.state.cash = 100.0
	field._offline_pending = 500.0
	field._offline_panel.visible = true

	field._offline_claim_button.pressed.emit()

	assert_almost_eq(field.state.cash, 600.0, EPS)
	assert_eq(field._offline_pending, 0.0)
	assert_false(field._offline_panel.visible)

func test_offline_double_button_is_a_disabled_placeholder() -> void:
	_load_field()
	assert_true(field._offline_double_button.disabled, "VR-07 未接，×2 睇廣告掣要停用")


# ── AI 司機狀態機：揾堆／鏟／賣 ──────────────────────────────

func _fill_bucket(n: int) -> void:
	for _i in range(n):
		var body := RigidBody3D.new()
		body.position = field._car.transform * Vector3(0.0, 0.3, 0.0) # 車前捕獲區入面
		field._kick_root.add_child(body)
		field._kicked.append({"slot": {"tier": "silver"}, "node": body, "t": 0.0})

func test_ai_steer_targets_an_ore_pile_while_seeking() -> void:
	_load_field()
	field._ai_mode = "heap"
	field._car.position = Vector3(1000.0, 1000.0, field.CAR_Z) # 遠離礦場，確保未去到目標

	var dir: Vector2 = field._ai_steer(0.1)

	assert_ne(field._ai_target, Vector2.INF, "場上成千粒礦，應該即刻揾到一堆")
	assert_gt(dir.length(), 0.0, "未去到目標應該有方向輸出")

func test_ai_steer_switches_to_furnace_once_bucket_60_percent_full() -> void:
	_load_field()
	field._ai_mode = "heap"
	var cap: int = field.CARGO_CAP[0] # push_tier 0（開場鏟斗）
	_fill_bucket(int(float(cap) * 0.6))

	field._ai_steer(0.1)

	assert_eq(field._ai_mode, "furnace", "夠 6 成滿應該轉去揸去爐賣")

func test_ai_steer_stays_in_heap_mode_below_60_percent_full() -> void:
	_load_field()
	field._ai_mode = "heap"
	var cap: int = field.CARGO_CAP[0]
	_fill_bucket(int(float(cap) * 0.6) - 2) # 差少少先夠 6 成

	field._ai_steer(0.1)

	assert_eq(field._ai_mode, "heap", "未夠 6 成唔應該轉去爐")

func test_ai_steer_returns_to_heap_after_bucket_emptied_near_furnace() -> void:
	_load_field()
	field._ai_mode = "furnace"
	field._ai_target = field.FURNACE_POS + Vector2(-0.3, -0.6)
	field._car.position = field._site_to_local(field._ai_target, field.CAR_Z)
	field._kicked.clear() # 賣晒，桶清空

	field._ai_steer(0.1)

	assert_eq(field._ai_mode, "heap", "去到爐、桶清空應該轉返去揾礦堆")
	assert_ne(field._ai_target, Vector2.INF, "應該即刻揾到下一堆")

func test_ai_activates_after_idle_threshold_and_releases_on_player_input() -> void:
	_load_field()
	field._ai_unlocked = true
	field._ai_on = true
	field._joy_down = false
	field._keys_vec = Vector2.ZERO

	for _i in range(int(field.AI_IDLE_SECS) - 1): # issue 原文：6 秒冇操作先自動（field.AI_IDLE_SECS）
		field._physics_process(1.0)
	assert_false(field._ai_active, "未夠 AI_IDLE_SECS 唔應該自動接手")

	field._physics_process(1.5) # 累計 idle 時間跨過 AI_IDLE_SECS
	assert_true(field._ai_active, "6 秒冇操作應該自動揸")

	field._joy_down = true
	field._joy_vec = Vector2(1.0, 0.0)
	field._physics_process(1.0 / 30.0)
	assert_false(field._ai_active, "玩家一掂搖桿應該即刻接手")


# ── AI 司機解鎖：Components 或 Cash（issue：Components 平，優先扣） ──

func test_ai_unlock_prefers_components_when_affordable() -> void:
	_load_field()
	field.state.components = 20.0
	field.state.cash = 0.0

	field._on_ai_pressed()

	assert_true(field._ai_unlocked)
	assert_almost_eq(field.state.components, 10.0, EPS, "應該扣 10 粒 Components")
	assert_almost_eq(field.state.cash, 0.0, EPS, "夠 Components 就唔應該掃 Cash")

func test_ai_unlock_falls_back_to_cash_when_no_components() -> void:
	_load_field()
	field.state.components = 0.0
	field.state.cash = 500.0

	field._on_ai_pressed()

	assert_true(field._ai_unlocked)
	assert_almost_eq(field.state.cash, 0.0, EPS)

func test_ai_unlock_fails_when_neither_currency_is_enough() -> void:
	_load_field()
	field.state.components = 5.0
	field.state.cash = 100.0

	field._on_ai_pressed()

	assert_false(field._ai_unlocked)

func test_ai_button_press_toggles_on_off_once_unlocked() -> void:
	_load_field()
	field._ai_unlocked = true
	field._ai_on = true

	field._on_ai_pressed()
	assert_false(field._ai_on)
	field._on_ai_pressed()
	assert_true(field._ai_on)


# ── 經理自動升級：淨升緊瓶頸段，留 20% 現金儲備 ──────────────

func test_manager_tick_upgrades_the_current_bottleneck_stage() -> void:
	_load_field()
	field._mgr_unlocked = true
	field._mgr_on = true
	field.state.cash = 10000.0
	assert_eq(field.mine.state.bottleneck_stage(), "layers", "預設層 1 產能最細，應該係瓶頸")
	var cost: float = field.mine.state.next_layer_speed_cost(0)

	field._manager_tick(5.0)

	assert_eq(field.mine.state.layer_level[0], 1, "經理應該自動幫瓶頸段（層 1）升級")
	assert_eq(field.mine.state.cart_level, 1, "非瓶頸段唔應該被郁")
	assert_eq(field.mine.state.warehouse_level, 1, "非瓶頸段唔應該被郁")
	assert_almost_eq(field.state.cash, 10000.0 - cost, EPS)

func test_manager_tick_waits_for_the_5_second_interval() -> void:
	_load_field()
	field._mgr_unlocked = true
	field._mgr_on = true
	field.state.cash = 10000.0

	field._manager_tick(2.0)

	assert_eq(field.mine.state.layer_level[0], 0, "未夠 5 秒唔應該升級")
	assert_almost_eq(field.state.cash, 10000.0, EPS)

func test_manager_tick_keeps_20_percent_cash_reserve() -> void:
	_load_field()
	field._mgr_unlocked = true
	field._mgr_on = true
	var cost: float = field.mine.state.next_layer_speed_cost(0)
	field.state.cash = cost * 1.1 # 買咗之後淨返 <20%，唔應該買
	for _p in field.mine._layer_unlock_panels + field.mine._push_panels + field._dep_panels: _p.ore_fed = _p.ore_cost # 2026-09-17：礦直接推入升級格，呢度當已推夠

	field._manager_tick(5.0)

	assert_eq(field.mine.state.layer_level[0], 0, "會跌穿 20% 現金儲備，唔應該買")
	assert_almost_eq(field.state.cash, cost * 1.1, EPS)

func test_manager_tick_noop_when_toggle_off() -> void:
	_load_field()
	field._mgr_unlocked = true
	field._mgr_on = false
	field.state.cash = 10000.0

	field._manager_tick(5.0)

	assert_eq(field.mine.state.layer_level[0], 0)
	assert_almost_eq(field.state.cash, 10000.0, EPS)


# ── 地面運輸隊：每 10 秒派一個機械人（smoke test） ──────────────

func test_surface_team_tick_dispatches_a_bot_after_10_seconds() -> void:
	_load_field()
	field.mine.state.warehouse_level = 2 # 2026-09-17：運輸隊要倉庫 Lv2 先開
	var before: int = field._site.get_child_count()

	field._surface_team_tick(10.0)

	assert_gt(field._site.get_child_count(), before, "夠 10 秒應該派一個機械人")

func test_surface_team_tick_does_nothing_before_10_seconds() -> void:
	_load_field()
	var before: int = field._site.get_child_count()

	field._surface_team_tick(4.0)

	assert_eq(field._site.get_child_count(), before, "未夠 10 秒唔應該派人")


# ── 用戶 2026-09-18：車房 / 拖車仔 / 走道 / 鑽機 / 逐格露出 ──

func test_vein_pads_reveal_one_at_a_time_in_cost_order() -> void:
	var field = _load_field()
	assert_true(field._dep_panels[0].visible, "第一條（最平）礦脈墊開場應該見到")
	for i in range(1, field._dep_panels.size()):
		assert_false(field._dep_panels[i].visible, "其餘礦脈墊要等上一條買咗先露出")
	field.state.cash = 1e9
	for _p in field._dep_panels: _p.ore_fed = _p.ore_cost
	field._on_deposit_tap("deposit2", field.DEPOSITS[2][3]) # 跳級買唔到
	assert_false(field._dep_unlocked[2], "未買礦脈 1 唔可以買礦脈 2")
	field._on_deposit_tap("deposit1", field.DEPOSITS[1][3])
	assert_true(field._dep_unlocked[1])
	assert_true(field._dep_panels[1].visible, "買咗礦脈 1 就露出礦脈 2 嘅墊")
	assert_true(field._hire_pads[0].visible, "礦脈開咗先見到請拖車仔墊")
	assert_false(field._drill_pads[0].visible, "未請拖車仔唔見鑽機墊")

func test_hire_hauler_spawns_and_levels_up_until_max() -> void:
	var field = _load_field()
	field.state.cash = 1e9
	for _p in field._dep_panels: _p.ore_fed = _p.ore_cost
	field._on_hire_tap("hire1", field._hauler_cost(1, 0))
	assert_eq(field._hauler_lvl[1], 0, "礦脈未開唔可以請")
	field._on_deposit_tap("deposit1", field.DEPOSITS[1][3])
	field._on_hire_tap("hire1", field._hauler_cost(1, 0))
	assert_eq(field._hauler_lvl[1], 1)
	assert_not_null(field._haulers[1], "請咗就有一架拖車仔喺場")
	assert_true(field._drill_pads[0].visible, "請咗拖車仔先見到鑽機墊")
	for _i in range(10):
		field._on_hire_tap("hire1", field._hauler_cost(1, field._hauler_lvl[1]))
	assert_eq(field._hauler_lvl[1], Hauler.MAX_LEVEL, "升到頂就停")
	assert_eq((field._haulers[1] as Hauler).cap, Hauler.level_cap(Hauler.MAX_LEVEL))

func test_hauler_loads_from_its_own_vein_and_sells_at_discount() -> void:
	var field = _load_field()
	field.state.cash = 1e9
	for _p in field._dep_panels: _p.ore_fed = _p.ore_cost
	field._on_deposit_tap("deposit1", field.DEPOSITS[1][3])
	field._on_hire_tap("hire1", field._hauler_cost(1, 0))
	var h: Hauler = field._haulers[1]
	for s in field._dep_slots[1]: s["gone"] = false # 開礦脈嘅湧出動畫仲未完，直接當鋪滿
	var got: Array = field._hauler_load(h, 1)
	assert_eq(got.size(), h.cap, "一次執 cap 粒")
	var before: float = field._furnace_total
	field._hauler_sell(h, ["silver"])
	var expect: float = field.mine.state.c.ore_value_silver * field.HAULER_SELL_MULT
	assert_almost_eq(field._furnace_total - before, expect, 0.01, "拖車仔賣礦打 7 折，冇門倍數")

func test_garage_buy_raises_speed_cargo_price_and_charges_cash() -> void:
	var field = _load_field()
	field.state.cash = 1000.0
	var cap0: int = field._cargo_cap()
	field._on_garage_buy("cargo")
	assert_eq(field._garage["cargo"], 1)
	assert_almost_eq(field.state.cash, 1000.0 - GaragePanel.cost_for("cargo", 0), 0.01)
	assert_gt(field._cargo_cap(), cap0, "載量升級要見得到")
	field._on_garage_buy("speed")
	assert_gt(field._garage_speed_mult(), 1.0)
	field._on_garage_buy("price")
	assert_gt(field._price_mult(), 1.0)
	field.state.cash = 0.0
	field._on_garage_buy("price")
	assert_eq(field._garage["price"], 1, "冇錢唔升")

func test_walkway_unlock_builds_belt_and_hopper_sells_ore() -> void:
	var field = _load_field()
	field.state.cash = 1e9
	field._walk_pad.ore_fed = field._walk_pad.ore_cost
	field._on_walkway_tap("walkway", field.WALKWAY_COST)
	assert_true(field._walkway_unlocked)
	assert_not_null(field._walkway)
	# 一粒剛體礦放入漏斗
	var s: Dictionary = field._slots[0]
	s["gone"] = false; s["active"] = false
	field._activate_slot(s)
	var body: RigidBody3D = field._kicked[-1]["node"]
	field._on_hopper_body(body)
	await wait_seconds(0.1)
	assert_eq(field._walkway.count(), 1, "礦粒上咗走道")
	assert_true(s["gone"], "槽位標記用咗")

func test_save_roundtrip_keeps_garage_haulers_walkway_drills() -> void:
	var field = _load_field()
	field._garage = {"speed": 2, "cargo": 1, "price": 3}
	field._hauler_lvl[1] = 2
	field._drills[1] = true
	field._walkway_unlocked = true
	field._save_game()
	var saved: Dictionary = SaveManager.load_state()
	assert_eq(int(saved["field_garage"]["speed"]), 2)
	assert_eq(int(saved["field_haulers"][1]), 2)
	assert_true(bool(saved["field_drills"][1]))
	assert_true(bool(saved["field_walkway"]))

func test_hidden_vein_pads_are_physics_disabled_so_ore_is_not_swallowed() -> void:
	var field = _load_field()
	assert_eq(field._dep_panels[1].process_mode, Node.PROCESS_MODE_DISABLED, "未露出嘅墊要停物理")
	assert_eq(field._dep_panels[0].process_mode, Node.PROCESS_MODE_INHERIT)
	field.state.cash = 1e9
	for _p in field._dep_panels: _p.ore_fed = _p.ore_cost
	field._on_deposit_tap("deposit1", field.DEPOSITS[1][3])
	assert_eq(field._dep_panels[1].process_mode, Node.PROCESS_MODE_INHERIT, "露出後恢復")
	assert_eq(field._hire_pads[0].process_mode, Node.PROCESS_MODE_INHERIT)

func test_ai_route_from_right_side_goes_down_the_east_side() -> void:
	var field = _load_field()
	field._ai_mode = "heap"
	field._car.position = field._site_to_local(Vector2(4.4, 1.6), field.CAR_Z)
	for i in range(field.CARGO_CAP[0]):
		field._kicked.append({"slot": field._slots[i], "node": field._car, "t": 0.0, "carried": true, "local": Vector3.ZERO})
	field._ai_steer(0.1)
	assert_eq(field._ai_mode, "furnace")
	assert_gt(field._ai_target.x, 2.5, "喺右邊礦脈裝滿，第一個航點行東側，唔穿爐前礦脈")

# ── 用戶 2026-09-20：全部物品實體碰撞 + 升級直接變模型 ──

func _count_bodies(root: Node, cls: String) -> int:
	var n := 0
	for c in root.get_children():
		if c.is_class(cls):
			n += 1
		n += _count_bodies(c, cls)
	return n

func test_props_rubble_gates_rack_all_have_static_colliders() -> void:
	var field = _load_field()
	assert_eq(_count_bodies(field._site.get_node("Props"), "StaticBody3D"), 0, "用戶 2026-09-21：場內冇非分區障礙物")
	assert_gt(_count_bodies(field._vein_rubble[0], "StaticBody3D"), 0, "礦床石頭係實體")
	assert_eq(field._vein_rubble[0].process_mode, Node.PROCESS_MODE_INHERIT)
	assert_gt(_count_bodies(field._site.get_node("Gate_x2"), "StaticBody3D"), 1, "倍數門兩支柱都係實體")
	assert_gt(_count_bodies(field._ingot_root, "StaticBody3D"), 0)
	field.state.cash = 1e9
	for _p in field._dep_panels: _p.ore_fed = _p.ore_cost
	field._on_deposit_tap("deposit1", field.DEPOSITS[1][3])
	assert_eq(field._vein_rubble[0].process_mode, Node.PROCESS_MODE_DISABLED, "開咗礦脈，礦床石頭連碰撞一齊收")

func test_hauler_is_solid_and_changes_model_on_level_up() -> void:
	var field = _load_field()
	field.state.cash = 1e9
	for _p in field._dep_panels: _p.ore_fed = _p.ore_cost
	field._on_deposit_tap("deposit1", field.DEPOSITS[1][3])
	field._on_hire_tap("hire1", field._hauler_cost(1, 0))
	var h: Hauler = field._haulers[1]
	assert_true(h._body is AnimatableBody3D, "拖車仔車身係 AnimatableBody3D")
	var wheels_lv1: int = _count_bodies(h, "MeshInstance3D")
	h.set_level(3)
	await wait_frames(2)
	assert_gt(_count_bodies(h, "MeshInstance3D"), wheels_lv1, "Lv3 三軸：模型件數多過 Lv1")

func test_garage_levels_change_car_model() -> void:
	var field = _load_field()
	var parts0: int = field._blade_nodes.size()
	field.state.cash = 1e9
	field._on_garage_buy("speed"); field._on_garage_buy("speed"); field._on_garage_buy("speed")
	field._on_garage_buy("cargo")
	field._on_garage_buy("price")
	assert_gt(field._blade_nodes.size(), parts0, "車速／載量／賣價升級後車模型多咗零件")

func test_walkway_segments_are_solid() -> void:
	var field = _load_field()
	field.state.cash = 1e9
	field._walk_pad.ore_fed = field._walk_pad.ore_cost
	field._on_walkway_tap("walkway", field.WALKWAY_COST)
	assert_eq(_count_bodies(field._walkway, "StaticBody3D"), field.WALKWAY_PATH.size() - 1, "每段帶一個 StaticBody3D")

# ── 用戶 2026-09-21：疊高 20 層、盒仔礦碎、符合物理 ──

func test_heap_is_a_20_layer_lattice_cone_with_column_colliders() -> void:
	var field = _load_field()
	var top_layer := 0
	for s in field._dep_slots[0]:
		top_layer = maxi(top_layer, int(s["layer"]))
	assert_eq(top_layer, field.HEAP_LAYERS, "主堆中心柱有 20 層")
	var enabled := 0
	for col in field._dep_cols[0]:
		if not (col["cs"] as CollisionShape3D).disabled:
			enabled += 1
	assert_gt(enabled, 300, "每條有礦嘅柱都有承托碰撞")
	# 柱由底向上連續：冇「下面空、上面有」
	for col in field._dep_cols[0]:
		var seen_gap := false
		for s in col["slots"]:
			if s["gone"]:
				seen_gap = true
			elif seen_gap:
				fail_test("柱入面有浮空礦")
				return
	pass_test("冇浮空")

func test_activating_a_low_chunk_cascades_the_column_and_shrinks_the_collider() -> void:
	var field = _load_field()
	var col: Dictionary = field._dep_cols[0][field._dep_cols[0].size() / 2]
	var stacked := 0
	for s in col["slots"]:
		if not s["gone"]:
			stacked += 1
	if stacked < 3:
		pass_test("呢條柱太矮，跳過"); return
	var n: int = field._activate_slot(col["slots"][1])
	assert_eq(n, stacked - 1, "轉第 2 層，上面全部一齊轉做剛體")
	assert_almost_eq((col["shape"] as BoxShape3D).size.z, field.LAYER_H, 0.001, "碰撞柱縮到只剩底層")
	var body: RigidBody3D = field._kicked[-1]["node"]
	assert_true(body.get_child(1).shape is BoxShape3D, "礦碎係盒仔碰撞，唔會滾走")

func test_refill_only_reveals_supported_slots() -> void:
	var field = _load_field()
	for _i in range(200):
		var s: Dictionary = field._pick_hidden_slot(0)
		if s.is_empty():
			break
		assert_true(field._slot_supported(s), "補礦只落喺有承托嘅位")
		s["gone"] = false
	pass_test("ok")

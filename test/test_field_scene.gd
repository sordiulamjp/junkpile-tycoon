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

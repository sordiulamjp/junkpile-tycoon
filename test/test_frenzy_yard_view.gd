extends GutTest

## VR-06c：res://systems/frenzy_yard_view.gd 波池（MultiMesh 靜態堆 + 車鏟
## 前方一小圈轉真 RigidBody3D，離開範圍/夠鐘轉返靜態）+ 卡通推土機鏟斗
## （UPGRADE 墊換模變闊）單元測試。
##
## 用獨立 FrenzyYardView（唔經 main.tscn）：波池位置本身用 rng 生成，測試
## 唔斷言實際座標，淨斷言數量／分佈／轉態行為，控制得到、快、唔怕 flaky。
## main.tscn 有冇正確裝配波池另見 test_main_scene.gd 嘅煙霧測試。
##
## `car`（AnimatableBody3D，`sync_to_physics = true`）嘅 position 由物理
## 引擎（Jolt）揸實，headless 測試入面直接 `car.position = x` 之後即刻讀
## 返會拎到未郁過嘅舊值（要等真正物理 tick 先追落去）——`before_each()`
## 關咗 `sync_to_physics` 先至可以喺測試度即時擺位，唔影響落場（`_build_car()`
## 照舊起 `sync_to_physics = true`）。

var view: FrenzyYardView
var c: GameConstants
var gs: GameState
var fs: FrenzyState


func before_each() -> void:
	c = GameConstants.new()
	gs = GameState.new(c)
	fs = FrenzyState.new(c)
	view = FrenzyYardView.new(c, gs, fs)
	add_child_autofree(view)
	view.car.sync_to_physics = false


func _first_slot_of_tier(tier: String) -> Dictionary:
	for slot: Dictionary in view._pool_slots:
		if slot["tier"] == tier:
			return slot
	return {}


# ── 波池：靜態 MultiMesh 堆鋪滿地面 ──────────────────────────────

func test_pool_builds_expected_total_instance_count() -> void:
	assert_almost_eq(
		view._pool_slots.size(), c.ore_pool_total_count, 6,
		"六個礦物階四捨五入之後加埋應該貼近 ore_pool_total_count"
	)

func test_pool_covers_all_six_ore_tiers_with_own_multimesh() -> void:
	var seen := {}
	for slot: Dictionary in view._pool_slots:
		seen[slot["tier"]] = true
	for tier: String in c.ore_pool_tier_weights.keys():
		assert_true(seen.has(tier), "礦物階 %s 應該有波" % tier)
		assert_true(view._pool_mesh_by_tier.has(tier), "礦物階 %s 應該有自己嘅 MultiMeshInstance3D" % tier)

func test_pool_gold_balls_are_bigger_than_common_balls() -> void:
	var gold_slot: Dictionary = _first_slot_of_tier("gold")
	var stone_slot: Dictionary = _first_slot_of_tier("stone")
	assert_almost_eq(float(gold_slot["scale_mult"]), c.ore_pool_gold_scale_mult, 0.001)
	assert_almost_eq(float(stone_slot["scale_mult"]), 1.0, 0.001)
	assert_gt(float(gold_slot["scale_mult"]), float(stone_slot["scale_mult"]), "issue 要求：金波大粒過普通波")

func test_pool_emissive_flag_only_on_gold_diamond_crown() -> void:
	for slot: Dictionary in view._pool_slots:
		var expected: bool = slot["tier"] in ["gold", "diamond", "crown"]
		assert_eq(slot["emissive"], expected, "%s 嘅自發光旗標同 issue 要求唔啱" % slot["tier"])


# ── 車鏟前方一小圈轉 rigid，離開範圍/夠鐘轉返靜態 ──────────────────
#
# 波池密度好高（預設 3000 粒鋪成千粒喺車場成條 y 走廊），kick_radius
# 範圍入面通常唔止一粒波（呢個先係 issue 要求嘅「推堆」效果——車一過就
# 一嚿波散開，唔係一粒粒噉散）。下面斷言故意唔假設「淨轉咗一粒」，淨
# 斷言「起碼轉咗」／「全部都轉返靜態」，先至唔會因為波池密度而 flaky。
#
# 注意：呢度冇斷言 MultiMesh.get_instance_transform() 讀返嚟嘅值——headless
# CI 用嘅係 dummy RenderingServer，set_instance_transform() 寫落去嘅嘢喺
# headless 讀唔返（純 CI 環境限制，Windows editor／真機一定睇到；曾經用
# 一個獨立 scratch script 確認過 set/get 喺 headless 底下對唔上，同呢個
# script 嘅邏輯冇關），所以淨用 `slot["active"]`（純 GDScript 狀態，唔經
# RenderingServer）做隱形／顯示嘅斷言依據。

func test_slot_activates_to_real_rigidbody_when_car_is_near() -> void:
	var slot: Dictionary = _first_slot_of_tier("stone")
	view.car.position = slot["pos"]
	view._pool_kick_tick(c.ore_pool_kick_scan_interval_secs)

	assert_true(slot["active"], "車企喺波嗰位，隔咗一個掃描週期應該轉咗做 rigid")
	assert_gte(view._pool_kicked.size(), 1)

func test_kicked_ball_reverts_to_static_after_leaving_radius() -> void:
	var slot: Dictionary = _first_slot_of_tier("stone")
	view.car.position = slot["pos"]
	view._pool_kick_tick(c.ore_pool_kick_scan_interval_secs)
	assert_gte(view._pool_kicked.size(), 1)

	view.car.position = (slot["pos"] as Vector3) + Vector3(50.0, 0.0, 0.0) # 車走得遠遠，全部應該離開範圍
	view._update_pool_kicks(0.0)

	assert_false(slot["active"], "車走遠咗，波應該轉返靜態")
	assert_eq(view._pool_kicked.size(), 0, "車走遠咗，呢輪轉咗做 rigid 嘅波應該全部轉返靜態")

func test_kicked_ball_reverts_after_lifetime_expires_even_if_car_stays_near() -> void:
	var slot: Dictionary = _first_slot_of_tier("stone")
	view.car.position = slot["pos"]
	view._pool_kick_tick(c.ore_pool_kick_scan_interval_secs)
	assert_gte(view._pool_kicked.size(), 1)

	view._update_pool_kicks(c.ore_pool_kick_lifetime_secs + 0.01) # 車冇郁過，但夠鐘

	assert_false(slot["active"], "夠鐘（ore_pool_kick_lifetime_secs）應該強制轉返靜態，唔理車喺唔喺近")
	assert_eq(view._pool_kicked.size(), 0, "夠鐘之後應該全部強制轉返靜態")

func test_pool_kick_budget_shares_debris_rigidbody_cap() -> void:
	c.debris_rigidbody_cap = 2
	var stone_slots: Array = []
	for slot: Dictionary in view._pool_slots:
		if slot["tier"] == "stone":
			stone_slots.append(slot)
		if stone_slots.size() >= 5:
			break
	assert_gte(stone_slots.size(), 5, "測試前提：起碼要有 5 粒 stone 波先夠試 cap")

	# 逼 5 粒石波企埋 y=0（波池嘅 y 範圍上限係 car_park_max_y 減兩粒半徑，
	# 一定 < 0，所以 y=0 保證冇其他隨機波混入嚟，先可以斷言啱啱好轉咗 2 粒）。
	for slot: Dictionary in stone_slots:
		slot["pos"] = Vector3.ZERO
	view.car.position = Vector3.ZERO
	view._pool_kick_tick(c.ore_pool_kick_scan_interval_secs)

	assert_eq(view._pool_kicked.size(), 2, "debris_rigidbody_cap=2，就算範圍入面有 5 粒都應該淨轉 2 粒")

func test_pool_kick_budget_leaves_room_for_already_scoring_debris() -> void:
	c.debris_rigidbody_cap = 3
	view._debris_nodes = [Node3D.new(), Node3D.new()] # 假裝散幣管道已經用咗 2 個名額
	var slot: Dictionary = _first_slot_of_tier("stone") # weights.keys() 第一個係 "stone"，佢即係 _pool_slots[0]，一定係掃描第一粒
	view.car.position = slot["pos"]

	view._pool_kick_tick(c.ore_pool_kick_scan_interval_secs)

	assert_true(slot["active"], "cap 3 減散幣 2 仲有 1 個波池名額，掃描第一粒（就係佢自己）應該攞到")
	for n in view._debris_nodes:
		n.free()

func test_low_fps_tier_skips_kicking_pool_to_static() -> void:
	fs.debris_tier = c.frenzy_fake_physics_min_tier # is_fake_physics() 一定 true
	var slot: Dictionary = _first_slot_of_tier("stone")
	view.car.position = slot["pos"]

	view._pool_kick_tick(c.ore_pool_kick_scan_interval_secs)

	assert_false(slot["active"], "最低幀數階唔應該再轉 rigid，波池淨係保持靜態鋪滿")
	assert_eq(view._pool_kicked.size(), 0)


# ── 卡通推土機：鏟斗跟 UPGRADE 墊變闊/變色，車身／履帶／碰撞盒唔跟 ──────

func test_blade_widens_and_recolors_on_upgrade_without_scaling_body() -> void:
	fs.cooldown_remaining = 0.0
	fs.start(0.0)
	var body_scale_before: Vector3 = view._car_mesh.scale

	fs.try_upgrade_pad()
	view._apply_car_tier_visual()

	var tier: Dictionary = fs.current_tier()
	assert_eq(view._car_mesh.scale, body_scale_before, "issue：UPGRADE 淨換鏟斗，車身唔應該變")
	assert_almost_eq(view._blade_mesh.scale.x, float(tier["scale"]), 0.001, "鏟斗闊度應該跟 tier.scale")
	assert_almost_eq(view._blade_mesh.scale.y, 1.0, 0.001, "淨變闊，唔應該連鏟斗高度都變")
	assert_almost_eq(view._blade_mesh.scale.z, 1.0, 0.001, "淨變闊，唔應該連鏟斗深度都變")
	assert_eq(view._blade_mat.albedo_color, tier["color"])

func test_car_collision_shape_untouched_by_bulldozer_reskin() -> void:
	var col: CollisionShape3D = null
	for child in view.car.get_children():
		if child is CollisionShape3D:
			col = child
	assert_not_null(col, "車應該有 CollisionShape3D")
	var shape: BoxShape3D = col.shape
	assert_eq(
		shape.size, Vector3(0.5, 0.3, 0.3),
		"碰撞盒要維持原本大細唔改——木橋安全闊度／四道門／UPGRADE 墊嘅觸發全部靠呢個大細，換皮唔應該連帶郁物理"
	)

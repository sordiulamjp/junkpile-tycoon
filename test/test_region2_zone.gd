extends GutTest

## ALTA-229（VR-13）main.gd 整合測試——Region2Zone（regions/region2_outer_path/
## region2_zone.gd）掛喺 main.tscn 場地擴張框架下嘅解鎖／扣錢／存檔流程。
## 跟 test/test_mine_zone.gd 同一風格（成個 main.tscn 起，測真實 callback，
## 純數值嗰部分見 test_region2_state.gd）。

var main: Node
const EPS := 0.001

func before_each() -> void:
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

func after_each() -> void:
	if is_instance_valid(main):
		main.free()
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

func _load_main() -> Node:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)
	return main


# ── 掛喺 main.tscn，唔係獨立場景；鎖住之前唔顯示 ─────────────

func test_region2_zone_is_a_child_of_main_scene_not_a_standalone_scene() -> void:
	_load_main()
	assert_not_null(main._region2_zone)
	assert_true(main._region2_zone.is_inside_tree())
	assert_eq(main._region2_zone.get_parent(), main._placement_root)

func test_region2_zone_starts_hidden_for_fresh_game() -> void:
	_load_main()
	assert_false(main._region2_zone.visible, "未解鎖區域 2 之前，外圍險路唔應該顯示")

func test_unlocking_region2_reveals_the_zone() -> void:
	_load_main()
	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	assert_true(main._region2_zone.visible, "撳咗「200」解鎖板之後外圍險路應該顯示")


# ── tick()：鎖住 no-op，解鎖之後自動出貨週期入共用 cash ──────

func test_tick_is_noop_while_locked() -> void:
	_load_main()
	var cash_before: float = main.state.cash
	main._region2_zone.tick(main._region2_zone.state.c.cycle_interval_secs)
	assert_almost_eq(main.state.cash, cash_before, EPS, "未解鎖唔應該自動出貨賺錢")

func test_tick_credits_convoy_cash_into_shared_cash_once_unlocked() -> void:
	_load_main()
	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	var cash_before: float = main.state.cash

	main._region2_zone.tick(main._region2_zone.state.c.cycle_interval_secs)

	assert_gt(main.state.cash, cash_before, "行完一個出貨週期應該加共用 Cash")


# ── UPGRADE 小屋：順序買，扣共用 cash ─────────────────────

func test_shack_upgrade_deducts_shared_game_state_cash() -> void:
	_load_main()
	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	var zone: Region2Zone = main._region2_zone
	var cost := zone.state.c.shack_tier_cost[0]
	main.state.cash = cost

	zone._on_shack_tap("region2_shack0", cost)

	assert_eq(zone.state.shack_tier, 1)
	assert_almost_eq(main.state.cash, 0.0, EPS, "應該扣走共用 GameState.cash，唔係自己一份")

func test_shack_upgrade_cannot_skip_ahead() -> void:
	_load_main()
	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	var zone: Region2Zone = main._region2_zone
	main.state.cash = 1000000.0

	zone._on_shack_tap("region2_shack1", zone.state.c.shack_tier_cost[1])

	assert_eq(zone.state.shack_tier, 0, "未買 tier0，唔可以直接買 tier1")


# ── 存檔：殺 App 重開，區域 2 進度不變 ─────────────────────

func test_region2_zone_progress_round_trips_through_save_and_reload() -> void:
	_load_main()
	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	var zone: Region2Zone = main._region2_zone
	main.state.cash = zone.state.c.shack_tier_cost[0]
	zone._on_shack_tap("region2_shack0", zone.state.c.shack_tier_cost[0])
	main._save_game()
	main.free()

	_load_main()
	assert_true("region2" in main._unlocked_regions, "殺 App 重開，區域解鎖狀態應該不變")
	assert_true(main._region2_zone.visible, "重開之後外圍險路應該直接顯示已解鎖")
	assert_eq(main._region2_zone.state.shack_tier, 1, "殺 App 重開，UPGRADE 小屋等級應該不變")

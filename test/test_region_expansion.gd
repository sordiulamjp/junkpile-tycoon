extends GutTest

## VR-11（ALTA-227）：main.gd 場地擴張框架整合測試——區域解鎖板
## （UnlockPanel）撳落去嘅實際扣錢／持久化流程、鏡頭可拖嘅夾範圍。
## UnlockPanel 自己嘅顯示邏輯見 test_unlock_panel.gd（唔使成個 main.tscn
## 都起埋）。

var main: Node

func before_each() -> void:
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

func after_each() -> void:
	if is_instance_valid(main):
		main.free()
	RemoteConstants.clear_cache()
	SaveManager.delete_save()

const EPS := 0.001


# ── 解鎖板：扣錢／持久化 ─────────────────────────────────────────

func test_region2_panel_starts_locked_for_fresh_game() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_eq(main._unlocked_regions, ["region1"])
	assert_false(main._region2_panel._unlocked)

func test_try_unlock_region_succeeds_when_affordable() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)

	assert_true("region2" in main._unlocked_regions)
	assert_almost_eq(main.state.cash, 0.0, EPS, "解鎖板應該真正扣走 state.cash")
	assert_true(main._region2_panel._unlocked)

func test_try_unlock_region_fails_when_not_affordable() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.c.region2_unlock_price - 1.0
	main._try_unlock_region("region2", main.c.region2_unlock_price)

	assert_false("region2" in main._unlocked_regions)
	assert_almost_eq(main.state.cash, main.c.region2_unlock_price - 1.0, EPS, "唔夠錢就唔應該扣任何錢")
	assert_false(main._region2_panel._unlocked)

func test_try_unlock_region_is_idempotent_once_unlocked() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.c.region2_unlock_price * 2.0
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	var cash_after_first: float = main.state.cash

	main._try_unlock_region("region2", main.c.region2_unlock_price) # 再撳一次

	assert_almost_eq(main.state.cash, cash_after_first, EPS, "已經解鎖咗唔應該再扣多次錢")
	assert_eq(main._unlocked_regions.count("region2"), 1)

## 對應驗收「殺 App 重開進度不變」——區域解鎖狀態透過 main.gd 正常
## _save_game() 流程存落 disk，重開場景應該讀返。
func test_region_unlock_round_trips_through_main_flow() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.state.cash = main.c.region2_unlock_price
	main._try_unlock_region("region2", main.c.region2_unlock_price)
	main.free()

	main = scene.instantiate()
	add_child_autofree(main)

	assert_true("region2" in main._unlocked_regions, "殺 App 重開，區域解鎖狀態應該不變")
	assert_true(main._region2_panel._unlocked, "重開之後解鎖板應該直接顯示已解鎖，唔使再撳一次")


# ── 鏡頭可拖 ─────────────────────────────────────────────────────

func test_camera_pan_starts_at_zero_matching_base_position() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	assert_eq(main._camera_pan, 0.0)
	assert_eq(main._camera.position, main._camera_base_position)

func test_drag_up_increases_pan_and_moves_camera_along_local_up() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main._apply_camera_drag(-100.0) # 手指／滑鼠向上拖 100px（screen Y 向下遞增，向上拖係負值）

	assert_gt(main._camera_pan, 0.0, "向上拖應該增加 pan（望到多啲上面嘅區域）")
	assert_lte(main._camera_pan, main.CAMERA_MAX_PAN)

	var basis := Basis.from_euler(
		Vector3(deg_to_rad(main.CAMERA_PITCH_DEG), deg_to_rad(main.CAMERA_YAW_DEG), 0.0)
	)
	var expected_pos: Vector3 = main._camera_base_position + basis.y * main._camera_pan
	assert_almost_eq(main._camera.position.distance_to(expected_pos), 0.0, EPS)

func test_drag_down_does_not_go_below_zero() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main._apply_camera_drag(500.0) # 向下拖（screen_delta_y 正值）唔應該拖到負 pan
	assert_eq(main._camera_pan, 0.0)
	assert_eq(main._camera.position, main._camera_base_position)

func test_drag_up_clamps_at_max_pan() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main._apply_camera_drag(-100000.0) # 誇張大力向上拖
	assert_eq(main._camera_pan, main.CAMERA_MAX_PAN)

## Review 修正（round 2）：玩家拖咗上去睇緊區域 2 解鎖板（_camera_pan > 0，
## 車場已經跌出畫面）先撳狂熱掣——round 1 個 gate 令狂熱期間拖唔返落嚟，
## 所以狂熱一開場一定要自己將 _camera_pan 歸零，唔靠玩家手動拖。
func test_try_start_frenzy_resets_camera_pan() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main._apply_camera_drag(-100000.0) # 誇張大力拖上去，夾喺 CAMERA_MAX_PAN
	assert_gt(main._camera_pan, 0.0, "測試前提：鏡頭應該已經拖咗上去")

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()

	assert_eq(main._camera_pan, 0.0, "狂熱開場應該自動將鏡頭歸零，唔會車場跌出畫面")
	assert_eq(main._camera.position, main._camera_base_position)

## Review 修正（round 1）：狂熱入面跟指郁車嘅拖曳唔可以連鏡頭都拖埋
## （frenzy_yard_view.gd 自己嗰個 _unhandled_input() 冇 set_input_as_handled()）。
func test_unhandled_input_drag_is_ignored_during_frenzy() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	main.frenzy.cooldown_remaining = 0.0
	main._try_start_frenzy()
	assert_true(main.frenzy.active, "測試前提：狂熱應該啟動咗")

	var event := InputEventScreenDrag.new()
	event.relative = Vector2(0.0, -100.0)
	main._unhandled_input(event)

	assert_eq(main._camera_pan, 0.0, "狂熱期間拖曳唔應該郁鏡頭")

func test_unhandled_input_drag_works_when_not_in_frenzy() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var event := InputEventScreenDrag.new()
	event.relative = Vector2(0.0, -100.0)
	main._unhandled_input(event)

	assert_gt(main._camera_pan, 0.0, "冇狂熱嗰陣拖曳應該照舊郁鏡頭")

## Review 修正（round 1）：Godot 預設 emulate_mouse_from_touch=true，觸控
## 拖曳會同時派一個真 InputEventScreenDrag 同一個模擬嘅
## InputEventMouseMotion（device=DEVICE_ID_EMULATION）——後者唔應該再
## apply 多一次，唔係就手機靈敏度變兩倍。
func test_unhandled_input_ignores_touch_emulated_mouse_motion() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var event := InputEventMouseMotion.new()
	event.relative = Vector2(0.0, -100.0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.device = InputEvent.DEVICE_ID_EMULATION
	main._unhandled_input(event)

	assert_eq(main._camera_pan, 0.0, "觸控模擬出嚟嘅 mouse motion 唔應該再郁多一次鏡頭")

func test_unhandled_input_real_mouse_motion_still_works() -> void:
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	add_child_autofree(main)

	var event := InputEventMouseMotion.new()
	event.relative = Vector2(0.0, -100.0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	main._unhandled_input(event)

	assert_gt(main._camera_pan, 0.0, "Windows host 編輯器試玩用真滑鼠，唔應該俾 device 判斷擋咗")

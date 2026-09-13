extends GutTest

## ALTA-228（VR-12）res://regions/region1_mine/region1_mine.tscn 煙霧測試——
## 場景可以載入、行幾幀冇 error，核心 UI 節點齊全，升級掣接得返
## MineState（跟 test/test_main_scene.gd 同一風格：headless 冇真實觸控，
## 呢度淨係測掣嘅 callback／狀態同步，唔測 tap 手感，留返俾裝置實測）。

var scene_root: Node

func after_each() -> void:
	if is_instance_valid(scene_root):
		scene_root.free()

func _load() -> Node:
	var scene: PackedScene = load("res://regions/region1_mine/region1_mine.tscn")
	scene_root = scene.instantiate()
	add_child_autofree(scene_root)
	return scene_root

func test_scene_loads_and_ticks_without_error() -> void:
	var main := _load()
	assert_not_null(main.state)
	for i in range(10):
		main._process(0.1)
	assert_true(main.state.cash >= main.state.c.starting_cash, "開場資金放置收入之下唔會倒扣")

func test_three_layer_rows_and_locked_layer4_are_built() -> void:
	var main := _load()
	assert_eq(main._layer_rate_labels.size(), 3)
	assert_eq(main._layer_upgrade_buttons.size(), 3)
	assert_not_null(main._layer4_price_label)
	assert_string_contains(main._layer4_price_label.text, "解鎖價")
	assert_string_contains(main._layer4_price_label.text, "未開放")

func test_cash_label_reflects_state_cash() -> void:
	var main := _load()
	main.state.cash = 1234.0
	main._refresh_ui()
	assert_string_contains(main._cash_label.text, "1.23K")

func test_layer_upgrade_button_press_upgrades_state() -> void:
	var main := _load()
	main.state.cash = 1000000.0
	main._refresh_ui()
	assert_false(main._layer_upgrade_buttons[0].disabled, "夠錢就應該撳得，開場資金一早應該夠")
	main._on_upgrade_layer_pressed(0)
	assert_eq(main.state.layer_level[0], 1)

func test_elevator_and_warehouse_upgrade_buttons_call_state() -> void:
	var main := _load()
	main.state.cash = 1000000.0
	main._on_upgrade_elevator_pressed()
	main._on_upgrade_warehouse_pressed()
	assert_eq(main.state.elevator_level, 2)
	assert_eq(main.state.warehouse_level, 2)

func test_bottleneck_banner_has_text_after_ready() -> void:
	var main := _load()
	assert_gt(main._bottleneck_label.text.length(), 0)

## issue：「每層／升降機／倉庫各有『經理』欄位（第二階段先接卡牌，先留
## UI 位）」——揾齊 5 粒「經理」掣（3 層＋升降機＋倉庫），確認有 UI 位
## 但未功能化（disabled）。
func test_manager_slots_are_reserved_but_disabled() -> void:
	var main := _load()
	var manager_buttons: Array[Button] = []
	_collect_manager_buttons(main, manager_buttons)
	assert_eq(manager_buttons.size(), 5, "3 礦層 + 升降機 + 倉庫＝5 個經理欄位")
	for btn in manager_buttons:
		assert_true(btn.disabled, "經理欄位呢期未功能化")

func _collect_manager_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button and node.text == "經理":
		out.append(node)
	for child in node.get_children():
		_collect_manager_buttons(child, out)

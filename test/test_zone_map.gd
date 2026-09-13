extends GutTest

## VR-11：scenes/zone_map.tscn 煙霧測試——場景可以載入、四張區域卡都
## 起齊；未起嘅區域（scene_path 空，VR-12～14 未做）顯示「開發中」並且
## 撳唔到；已經有場景嘅區域 4（沿用現有 main.tscn）撳得落去；Cash 讀數
## 跟返 Wallet／存檔。

var map: Control

func before_each() -> void:
	SaveManager.delete_save()
	Wallet.reset()

func after_each() -> void:
	if is_instance_valid(map):
		map.free()
	SaveManager.delete_save()
	Wallet.reset()


func test_scene_loads_with_four_zone_cards() -> void:
	var scene: PackedScene = load("res://scenes/zone_map.tscn")
	map = scene.instantiate()
	add_child_autofree(map)
	assert_eq(map._zone_buttons.size(), 4)

func test_not_yet_built_zones_are_disabled() -> void:
	var scene: PackedScene = load("res://scenes/zone_map.tscn")
	map = scene.instantiate()
	add_child_autofree(map)
	for i in range(3): # 區域 1～3 未起（VR-12～14）
		assert_true(map._zone_buttons[i].disabled, "未起嘅區域唔應該撳得入")

func test_zone4_reuses_existing_main_scene_and_is_enterable() -> void:
	var scene: PackedScene = load("res://scenes/zone_map.tscn")
	map = scene.instantiate()
	add_child_autofree(map)
	assert_false(map._zone_buttons[3].disabled, "區域 4 沿用現有 main.tscn，應該即刻撳得入")

func test_cash_label_reflects_saved_wallet() -> void:
	var seed_state := SaveManager.default_state()
	seed_state["cash"] = 2000.0
	SaveManager.save_state(seed_state)

	var scene: PackedScene = load("res://scenes/zone_map.tscn")
	map = scene.instantiate()
	add_child_autofree(map)

	assert_string_contains(map._cash_label.text, "2.0K")

extends GutTest

## VR-11：res://systems/unlock_panel.gd 單元測試——純顯示／tap 邏輯，
## 唔使成個 main.tscn 都起埋（main.gd 點樣用呢個 class 見
## test_region_expansion.gd）。覆蓋：tap 撳落去 call 返 callback（帶
## region_id／cost）、非左鍵／已解鎖之後唔再接受撳、
## refresh_afford_state() 跟返夠唔夠錢轉色。

var panel: UnlockPanel
var _tap_calls: Array = []

func before_each() -> void:
	_tap_calls = []
	panel = UnlockPanel.new()
	add_child_autofree(panel)
	panel.setup("region2", 50000.0, "區域 2　紫岩礦場", _on_tap)

func _on_tap(region_id: String, cost: float) -> void:
	_tap_calls.append([region_id, cost])

func _fake_left_click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	panel._on_input_event(null, event, Vector3.ZERO, Vector3.ZERO, 0)


func test_setup_shows_display_name_and_cost() -> void:
	# 2026-09-14 用戶：墊改用圖示，文字淨返價錢
	assert_string_contains(panel._label.text, "50K")
	assert_string_contains(panel._label.text, "50K")

func test_tap_invokes_callback_with_region_id_and_cost() -> void:
	_fake_left_click()
	assert_eq(_tap_calls.size(), 1)
	assert_eq(_tap_calls[0][0], "region2")
	assert_almost_eq(_tap_calls[0][1], 50000.0, 0.001)

func test_non_left_click_is_ignored() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	panel._on_input_event(null, event, Vector3.ZERO, Vector3.ZERO, 0)
	assert_eq(_tap_calls.size(), 0)

func test_button_release_is_ignored() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	panel._on_input_event(null, event, Vector3.ZERO, Vector3.ZERO, 0)
	assert_eq(_tap_calls.size(), 0)

func test_mark_unlocked_shows_unlocked_label_and_stops_accepting_taps() -> void:
	panel.mark_unlocked()
	assert_eq(panel._label.text, "✓", "已解鎖淨顯示 ✓（圖示版）")

	_fake_left_click()
	assert_eq(_tap_calls.size(), 0, "已解鎖之後撳落去唔應該再 call callback")

func test_refresh_afford_state_dims_pad_when_not_affordable() -> void:
	panel.refresh_afford_state(0.0)
	var mat: StandardMaterial3D = panel._pad.material_override
	var expected: Color = (VisualFactory.PALETTE["pad_purple"] as Color).darkened(0.45)
	assert_eq(mat.albedo_color, expected)

func test_refresh_afford_state_uses_base_color_when_affordable() -> void:
	panel.refresh_afford_state(999999.0)
	var mat: StandardMaterial3D = panel._pad.material_override
	assert_eq(mat.albedo_color, VisualFactory.PALETTE["pad_purple"])

func test_refresh_afford_state_is_noop_once_unlocked() -> void:
	panel.mark_unlocked()
	panel.refresh_afford_state(0.0) # 已解鎖，就算冇錢都唔應該打返做「未解鎖」嘅顯示
	assert_eq(panel._label.text, "✓", "已解鎖淨顯示 ✓（圖示版）")

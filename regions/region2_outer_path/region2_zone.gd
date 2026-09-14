extends Node3D
class_name Region2Zone

## ALTA-229（VR-13）區域 2「外圍險路」：一條環繞區域 1 上方嘅路，由
## main.gd 現有嘅「200」紫色解鎖板（`_region2_panel`，VR-11 已起）解鎖
## 之後先顯示／運作。跟 regions/region1_mine/mine_zone.gd 同一框架
## （「同一場地，由下向上擴張」，唔係獨立場景）：main.gd 負責擺位、
## `add_child(_placement_root)`、每幀 call `tick(delta)`、存檔讀寫 call
## `to_save_dict()` / `setup()` 嘅 `saved` 參數。
##
## 佈局（PLAN v3，parent ALTA-147）：左邊車道向上串聯 ×2→×3→×4 發光
## 透明板（倍數相乘）+ 刺滾筒 + 灰磚牆（×3 後撞爛先過）→ 頂部轉右一條
## 金河（外側岩浆）+ 中段 100 lb 木橋（超重斷橋）→ ×5 板 → 礦站（賣出
## 倍數後嘅礦，比熔爐賺多）；沿路 UPGRADE 小屋 200／500。冇獨立跟指車
## （唔似狂熱車場要玩家操控）——一架自動出貨車沿住 Path3D 循環行完全程
## （Region2State.tick()／run_convoy_cycle() 決定實際 cash_gain／斷橋），
## 純視覺跟返個 progress_ratio 走，冇判分意義。
##
## 色調（issue）：門道段紫岩、金河段紅啡岩 + 岩浆，見 Region2Constants.PALETTE。

const PALETTE := Region2Constants.PALETTE

## -- 左車道向上（局部 y 遞增）幾何 --
const GATE_SPACING := 0.75
const WALL_LOCAL_Y := GATE_SPACING * 2.0 + 0.32       # ×3（index1）後、×4（index2）前
const GATE4_LOCAL_Y := GATE_SPACING * 3.0 + 0.55
const TURN_LOCAL_Y := GATE4_LOCAL_Y + 0.55            # 轉右總深度＝金河起點

## -- 頂部轉右：金河 + 岩浆 + 木橋（局部 x 遞增） --
const RIVER_LEN := 2.4
const BRIDGE_LOCAL_X := RIVER_LEN * 0.55
const GATE5_LOCAL_X := RIVER_LEN + 0.5
const STATION_LOCAL_X := GATE5_LOCAL_X + 0.55

var state: Region2State
var _game_state: GameState
var _unlocked: bool = false
var _anim_t: float = 0.0

var _path: Path3D
var _path_follow: PathFollow3D
var _wall_intact: Node3D
var _wall_rubble: Node3D
var _wall_broken_visual: bool = false

var _shack_panels: Array[UnlockPanel] = []


## saved：main.gd 讀檔攞到嘅 region2_zone 子 dict（見 data/save_manager.gd
## v3→v4 遷移），冇存檔就 {}。unlocked：呢一刻 "region2" 使唔使喺
## main._unlocked_regions 入面——鎖住就成個 zone 唔顯示（`visible=false`，
## `tick()` 直接 no-op），撳咗 main._region2_panel 之後由 main.gd call
## `set_unlocked(true)`。
func setup(p_game_state: GameState, saved: Dictionary = {}, unlocked: bool = false) -> void:
	_game_state = p_game_state
	state = Region2State.new()
	_load_progress(saved)
	_unlocked = unlocked
	visible = _unlocked

	_build_left_lane()
	_build_river_and_bridge()
	_build_peak_and_station()
	_build_shacks()
	_build_convoy_path()

func _load_progress(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	state.shack_tier = int(saved.get("shack_tier", 0))

func to_save_dict() -> Dictionary:
	return {"shack_tier": state.shack_tier}

## main.gd `_try_unlock_region()` 撳落「200」解鎖板成功之後 call——同
## mine_zone 唔同，區域 2 唔係恆常解鎖，鎖住嗰陣呢個 zone 全部隱藏，唔
## 收集、唔畫、唔 tick，冇額外效能成本。
func set_unlocked(v: bool) -> void:
	_unlocked = v
	visible = v


# ══════════════════════ 每幀模擬 ══════════════════════

func tick(delta: float) -> void:
	if not _unlocked:
		return
	_anim_t += delta
	if _path_follow != null and state.c.cycle_interval_secs > 0.0:
		_path_follow.progress_ratio = fmod(_anim_t / state.c.cycle_interval_secs, 1.0)

	var result := state.tick(delta)
	if not bool(result["cycle_completed"]):
		return
	var cash_gain: float = result["cash_gain"]
	if cash_gain > 0.0:
		_game_state.cash += cash_gain
		if not _wall_broken_visual:
			_set_wall_broken(true) # 第一車行到就撞爛磚牆，之後恆常企喺「已撞爛」
		SfxPlayer.play("gate_pass")
		EventLog.log_event("region2_convoy_sold", {"cash_gain": cash_gain})
	else:
		SfxPlayer.play("lava_fall") # 超重斷橋：呢車冇 Cash
		EventLog.log_event("region2_convoy_bridge_broke", {})

## main.gd `_refresh_hud()` 每幀 call（同 `_mine_zone.refresh_afford_state()`
## 一致做法）——UPGRADE 小屋「夠唔夠錢」暗／亮色跟返即時 Cash。
func refresh_afford_state() -> void:
	for p in _shack_panels:
		p.refresh_afford_state(_game_state.cash)


# ══════════════════════ 左車道：×2→×3→×4 發光板 + 滾筒 + 磚牆 ══════════════════════

func _build_left_lane() -> void:
	var lane := Node3D.new()
	lane.name = "LeftLane"
	add_child(lane)

	_build_gate(lane, Vector3(0.0, GATE_SPACING * 1.0, 0.16), "×2")
	_build_roller(lane, Vector3(0.0, GATE_SPACING * 1.5, 0.1))
	_build_gate(lane, Vector3(0.0, GATE_SPACING * 2.0, 0.16), "×3")
	_build_wall(lane, Vector3(0.0, WALL_LOCAL_Y, 0.0))
	_build_roller(lane, Vector3(0.0, GATE_SPACING * 2.6, 0.1))
	_build_gate(lane, Vector3(0.0, GATE4_LOCAL_Y, 0.16), "×4")

## 發光透明板（issue：「串聯×2→×3→×4 發光透明板（IG 造型，倍數相乘）」）——
## 純視覺標示（實際相乘喺 Region2State.current_multiplier()），純色＋
## 自發光＋半透明代替真貼圖。
func _build_gate(parent: Node3D, pos: Vector3, label_text: String) -> void:
	var gate := VisualFactory.make_metal_box(Vector3(1.0, 0.06, 0.5), Color(PALETTE["gate_glow"]), Color(PALETTE["gate_glow"]), 1.4)
	var mat: StandardMaterial3D = gate.material_override
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var albedo: Color = mat.albedo_color
	albedo.a = 0.55
	mat.albedo_color = albedo
	gate.position = pos
	parent.add_child(gate)

	var label := Label3D.new()
	label.text = label_text
	label.font_size = 72
	label.pixel_size = 0.0032
	label.outline_size = 12
	label.modulate = Color.WHITE
	label.position = pos + Vector3(0.0, 0.0, 0.32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

## 刺滾筒——同 main.gd 帶滾軸／FrenzyYardView 一樣「持續自轉先有流動視覺」
## 手法（`_process()` 逐幀 `rotate_x()`），純造型。
func _build_roller(parent: Node3D, pos: Vector3) -> void:
	var roller := VisualFactory.make_low_poly_cylinder(0.12, 0.9, Color("#8A8F98"), 8, 0.5)
	roller.name = "SpikeRoller"
	roller.rotation_degrees.z = 90.0
	roller.position = pos
	parent.add_child(roller)

## 灰磚牆——企喺 ×3 後／×4 前，issue：「×3 後撞爛先過」。開場顯示完整
## 磚牆（`_wall_intact`），第一架自動出貨車行完成程（`tick()` 見
## cash_gain > 0）先切去碎石堆（`_wall_rubble`），之後恆常企喺「已撞爛」，
## 唔會再砌返（同现實「撞爛咗嘅牆唔會自己修復」一致）。
func _build_wall(parent: Node3D, pos: Vector3) -> void:
	_wall_intact = Node3D.new()
	_wall_intact.name = "WallIntact"
	_wall_intact.position = pos
	parent.add_child(_wall_intact)
	for row in range(2):
		for col in range(3):
			var brick := VisualFactory.make_flat_box(Vector3(0.32, 0.14, 0.16), Color(PALETTE["brick_wall"]))
			brick.position = Vector3(-0.32 + float(col) * 0.32, 0.0, 0.1 + float(row) * 0.17)
			_wall_intact.add_child(brick)

	_wall_rubble = Node3D.new()
	_wall_rubble.name = "WallRubble"
	_wall_rubble.position = pos
	_wall_rubble.visible = false
	parent.add_child(_wall_rubble)
	for i in range(4):
		var chunk := VisualFactory.make_ore_chunk(0.14, Color(PALETTE["brick_rubble"]))
		chunk.position = Vector3(-0.3 + float(i) * 0.2, 0.0, 0.06)
		chunk.rotation.y = float(i) * 0.6
		_wall_rubble.add_child(chunk)

func _set_wall_broken(v: bool) -> void:
	_wall_broken_visual = v
	if _wall_intact != null:
		_wall_intact.visible = not v
	if _wall_rubble != null:
		_wall_rubble.visible = v


# ══════════════════════ 頂部轉右：金河 + 岩浆 + 木橋 ══════════════════════

func _build_river_and_bridge() -> void:
	var river := Node3D.new()
	river.name = "GoldRiver"
	river.position = Vector3(0.0, TURN_LOCAL_Y, 0.0)
	add_child(river)

	var bed := VisualFactory.make_flat_box(Vector3(RIVER_LEN, 0.7, 0.05), Color(PALETTE["river_bed"]))
	bed.position = Vector3(RIVER_LEN * 0.5, 0.0, 0.0)
	river.add_child(bed)

	var gold := VisualFactory.make_metal_box(Vector3(RIVER_LEN, 0.42, 0.03), Color(PALETTE["river_gold"]), Color(PALETTE["river_gold"]), 0.4)
	gold.position = Vector3(RIVER_LEN * 0.5, -0.05, 0.03)
	river.add_child(gold)

	# 外側岩浆（issue：「外側岩浆」——貼住金河遠緣一條，車唔行嗰邊）。
	var lava := VisualFactory.make_metal_box(Vector3(RIVER_LEN, 0.22, 0.04), Color(PALETTE["lava"]), Color(PALETTE["lava"]), 1.6)
	lava.position = Vector3(RIVER_LEN * 0.5, 0.42, 0.03)
	river.add_child(lava)

	# 100 lb 木橋——issue：「中段」，五條橋板橫跨金河闊度。
	var bridge := Node3D.new()
	bridge.name = "WoodenBridge"
	bridge.position = Vector3(BRIDGE_LOCAL_X, 0.0, 0.04)
	river.add_child(bridge)
	for i in range(5):
		var plank := VisualFactory.make_flat_box(Vector3(0.16, 0.5, 0.03), Color(PALETTE["bridge_wood"]))
		plank.position = Vector3(-0.32 + float(i) * 0.16, 0.0, 0.0)
		bridge.add_child(plank)


# ══════════════════════ 路尾：×5 板 → 礦站 ══════════════════════

func _build_peak_and_station() -> void:
	var peak_pos := Vector3(GATE5_LOCAL_X, TURN_LOCAL_Y, 0.16)
	_build_gate(self, peak_pos, "×5")

	var station := Node3D.new()
	station.name = "MineStation"
	station.position = Vector3(STATION_LOCAL_X, TURN_LOCAL_Y, 0.0)
	add_child(station)

	var body := VisualFactory.make_flat_box(Vector3(0.75, 0.6, 0.5), Color(PALETTE["station"]))
	body.position = Vector3(0.0, 0.0, 0.25)
	station.add_child(body)
	var roof := VisualFactory.make_flat_box(Vector3(0.85, 0.7, 0.06), Color(PALETTE["station_roof"]))
	roof.position = Vector3(0.0, 0.0, 0.53)
	station.add_child(roof)
	var lamp := VisualFactory.make_lamp(0.05, Color("#FFD27A"))
	lamp.position = Vector3(0.0, -0.32, 0.4)
	station.add_child(lamp)


# ══════════════════════ UPGRADE 小屋（200／500） ══════════════════════

func _build_shacks() -> void:
	var positions := [Vector3(-0.75, GATE_SPACING * 1.6, 0.12), Vector3(0.0, TURN_LOCAL_Y - 0.5, 0.12)]
	for i in range(state.c.shack_tier_cost.size()):
		var p := UnlockPanel.new()
		p.name = "Shack%d" % i
		p.position = positions[i] if i < positions.size() else positions[positions.size() - 1] + Vector3(float(i), 0.0, 0.0)
		add_child(p)
		var region_id := "region2_shack%d" % i
		p.setup(region_id, state.c.shack_tier_cost[i], "UPGRADE 小屋", _on_shack_tap, "furnace")
		if i < state.shack_tier:
			p.mark_unlocked()
		_shack_panels.append(p)

func _on_shack_tap(region_id: String, cost: float) -> void:
	var idx := int(region_id.trim_prefix("region2_shack"))
	if idx != state.shack_tier: # 一定要順序買，唔可以跳級（同 region1 推堆墊一致）
		return
	if _game_state.cash < cost:
		return
	_game_state.cash -= cost
	state.apply_shack_upgrade()
	SfxPlayer.play("upgrade")
	EventLog.log_event("region2_shack_upgrade", {"tier": state.shack_tier, "cost": cost})
	if idx < _shack_panels.size():
		_shack_panels[idx].mark_unlocked()


# ══════════════════════ 自動出貨車：Path3D 循環（純視覺） ══════════════════════

## 冇跟指輸入——同 region1 礦車一樣自動運行，純視覺跟 Region2State
## 嘅出貨週期走，冇判分意義（真正 cash_gain／斷橋喺 `tick()` 用
## `state.tick()` 決定）。
func _build_convoy_path() -> void:
	_path = Path3D.new()
	_path.name = "ConvoyPath"
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.14))
	curve.add_point(Vector3(0.0, GATE_SPACING * 1.0, 0.14))
	curve.add_point(Vector3(0.0, WALL_LOCAL_Y, 0.14))
	curve.add_point(Vector3(0.0, GATE4_LOCAL_Y, 0.14))
	curve.add_point(Vector3(0.0, TURN_LOCAL_Y, 0.14))
	curve.add_point(Vector3(BRIDGE_LOCAL_X, TURN_LOCAL_Y, 0.14))
	curve.add_point(Vector3(GATE5_LOCAL_X, TURN_LOCAL_Y, 0.14))
	curve.add_point(Vector3(STATION_LOCAL_X, TURN_LOCAL_Y, 0.14))
	_path.curve = curve
	add_child(_path)

	_path_follow = PathFollow3D.new()
	_path_follow.loop = true
	_path.add_child(_path_follow)

	var cart := VisualFactory.make_metal_box(Vector3(0.24, 0.18, 0.16), Color("#F2B830"))
	cart.name = "Cart"
	_path_follow.add_child(cart)

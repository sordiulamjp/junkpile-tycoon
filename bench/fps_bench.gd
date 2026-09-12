extends Node3D

## VR-04：幀數實測工具（唔隨貨出街）——S8+ 上碎片剛體嘅平均 fps，用嚟定
## GameConstants.debris_rigidbody_cap／frenzy_debris_degrade_steps。跟
## `ads/ad_test.tscn` 同一個做法：唔搶 `run/main_scene`，出 APK 前臨時將
## project.godot 嘅 run/main_scene 改去 res://bench/fps_bench.tscn，裝機
## 跑完之後改返。
##
## VR-06c：加咗一個常駐嘅 MultiMesh 波池底（MULTIMESH_BALL_COUNT 粒靜態
## 波，同真實波池一樣一個 draw call 畫晒），同埋 150 呢個 issue 明文要求
## 嘅組合基準點（「MultiMesh 幾千粒 + 150 剛體要 ≥ 40fps」）——依家每個
## phase 嘅剛體數都係喺呢個波池底之上疊加。
##
## 各 phase 逐級加碼片數（唔清舊嘅，直接疊加到下一個目標數），每個 phase
## 跳過首 1 秒（啱啱生完嗰下正常會跌幀，唔計落平均），之後 5 秒取樣。
## 結果 print()（adb logcat 睇到）+ 寫落 user://fps_bench_report.txt
## （adb pull 攞）+ 畫面 Label 顯示到跑完唔會自動熄，方便截圖存證。

const PHASES: Array[int] = [100, 150, 200, 300]
const WARMUP_SECS := 1.0
const SAMPLE_SECS := 5.0
const DEBRIS_SIZE := Vector3(0.14, 0.14, 0.14)
const MULTIMESH_BALL_COUNT := 3000
const MULTIMESH_BALL_RADIUS := 0.05

var _phase_idx := 0
var _phase_elapsed := 0.0
var _fps_samples: Array[float] = []
var _results: Array[Dictionary] = []
var _label: Label
var _spawned_root: Node3D
var _done := false


func _ready() -> void:
	_build_scene()
	_build_hud()
	_start_phase(0)


func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat
	return mesh_instance

func _add_wall(pos: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	wall.position = pos
	add_child(wall)

func _build_scene() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.5, 5.0)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
	add_child(light)

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(4.0, 0.2, 4.0)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.add_child(_make_box(Vector3(4.0, 0.2, 4.0), Color(0.3, 0.3, 0.32)))
	floor_body.position = Vector3(0.0, -0.1, 0.0)
	add_child(floor_body)

	# 四面矮牆，等碎片剛體堆埋一齊唔會跌出鏡頭——同狂熱車場側牆
	# 同一個目的（VR-04：跟指車推嘅剛體堆要有嘢圍住）。
	_add_wall(Vector3(-2.0, 0.5, 0.0), Vector3(0.1, 1.0, 4.0))
	_add_wall(Vector3(2.0, 0.5, 0.0), Vector3(0.1, 1.0, 4.0))
	_add_wall(Vector3(0.0, 0.5, -2.0), Vector3(4.0, 1.0, 0.1))
	_add_wall(Vector3(0.0, 0.5, 2.0), Vector3(4.0, 1.0, 0.1))

	_spawned_root = Node3D.new()
	add_child(_spawned_root)

	_build_ore_pool_floor()

## VR-06c：波池底——同 systems/visual_factory.gd::make_ore_pool_multimesh()
## 一樣做法（一個 MultiMesh 共用一個 SphereMesh，GPU instancing 一個 draw
## call），呢度自砌一份唔拉 VisualFactory／GameConstants 依賴，維持呢個
## bench scene 一直以嚟嘅自包含風格（見檔頭註解）。
func _build_ore_pool_floor() -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = MULTIMESH_BALL_RADIUS
	sphere.height = MULTIMESH_BALL_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mm.mesh = sphere
	mm.instance_count = MULTIMESH_BALL_COUNT
	for i in range(MULTIMESH_BALL_COUNT):
		var pos := Vector3(randf_range(-1.8, 1.8), randf_range(0.02, 0.3), randf_range(-1.8, 1.8))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.42, 0.2)
	mmi.material_override = mat
	add_child(mmi)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 28)
	_label.text = "FPS BENCH starting..."
	canvas.add_child(_label)


func _spawn_one() -> void:
	var body := RigidBody3D.new()
	body.mass = 0.2
	body.add_child(_make_box(DEBRIS_SIZE, Color(0.85, 0.7, 0.2)))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = DEBRIS_SIZE
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(randf_range(-1.8, 1.8), randf_range(1.0, 4.0), randf_range(-1.8, 1.8))
	_spawned_root.add_child(body)

func _start_phase(idx: int) -> void:
	_phase_idx = idx
	_phase_elapsed = 0.0
	_fps_samples.clear()
	var target: int = PHASES[idx]
	var current: int = _spawned_root.get_child_count()
	for i in range(target - current):
		_spawn_one()

func _process(delta: float) -> void:
	if _done:
		return
	_phase_elapsed += delta
	var fps := Engine.get_frames_per_second()
	if _phase_elapsed > WARMUP_SECS:
		_fps_samples.append(fps)
	_label.text = "Phase %d/%d: %d rigidbodies + %d multimesh\nt=%.1fs  fps=%.0f" \
		% [_phase_idx + 1, PHASES.size(), PHASES[_phase_idx], MULTIMESH_BALL_COUNT, _phase_elapsed, fps]
	if _phase_elapsed >= WARMUP_SECS + SAMPLE_SECS:
		_finish_phase()

func _finish_phase() -> void:
	var avg := 0.0
	var min_fps := 0.0
	if not _fps_samples.is_empty():
		for s in _fps_samples:
			avg += s
		avg /= _fps_samples.size()
		min_fps = _fps_samples.min()
	_results.append({"count": PHASES[_phase_idx], "avg_fps": avg, "min_fps": min_fps})
	print("FPS_BENCH_RESULT count=%d avg_fps=%.1f min_fps=%.1f" % [PHASES[_phase_idx], avg, min_fps])
	if _phase_idx + 1 < PHASES.size():
		_start_phase(_phase_idx + 1)
	else:
		_finish_all()

func _finish_all() -> void:
	_done = true
	var lines: Array[String] = ["FPS BENCH DONE"]
	for r: Dictionary in _results:
		lines.append("n=%d avg=%.1f min=%.1f" % [r["count"], r["avg_fps"], r["min_fps"]])
	var report := "\n".join(lines)
	print("FPS_BENCH_REPORT\n" + report)
	_label.text = report
	var f := FileAccess.open("user://fps_bench_report.txt", FileAccess.WRITE)
	if f:
		f.store_string(report)
		f.close()

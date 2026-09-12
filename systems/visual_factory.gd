class_name VisualFactory
extends RefCounted

## VR-06：換皮視覺工廠。
##
## 集中晒「靠 code 現砌」嘅美術物件，取代 main.gd／frenzy_yard_view.gd
## 原本各自嘅 `_make_box(size, color)`。淨係換視覺（mesh／材質／模型），
## 完全唔改碰撞形狀、擺位座標、數值——嗰啲全部留喺原本呼叫嗰度，呢個
## script 冇任何判分邏輯，方便同 ALTA-150／151 嘅灰模改動並行（並行紀律
## 見 issue ALTA-153）。
##
## 風格：flat-shaded low-poly——低面數 mesh（八邊圓柱、Prism 楔形代替
## 圓滑幾何）+ per-vertex 光照材質，貼近 docx 概念圖嘅平面卡通感，
## 唔靠貼圖。色板見 PALETTE，礦工用 Kenney CC0 機械人 glTF（見
## CREDITS.md），其餘全部係 Godot 原生 Mesh。

const PALETTE := {
	"cave": Color(0.42, 0.36, 0.3),
	"cave_light": Color(0.5, 0.44, 0.36),
	"belt": Color(0.35, 0.35, 0.38),
	"furnace_body": Color(0.16, 0.34, 0.58),
	"furnace_glow": Color(1.0, 0.55, 0.15),
	"warehouse_body": Color(0.2, 0.4, 0.65),
	"warehouse_roof": Color(0.14, 0.28, 0.46),
	"lava": Color(0.85, 0.25, 0.05),
	"bridge_wood": Color(0.45, 0.3, 0.15),
	"gear_metal": Color(0.6, 0.62, 0.66),
	"wall": Color(0.25, 0.25, 0.28, 0.5),
}

const MINER_MODEL_PATH := "res://assets/models/character-g.glb"
## Kenney 機械人 glTF 企立高度實測 ≈2.7 世界單位（見 ALTA-153 留言）；
## 原本盒仔灰模高 0.4，用呢個縮放令礦工喺山腳大細睇落同灰模年代接近，
## 冇忽然變得成隻山咁高。
const MINER_VISUAL_SCALE := 0.15

static var _miner_scene: PackedScene = null
static var _miner_load_attempted := false


# ══════════════════════ 材質 ══════════════════════

static func flat_material(
	color: Color, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0,
	metallic: float = 0.0, roughness: float = 0.9
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# per-vertex 光照：令平面 mesh 顯得更「塊面」，冇咁多平滑漸層，
	# 係 flat-shaded low-poly 嘅主要手感來源（几何本身已經係低面數）。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


# ══════════════════════ 基本形狀（同 _make_box 一樣簽名，一行取代） ══════════════════════

## 同原本 `_make_box(size, color)` 完全一樣嘅簽名／回傳形狀，call site
## 唔使改任何位置／碰撞代碼，淨係換咗 flat-shaded 材質。
static func make_flat_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = flat_material(color)
	return mesh_instance

## 帶金屬感嘅盒仔（爐身／滾筒／車身呢類機械物件），可選發光（爐口／
## UPGRADE 墊）。
static func make_metal_box(
	size: Vector3, color: Color, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = flat_material(color, emission, emission_energy, 0.6, 0.35)
	return mesh_instance

## 低面數圓柱（預設 8 邊，代替 CylinderMesh 預設嘅 32 邊圓滑面）——
## 散幣／齒輪／滾筒呢類細件用嚟撐 low-poly 感。
static func make_low_poly_cylinder(
	radius: float, height: float, color: Color, sides: int = 8, metallic: float = 0.4
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = sides
	cyl.rings = 1
	mesh_instance.mesh = cyl
	mesh_instance.material_override = flat_material(color, Color(0, 0, 0), 0.0, metallic, 0.4)
	return mesh_instance

## 礦物碎料：楔形「石卡」代替純色盒仔，睇落似粒石／礦而唔係方塊。
static func make_ore_chunk(size: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(size, size * 1.3, size)
	prism.left_to_right = 0.5
	mesh_instance.mesh = prism
	mesh_instance.material_override = flat_material(color, Color(0, 0, 0), 0.0, 0.15, 0.5)
	return mesh_instance


# ══════════════════════ 礦工：Kenney CC0 機械人 glTF ══════════════════════

## 礦工：Kenney「Blocky Characters」機械人皮膚（CC0，見 CREDITS.md），
## 代替純色盒仔，符合 issue 要求「唔可以似 Idle Zombie Miner」。讀取
## 唔到（例如某個 export 漏帶 assets/）就 fallback 返盒仔，唔會累成個
## 場景 build 唔到。
static func make_miner() -> Node3D:
	if not _miner_load_attempted:
		_miner_load_attempted = true
		if ResourceLoader.exists(MINER_MODEL_PATH):
			_miner_scene = load(MINER_MODEL_PATH)
	if _miner_scene == null:
		return make_flat_box(Vector3(0.22, 0.4, 0.22), Color(0.95, 0.75, 0.1))
	var inst: Node3D = _miner_scene.instantiate()
	inst.scale = Vector3.ONE * MINER_VISUAL_SCALE
	return inst


# ══════════════════════ HUD 圖示 ══════════════════════

## Kenney Game Icons（白底 PNG，見 CREDITS.md）／自製 icon 讀成
## TextureRect，用 `modulate` 上色，HUD 用嚟代替純文字標籤。搵唔到就
## 留白（TextureRect 冇 texture 唔會 crash），唔會累成個 HUD build 唔到。
static func make_icon(path: String, size: float = 22.0, tint: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	if ResourceLoader.exists(path):
		rect.texture = load(path)
	rect.custom_minimum_size = Vector2(size, size)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = tint
	return rect

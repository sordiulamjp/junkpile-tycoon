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

## 場地規格 v2（ALTA-219，2026-09-13）色板——取代 VR-06b 嗰組「爐口藍火
## 對比」決定：呢版 issue 明文規定「爐藍 #2E5C9E + 橙光」，唔再刻意同
## IZM 反差（"furnace_glow" 由藍改返橙）；岩壁／地面／岩浆／墊門紫／
## 車色全部跟返 issue 「色板（暖色）」段嘅十六進位值。
const PALETTE := {
	"cave": Color(0.42, 0.36, 0.3),
	"cave_light": Color(0.5, 0.44, 0.36),
	"belt": Color(0.35, 0.35, 0.38),
	"furnace_body": Color("#2E5C9E"), # 場地規格 v2：爐藍
	"furnace_glow": Color("#FF5A1F"), # 場地規格 v2：爐口橙光（跟岩浆同一團暖橙）
	"warehouse_body": Color(0.2, 0.4, 0.65),
	"warehouse_roof": Color(0.14, 0.28, 0.46),
	"lava": Color("#FF5A1F"),        # 場地規格 v2：岩浆
	"bridge_wood": Color(0.45, 0.3, 0.15),
	"gear_metal": Color(0.6, 0.62, 0.66),
	"wall": Color(0.25, 0.25, 0.28, 0.5),
	"canyon_wall": Color("#6B4A3A"),      # 場地規格 v2：岩壁底色
	"canyon_wall_light": Color("#8C6A55"), # 場地規格 v2：岩壁頂面淺一級
	"canyon_wall_dark": Color(0.16, 0.1, 0.06),
	"ground_warm": Color("#B79C7E"),  # 場地規格 v2：地面
	"ground_tread": Color(0.55, 0.46, 0.36),
	"entrance_eave": Color(0.5, 0.3, 0.15),
	"lamp_warm": Color(1.0, 0.78, 0.4),
	"pad_purple": Color("#5B3A8C"),   # 場地規格 v2：墊／門紫
}

## VR-06c：波池礦物階色板——同 main.gd::_ore_color() 用同一套礦物階名
## （stone／coal／copper／gold／diamond／crown，見 constants.gd
## ore_tier_value docx 數值）同同一組數值。兩處獨立維護：main.gd 嗰個
## 用喺山腳碎料（有判分意義嘅 ore_key），呢度用喺車場波池（純表現層，
## 冇判分意義），刻意唔拉一個共用依賴，各自留喺自己嘅表現層檔案。
const ORE_TIER_COLOR := {
	"stone": Color(0.55, 0.55, 0.55),
	"coal": Color(0.15, 0.15, 0.15),
	"copper": Color("#C8742A"),  # 場地規格 v2：礦粒銅
	"gold": Color("#F2B830"),    # 場地規格 v2：礦粒金
	"diamond": Color("#9FE3F0"), # 場地規格 v2：礦粒鑽
	"crown": Color(0.85, 0.65, 0.95),
}
## 金／鑽／皇冠三階波「少少自發光」（issue 視覺參考），其餘唔發光。
const ORE_TIER_EMISSIVE_TIERS := ["gold", "diamond", "crown"]

## VR-17b（ALTA-399）：ALTA-249 headless-Blender 灰模換模，接線用嘅 .glb 路徑。
const MODEL_DOZER_BODY := "res://assets/models/dozer_body.glb"
const MODEL_DOZER_BLADE := "res://assets/models/dozer_blade.glb"
const MODEL_DOZER_WING := "res://assets/models/dozer_wing.glb"
const MODEL_FURNACE := "res://assets/models/furnace.glb"
const MODEL_MINE_ENTRANCE := "res://assets/models/mine_entrance.glb"
const MODEL_MINE_CART := "res://assets/models/mine_cart.glb"
const MODEL_ROCK := [
	"res://assets/models/rock_0.glb",
	"res://assets/models/rock_1.glb",
	"res://assets/models/rock_2.glb",
]
const MODEL_WAREHOUSE := "res://assets/models/warehouse.glb"
const MODEL_CRATE := "res://assets/models/crate.glb"
const MODEL_LAMP_POST := "res://assets/models/lamp_post.glb"
const MODEL_GARAGE := "res://assets/models/garage.glb"

const MINER_MODEL_PATH := "res://assets/models/character-g.glb"
## Kenney 機械人 glTF 企立高度實測 ≈2.7 世界單位（見 ALTA-153 留言）。
## 用戶實機回饋（round2 第 5 點）：礦工放大到約 0.35 世界單位高——呢個
## 絕對數字同之前嘅 0.15（≈0.405 高）好接近，甚至字面上係細咗；但用戶
## 睇緊嘅係「螢幕上顯得幾大」，而 VR-06b（ALTA-214）已經將鏡頭大幅拉近
## （場地佔畫面約 70%，代替之前為咗一次框晒 12 層山＋帶＋爐＋倉而被逼
## 拉到好遠嘅正交相機），所以呢個世界單位數字底下，礦工實際喺螢幕
## 顯得大好多。跟返用戶畀嘅實數（0.35），唔用自己嗰個「感覺上應該更大」
## 嘅估算。
const MINER_VISUAL_SCALE := 0.2

static var _miner_scene: PackedScene = null
static var _miner_load_attempted := false

## VR-17b：通用 .glb 換模入口，`make_miner()` 嗰套 pattern 攞出嚟做任何
## 一件模型都用得——`ResourceLoader.exists` + static cache（keyed by path，
## `has()` 分得出「未試過」同「試過但搵唔到」）+ 缺檔就用 `fallback()`
## 起返原本嘅灰模，成個場景照樣 build 得出。
##
## Review round 1（ALTA-399）修正：`rotation_degrees.x = 90.0`（Blender
## Z-up 匯出做 glTF Y-up，呢個先轉返場地 Z-up 慣例）同埋 `scale` 淨係
## 喺真係讀到 glb 嗰陣先套用，落喺呢度而唔係 call site——fallback 灰模
## 本身已經係場地座標砌，唔應該再食多一次旋轉／縮放（吼喺場景會瞓低／
## 雙重縮放）。`scale` 用嘅係 glTF 匯入後、rotation 之前嘅 local 軸——即係
## Y = 場地高度（rotation_degrees.x=90 之後先變 Z）、Z = 場地深度（負 Y）；
## call site 揸 site 語意嘅 Vector3(x, z, y) 傳入，唔好直接用 site 嘅
## Vector3(x, y, z)。`model_position` 同一道理：淨係喺讀到真 glb 先加落去
## （例如鏟斗兩側 wing 個 x 位置要跟 tier 闊度）——fallback 已經自己喺
## site 座標度擺好位，唔應該再疊多一層 offset。
static var _model_cache: Dictionary = {}
static func make_model(
	path: String, fallback: Callable,
	model_scale: Vector3 = Vector3.ONE, model_position: Vector3 = Vector3.ZERO
) -> Node3D:
	if not _model_cache.has(path):
		_model_cache[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _model_cache[path]
	if scene == null:
		return fallback.call()
	var inst: Node3D = scene.instantiate()
	inst.rotation_degrees.x = 90.0
	inst.scale = model_scale
	inst.position = model_position
	return inst


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

## VR-06b：低多邊形切面岩壁——一嚿楔形（PrismMesh）代表一塊岩石切面，
## `skew` 揸 `left_to_right`（0~1）令每嚿唔對稱，加埋 call site 嘅隨機
## 旋轉／大細 jitter 先砌到「唔規則切面」感，唔靠貼圖（issue 視覺參考：
## faceted rock，flat shading，冇貼圖）。
static func make_rock_facet(size: Vector3, color: Color, skew: float = 0.5) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = size
	prism.left_to_right = clampf(skew, 0.0, 1.0)
	mesh_instance.mesh = prism
	mesh_instance.material_override = flat_material(color, Color(0, 0, 0), 0.0, 0.05, 0.95)
	return mesh_instance

## VR-06b：礦道入口嘅「一盞燈」——低面數圓球，帶少少自發光，擺喺熔爐／
## 倉嘅屋簷邊做暖色燈籠感（issue 視覺參考：「方形入口 + 屋簷 + 一盞燈」
## 語言，用自己色）。
static func make_lamp(radius: float, color: Color, emission_energy: float = 1.2) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh_instance.mesh = sphere
	mesh_instance.material_override = flat_material(color, color, emission_energy, 0.0, 0.6)
	return mesh_instance

## VR-06c：波池粒轉真 rigid 之後嘅單粒 mesh（見 frenzy_yard_view.gd
## _activate_pool_slot()）——同 make_lamp() 一樣係低面數圓球，呢度獨立
## 開一個命名清晰嘅入口，實現直接複用 make_lamp()。
static func make_ore_ball(radius: float, color: Color, emission_energy: float = 0.0) -> MeshInstance3D:
	return make_lamp(radius, color, emission_energy)

## VR-06c：波池靜態堆——一個 MultiMeshInstance3D 代表一個礦物階，幾千粒
## 共用一個 SphereMesh + material，GPU instancing 一個 draw call畫晒
## （issue 視覺參考：「靜態堆用 MultiMeshInstance3D，幾千粒零成本」）。
## call site（frenzy_yard_view.gd _build_ore_pool()）逐粒 set_instance_transform()
## 擺位；轉做 rigid 嗰陣將對應 index 嘅 transform 縮做 0（_hide_pool_slot()）
## 令個靜態粒隱形，唔會同真 rigid 個 mesh 疊埋一齊。
## 用戶 2026-09-21：礦碎係非圓體（盒仔），唔會滾走；靜態堆用 BoxMesh instancing
static func make_ore_chunk_multimesh(size: Vector3, color: Color, emission_energy: float, instance_count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = size
	mm.mesh = box
	mm.instance_count = maxi(instance_count, 0)
	mmi.multimesh = mm
	mmi.material_override = flat_material(color, color, emission_energy, 0.0, 0.6)
	return mmi

static func make_ore_pool_multimesh(radius: float, color: Color, emission_energy: float, instance_count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mm.mesh = sphere
	mm.instance_count = maxi(instance_count, 0)
	mmi.multimesh = mm
	mmi.material_override = flat_material(color, color, emission_energy, 0.0, 0.6)
	return mmi


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
##
## Review 意見（ALTA-214 round 1）：冧咗 `expand_mode` 就會維持預設
## `EXPAND_KEEP_SIZE`——`custom_minimum_size` 淨係下限，TextureRect 實際
## 最細仍然係貼圖原生大細（coin／eco_leaf 128px，其餘 icon 50px），令
## 「size」參數形同虛設，頂 HUD 資源列因而爆框。加 `EXPAND_IGNORE_SIZE`
## 令貼圖原生大細唔再頂住 layout minimum size，`size` 先真係話事。
static func make_icon(path: String, size: float = 22.0, tint: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	if ResourceLoader.exists(path):
		rect.texture = load(path)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = tint
	return rect

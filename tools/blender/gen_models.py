# Headless Blender generator for Junkpile Tycoon low-poly .glb models (VR-17 / ALTA-249).
#
# Run (no GUI needed):
#   ~/blender-4.2/blender -b -P tools/blender/gen_models.py -- assets/models
#
# Conventions
# - Author in Blender Z-up using the SITE convention of scenes/field.gd:
#   x = width, y = depth (+y = front / towards the blade), z = height.
#   The glTF exporter converts to Y-up; Godot call sites then apply
#   rotation_degrees.x = 90 (same as make_miner()), which maps the model back
#   to site axes 1:1. So every size / offset below is the same number the
#   grey-box code uses today.
# - Flat shading, one solid-colour material per part, no textures -> each
#   .glb is a few KB. Colours are the IG purple-rock palette / car hexes
#   already in the code (MineConstants.PALETTE, field.gd).
# - Collision is NOT part of these models; Godot keeps its own shapes.
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

_mats = {}


def hexc(h, mul=1.0):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    # sRGB -> linear (glTF baseColorFactor is linear)
    def lin(c):
        c *= mul
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


def mat(name, color, metallic=0.0, rough=0.7, emit=None, emit_strength=0.0):
    key = (name, color, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hexc(color)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = hexc(emit)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    _mats[key] = m
    return m


def _new_obj(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(material)
    for p in me.polygons:
        p.use_smooth = False
    bpy.context.collection.objects.link(ob)
    return ob


def box(name, size, pos, material, rot=(0, 0, 0), bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    ob = _new_obj(name, bm, material)
    ob.rotation_euler = rot
    ob.location = pos
    return ob


def cyl(name, radius, height, pos, material, sides=8, axis="z", r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius,
                          radius2=radius if r2 is None else r2, depth=height)
    ob = _new_obj(name, bm, material)
    if axis == "x":
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "y":
        ob.rotation_euler = (math.pi / 2, 0, 0)
    ob.location = pos
    return ob


def wedge(name, size, pos, material, rot=(0, 0, 0)):
    """Triangular prism: base size.x * size.y, height size.z, ridge along x."""
    w, d, h = size
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in [
        (-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0),
        (-w / 2, 0, h), (w / 2, 0, h)]]
    for f in [(0, 1, 2, 3), (0, 4, 5, 1), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2)]:
        bm.faces.new([v[i] for i in f])
    bm.normal_update()
    ob = _new_obj(name, bm, material)
    ob.rotation_euler = rot
    ob.location = pos
    return ob


def curved_plate(name, material, w=1.0, steps=14, thick=0.04, height=0.16, lip=0.03):
    """Blade plate following the arc used by field.gd _rebuild_blade():
    centre line c(a) = (sin(a)*0.34*w, 0.2 + cos(a)*0.14*w), a in [-0.8, 0.8].
    Origin = car origin, so Coder can add it to _car_body at (0,0,0)."""
    bm = bmesh.new()
    rows = []
    for i in range(steps + 1):
        a = -0.8 + 1.6 * i / steps
        c = Vector((math.sin(a) * 0.34 * w, 0.2 + math.cos(a) * 0.14 * w, 0.0))
        d = Vector((math.cos(a) * 0.34 * w, -math.sin(a) * 0.14 * w, 0.0)).normalized()
        n = Vector((-d.y, d.x, 0.0))  # points forward (+y at centre)
        n = n if n.y >= 0 else -n
        half = thick / 2
        rows.append([
            c - n * half + Vector((0, 0, -height / 2)),
            c + n * half + Vector((0, 0, -height / 2)),
            c + n * half + Vector((0, 0, height / 2)),
            c - n * (half + lip) + Vector((0, 0, height / 2 + lip)),  # curled top lip
        ])
    vrows = [[bm.verts.new(p) for p in r] for r in rows]
    for i in range(steps):
        a, b = vrows[i], vrows[i + 1]
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new([a[j], b[j], b[k], a[k]])
    bm.faces.new(vrows[0][::-1])
    bm.faces.new(vrows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _new_obj(name, bm, material)


def rock(name, size, material, seed=0, segs=7):
    """Rounded low-poly boulder filling [-0.5,0.5]x[-0.5,0.5]x[0,1] * size."""
    import random
    rnd = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.5)
    for v in bm.verts:
        v.co.x *= size[0] * (1.0 + rnd.uniform(-0.12, 0.12))
        v.co.y *= size[1] * (1.0 + rnd.uniform(-0.12, 0.12))
        v.co.z = (v.co.z + 0.5) * size[2] * (1.0 + rnd.uniform(-0.06, 0.10))
    # squash + flatten the bottom so it reads as a boulder sitting on the ground
    for v in bm.verts:
        v.co.z = min(v.co.z, 0.92 * size[2])
        if v.co.z < 0.22 * size[2]:
            v.co.z = 0.0
            v.co.x *= 1.15; v.co.y *= 1.15
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    return _new_obj(name, bm, material)


def export(objs, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    root = bpy.context.view_layer.objects.active
    root.name = os.path.splitext(filename)[0]
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_image_format="NONE", export_normals=True,
                              export_texcoords=False, export_animations=False,
                              export_skins=False, export_morph=False, export_lights=False,
                              export_cameras=False, export_extras=False)
    bpy.data.objects.remove(root, do_unlink=True)
    print("wrote", path, os.path.getsize(path), "bytes")


# ---------------------------------------------------------------- palette
YEL, YEL_L, DARK, METAL = "#F2C230", "#F7D35A", "#26262B", "#8A8A94"
WALL, WALL_L, WALL_D = "#7A4AB0", "#9A62C8", "#5E3A8C"
FURN, FIRE, WOOD, WOOD_D, CRATE = "#2E2E33", "#FF7A1E", "#8B5A2B", "#6B4A24", "#B8894A"
GOLD, LAMP, BOARD, HOLE = "#F2B830", "#FFD27A", "#15151A", "#1A1420"

bpy.ops.wm.read_factory_settings(use_empty=True)

# 1. Bulldozer body (origin = car origin; add to _car_body at (0,0,0)).
m_yel, m_yel_l = mat("dozer_yellow", YEL, 0.6, 0.35), mat("dozer_cab", YEL_L, 0.6, 0.35)
m_dark, m_metal = mat("track_dark", DARK, 0.3, 0.8), mat("metal", METAL, 0.8, 0.3)
parts = [
    box("body", (0.3, 0.32, 0.16), (0, 0, 0), m_yel, bevel=0.015),
    box("hood", (0.24, 0.14, 0.06), (0, 0.1, 0.10), m_yel),
    box("cab", (0.18, 0.16, 0.12), (0, -0.04, 0.13), m_yel_l, bevel=0.012),
    box("cab_glass", (0.19, 0.10, 0.07), (0, -0.04, 0.15), mat("glass", "#3A5C7A", 0.2, 0.2)),
    box("roof", (0.21, 0.19, 0.02), (0, -0.04, 0.20), m_dark),
    cyl("exhaust", 0.02, 0.14, (0.09, 0.09, 0.19), m_metal, 6),
]
for sx in (-1, 1):
    parts.append(box("track%d" % sx, (0.09, 0.4, 0.1), (sx * 0.2, 0.0, -0.05), m_dark, bevel=0.02))
    for wy in (-0.13, 0.0, 0.13):
        parts.append(cyl("wheel", 0.045, 0.1, (sx * 0.2, wy, -0.05), m_metal, 8, axis="x"))
export(parts, "dozer_body.glb")

# 2. Blade plate at tier width w=1 (origin = car origin). Coder scales
#    x by BLADE_SCALE and z by (0.16+0.05*(w-1))/0.16; colour via material
#    override per tier (col_tint in field.gd).
export([curved_plate("blade", m_yel)], "dozer_blade.glb")

# 3. One side wing (right side, +x). Mirror with scale.x = -1 for the left.
#    Origin = car origin; wing base at z=-0.07 so wing_h scales from the deck.
m_wing = mat("wing", YEL, 0.6, 0.35)
export([box("wing", (0.04, 0.26, 0.14), (0.38, 0.14, 0.0), m_wing, bevel=0.008)], "dozer_wing.glb")

# 4. Furnace (origin = Furnace node origin on the ground; same offsets as field.gd:448-487).
m_furn, m_furn_l = mat("furnace", FURN, 0.5, 0.5), mat("furnace_l", "#3A3A40", 0.5, 0.5)
m_fire = mat("furnace_fire", FIRE, 0.0, 0.6, emit=FIRE, emit_strength=1.8)
parts = [
    box("furn_body", (1.1, 0.8, 0.6), (0, 0.2, 0.3), m_furn, bevel=0.03),
    box("furn_rim", (1.16, 0.86, 0.06), (0, 0.2, 0.62), m_furn_l),
    cyl("chimney", 0.12, 0.35, (0.28, 0.35, 0.775), m_furn_l, 8, r2=0.10),
    cyl("chimney_cap", 0.15, 0.04, (0.28, 0.35, 0.96), m_furn, 8),
    box("mouth", (0.6, 0.06, 0.32), (0, -0.17, 0.2), m_fire),
    box("mouth_frame_t", (0.68, 0.05, 0.05), (0, -0.19, 0.38), m_furn_l),
    box("mouth_frame_l", (0.05, 0.05, 0.38), (-0.33, -0.19, 0.21), m_furn_l),
    box("mouth_frame_r", (0.05, 0.05, 0.38), (0.33, -0.19, 0.21), m_furn_l),
    box("board", (0.9, 0.12, 0.34), (0, 0.45, 0.78), mat("board", BOARD, 0.2, 0.8), rot=(-0.35, 0, 0)),
]
for sx in (-1, 1):
    parts.append(box("leg", (0.12, 0.12, 0.08), (sx * 0.45, 0.2, 0.02), m_furn_l))
export(parts, "furnace.glb")

# 5. Mine entrance (origin = post base, same as mine_zone.gd _build_entrance).
m_wood, m_wood_d = mat("wood", WOOD, 0.0, 0.8), mat("wood_dark", WOOD_D, 0.0, 0.8)
m_lamp = mat("lamp", LAMP, 0.0, 0.4, emit=LAMP, emit_strength=1.2)
parts = [box("hole", (0.6, 0.02, 0.5), (0, 0.08, 0.0), mat("hole", HOLE, 0.0, 1.0)),
         box("lintel", (0.8, 0.12, 0.09), (0, 0, 0.31), m_wood_d),
         wedge("gable", (0.9, 0.16, 0.12), (0, 0, 0.355), m_wood_d)]
for px in (-0.32, 0.32):
    parts += [box("post", (0.09, 0.09, 0.55), (px, 0, 0), m_wood),
              box("brace", (0.04, 0.10, 0.18), (px * 0.78, 0.0, 0.19), m_wood, rot=(0, -0.6 * (1 if px > 0 else -1), 0)),
              cyl("lamp", 0.045, 0.06, (px, -0.08, 0.2), m_lamp, 8, axis="y")]
export(parts, "mine_entrance.glb")

# 6. Mine cart (origin = centre of the 0.22 x 0.16 x 0.14 box; collider is a child).
m_gold = mat("cart_gold", GOLD, 0.6, 0.35)
bm = bmesh.new()
lo, hi = 0.75, 1.0  # tapered hopper
v = [bm.verts.new((x * 0.11 * s, y * 0.08 * s, z)) for z, s in ((-0.07, lo), (0.07, hi)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
for f in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
    bm.faces.new([v[i] for i in f])
bm.normal_update()
parts = [_new_obj("hopper", bm, m_gold),
         box("rim_f", (0.24, 0.02, 0.02), (0, 0.08, 0.07), m_dark),
         box("rim_b", (0.24, 0.02, 0.02), (0, -0.08, 0.07), m_dark),
         box("rim_l", (0.02, 0.18, 0.02), (-0.11, 0, 0.07), m_dark),
         box("rim_r", (0.02, 0.18, 0.02), (0.11, 0, 0.07), m_dark),
         box("axle_f", (0.2, 0.02, 0.02), (0, 0.05, -0.07), m_metal),
         box("axle_b", (0.2, 0.02, 0.02), (0, -0.05, -0.07), m_metal)]
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(cyl("wheel", 0.03, 0.02, (sx * 0.1, sy * 0.05, -0.07), m_dark, 8, axis="x"))
export(parts, "mine_cart.glb")

# 7. Rocks: three unit boulders (1 x 1 x 1, base on z=0). Coder scales to
#    the random size vector used by field.gd _rock() and keeps _static_box.
for i, (tone, seed) in enumerate(((WALL, 1), (WALL_L, 7), (WALL_D, 13))):
    export([rock("rock", (1, 1, 1), mat("rock%d" % i, tone, 0.0, 0.9), seed=seed)], "rock_%d.glb" % i)

# 8. Warehouse (origin = body centre, i.e. mine_zone.gd base position).
m_wh = mat("wh_body", "#835399", 0.1, 0.7)   # wall_light darkened 0.15
m_wh_roof = mat("wh_roof", WALL_D, 0.1, 0.7)
parts = [box("wh", (0.8, 0.55, 0.5), (0, 0, 0), m_wh, bevel=0.015),
         box("roof", (0.9, 0.65, 0.06), (0, 0, 0.28), m_wh_roof),
         wedge("roof_top", (0.9, 0.65, 0.16), (0, 0, 0.31), m_wh_roof),
         box("door", (0.3, 0.02, 0.32), (0, -0.28, -0.08), mat("wh_door", "#42295F", 0.1, 0.7)),
         box("sign", (0.4, 0.02, 0.1), (0, -0.285, 0.15), m_gold)]
export(parts, "warehouse.glb")

# 9. Crate (0.22 x 0.22 x 0.18, centred) and barrel (r 0.11, h 0.24, base on z=0).
m_crate, m_band = mat("crate", CRATE, 0.0, 0.8), mat("band", WOOD_D, 0.0, 0.8)
parts = [box("crate", (0.22, 0.22, 0.18), (0, 0, 0), m_crate, bevel=0.01),
         box("band_x", (0.24, 0.06, 0.2), (0, 0, 0), m_band),
         box("band_y", (0.06, 0.24, 0.196), (0, 0, 0), m_band)]
export(parts, "crate.glb")
m_barrel = mat("barrel", "#3368B8", 0.4, 0.5)
parts = [cyl("barrel", 0.11, 0.24, (0, 0, 0.12), m_barrel, 10),
         cyl("hoop_t", 0.115, 0.02, (0, 0, 0.20), m_metal, 10),
         cyl("hoop_b", 0.115, 0.02, (0, 0, 0.04), m_metal, 10)]
export(parts, "barrel.glb")

# 10. Lamp post (origin = ground; matches field.gd _build_props sizes).
parts = [cyl("post", 0.04, 1.1, (0, 0, 0.55), mat("post", "#3A3140", 0.3, 0.7), 6),
         cyl("lamp_head", 0.08, 0.12, (0, 0, 1.15), m_lamp, 8),
         cyl("lamp_cap", 0.1, 0.03, (0, 0, 1.22), m_dark, 8)]
export(parts, "lamp_post.glb")

# 11. Garage / upgrade hut (origin = Garage node origin on the ground; field.gd _build_garage).
m_shed = mat("shed", "#4A4652", 0.3, 0.7)
parts = [box("shed", (0.95, 0.7, 0.5), (0, 0, 0.25), m_shed, bevel=0.015),
         box("roof", (1.05, 0.8, 0.08), (0, 0, 0.54), m_yel),
         wedge("roof_top", (1.05, 0.8, 0.18), (0, 0, 0.58), m_yel),
         box("door", (0.5, 0.04, 0.38), (0, -0.36, 0.2), m_dark),
         box("wrench_a", (0.06, 0.32, 0.04), (0, -0.37, 0.62), mat("chrome", "#C9CFD6", 0.8, 0.3), rot=(0, 0, 0.6)),
         box("wrench_b", (0.16, 0.12, 0.04), (0.1, -0.37, 0.74), mat("chrome", "#C9CFD6", 0.8, 0.3), rot=(0, 0, 0.6))]
export(parts, "garage.glb")

print("done ->", OUT_DIR)

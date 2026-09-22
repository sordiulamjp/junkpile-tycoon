# Render a preview PNG of every .glb in assets/models (headless Cycles CPU).
#   ~/blender-4.2/blender -b -P tools/blender/preview.py -- assets/models out_dir
import bpy, os, sys, math, glob
from mathutils import Vector
src, out = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(out, exist_ok=True)
for path in sorted(glob.glob(os.path.join(src, "*.glb"))):
    if "character" in path:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"          # CPU path tracing: works on a GPU-less VM
    sc.cycles.device = "CPU"; sc.cycles.samples = 24; sc.cycles.use_denoising = False
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.3, 0.25, 0.36, 1); bg.inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
    sun.data.energy = 3.0; sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    ctr = (lo + hi) / 2; rad = max((hi - lo).length / 2, 0.1)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = rad * 2.3
    d = Vector((-1.0, -1.4, 0.95)).normalized()
    cam.location = ctr + d * rad * 4
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, os.path.basename(path).replace(".glb", ".png"))
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)

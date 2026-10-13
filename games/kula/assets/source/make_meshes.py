# Builds face.glb and ball.glb for Kula. Run from any directory:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python games/kula/assets/source/make_meshes.py
#
# Blender is +Z up. The glTF export turns that into +Y up, so a quad facing
# Blender +Z faces glTF +Y, like the engine's primitive plane.

import math
import os

import bmesh
import bpy

MESHES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "meshes")

# The engine multiplies these by the draw's tint, so the face centre matches
# the primitive plane's grey and the border reads lighter under any tint.
FACE_CENTRE = (0.8, 0.8, 0.8, 1.0)
FACE_BORDER = (1.0, 1.0, 1.0, 1.0)
FACE_BORDER_WIDTH = 0.06

BALL_WHITE = (0.9, 0.9, 0.9, 1.0)
BALL_RED = (0.8, 0.05, 0.03, 1.0)
BALL_SEGMENTS = 32
BALL_RINGS = 16
BALL_WEDGES = 8


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = colour
    return mat


def new_object(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, file_name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MESHES, file_name),
        export_format="GLB",
        use_selection=True,
        export_texcoords=False,
        export_animations=False,
    )


# A 1 x 1 quad centred on the origin: a centre square and a border ring of
# four quads round it. All faces wind counter-clockwise seen from +Z.
def make_face():
    clear_scene()
    half = 0.5
    inner_half = half - FACE_BORDER_WIDTH
    outer = [(-half, -half), (half, -half), (half, half), (-half, half)]
    inner = [(-inner_half, -inner_half), (inner_half, -inner_half), (inner_half, inner_half), (-inner_half, inner_half)]
    verts = [(x, y, 0.0) for x, y in outer + inner]
    centre = [(4, 5, 6, 7)]
    border = [(k, (k + 1) % 4, (k + 1) % 4 + 4, k + 4) for k in range(4)]
    mesh = bpy.data.meshes.new("face")
    mesh.from_pydata(verts, [], centre + border)
    mesh.materials.append(material("face_centre", FACE_CENTRE))
    mesh.materials.append(material("face_border", FACE_BORDER))
    for poly in mesh.polygons:
        poly.material_index = 0 if poly.index == 0 else 1
    mesh.update()
    export(new_object("face", mesh), "face.glb")


# A UV sphere of diameter 1, like the primitive sphere. The wedges run pole to
# pole, so a roll about any horizontal axis shows.
def make_ball():
    clear_scene()
    mesh = bpy.data.meshes.new("ball")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=BALL_SEGMENTS, v_segments=BALL_RINGS, radius=0.5)
    for f in bm.faces:
        c = f.calc_center_median()
        angle = math.atan2(c.y, c.x) % (2.0 * math.pi)
        f.material_index = int(angle / (2.0 * math.pi) * BALL_WEDGES) % 2
        f.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material("ball_white", BALL_WHITE))
    mesh.materials.append(material("ball_red", BALL_RED))
    export(new_object("ball", mesh), "ball.glb")


os.makedirs(MESHES, exist_ok=True)
make_face()
make_ball()

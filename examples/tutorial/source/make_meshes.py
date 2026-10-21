# Builds pip.glb, the tutorial character, into each chapter app that loads it.
# Run from the repository root with Blender 5.2:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python examples/tutorial/source/make_meshes.py
#
# Blender is +Z up and the export turns that into glTF +Y up. Blender -Y
# becomes glTF +Z, so Pip faces Blender -Y.

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

TUTORIAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Each chapter app keeps its own copy, so it runs with no ROCCO_ASSETS.
CHAPTERS = ["02-character", "03-moving"]

# The loader draws every part with the first part's roughness and metallic,
# so all materials share them.
ROUGHNESS = 0.5

# Linear colours.
SHELL = (0.78, 0.76, 0.7, 1.0)
JOINT = (0.22, 0.24, 0.27, 1.0)
ACCENT = (0.9, 0.22, 0.03, 1.0)
VISOR = (0.02, 0.035, 0.05, 1.0)
EYE = (0.25, 0.85, 1.0, 1.0)

SEGMENTS = 24
RINGS = 12

# A-pose: each arm hangs this far out from straight down.
ARM_ANGLE = math.radians(40.0)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# The export writes metallicFactor 0 and the roughness as roughnessFactor.
def material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    return mat


def placed(centre, size, angle_y=0.0):
    scale = Matrix.Diagonal(Vector((*size, 1.0)))
    return Matrix.Translation(Vector(centre)) @ Matrix.Rotation(angle_y, 4, "Y") @ scale


def paint(faces, index, smooth):
    for f in faces:
        f.material_index = index
        f.smooth = smooth


def faces_of(verts):
    return list(dict.fromkeys(f for v in verts for f in v.link_faces))


def ellipsoid(bm, index, centre, radii, angle_y=0.0):
    made = bmesh.ops.create_uvsphere(bm, u_segments=SEGMENTS, v_segments=RINGS, radius=1.0, matrix=placed(centre, radii, angle_y))
    paint(faces_of(made["verts"]), index, True)


# The flat sides stay flat shaded and only the bevels are smooth.
def rounded_box(bm, index, centre, half, bevel):
    made = bmesh.ops.create_cube(bm, size=2.0, matrix=placed(centre, half))
    verts = made["verts"]
    paint(faces_of(verts), index, False)
    edges = list(dict.fromkeys(e for v in verts for e in v.link_edges))
    rounded = bmesh.ops.bevel(bm, geom=verts + edges, offset=bevel, segments=3, profile=0.5, affect="EDGES")
    paint(rounded["faces"], index, True)


def cylinder(bm, index, centre, radius, depth):
    made = bmesh.ops.create_cone(bm, cap_ends=True, segments=SEGMENTS, radius1=radius, radius2=radius, depth=depth, matrix=Matrix.Translation(Vector(centre)))
    paint(faces_of(made["verts"]), index, True)


# Without this, the faces come out in a different order on each run. A fixed
# order keeps the committed file the same from run to run.
def sort_elements(bm):
    sort_by(bm.verts, lambda v: tuple(round(c, 6) for c in v.co))
    sort_by(bm.faces, lambda f: (f.material_index, sorted(v.index for v in f.verts)))


# BMesh sorts by a number only, so each element sorts by its rank.
def sort_by(seq, key):
    rank = {element: i for i, element in enumerate(sorted(seq, key=key))}
    seq.sort(key=lambda element: rank[element])
    seq.index_update()


# One mesh with each limb apart from the body, so a later rig can weight
# each limb to one bone. The feet stand on z 0.
def make_pip():
    clear_scene()
    materials = [material(name, colour) for name, colour in [("shell", SHELL), ("joint", JOINT), ("accent", ACCENT), ("visor", VISOR), ("eye", EYE)]]
    shell, joint, accent, visor, eye = range(len(materials))
    bm = bmesh.new()

    for side in (-1.0, 1.0):
        ellipsoid(bm, joint, (side * 0.1, 0.0, 0.2), (0.06, 0.06, 0.13))
        ellipsoid(bm, accent, (side * 0.1, -0.03, 0.045), (0.075, 0.1, 0.045))
        shoulder = Vector((side * 0.2, 0.0, 0.56))
        down = Vector((side * math.sin(ARM_ANGLE), 0.0, -math.cos(ARM_ANGLE)))
        ellipsoid(bm, joint, shoulder + down * 0.13, (0.05, 0.05, 0.13), -side * ARM_ANGLE)
        ellipsoid(bm, shell, shoulder + down * 0.29, (0.065, 0.065, 0.065))

    rounded_box(bm, shell, (0.0, 0.0, 0.45), (0.19, 0.14, 0.15), 0.06)
    rounded_box(bm, accent, (0.0, -0.135, 0.44), (0.08, 0.02, 0.06), 0.015)
    rounded_box(bm, accent, (0.0, 0.17, 0.47), (0.13, 0.05, 0.12), 0.03)

    ellipsoid(bm, shell, (0.0, 0.0, 0.8), (0.23, 0.21, 0.2))
    ellipsoid(bm, visor, (0.0, -0.15, 0.81), (0.17, 0.08, 0.1))
    for side in (-1.0, 1.0):
        ellipsoid(bm, eye, (side * 0.065, -0.225, 0.82), (0.03, 0.012, 0.04))
    cylinder(bm, joint, (0.0, 0.0, 1.03), 0.012, 0.1)
    ellipsoid(bm, accent, (0.0, 0.0, 1.1), (0.035, 0.035, 0.035))

    sort_elements(bm)
    mesh = bpy.data.meshes.new("pip")
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new("pip", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_texcoords=False,
        export_animations=False,
    )


pip = make_pip()
for chapter in CHAPTERS:
    meshes = os.path.join(TUTORIAL, chapter, "assets", "meshes")
    os.makedirs(meshes, exist_ok=True)
    export(pip, os.path.join(meshes, "pip.glb"))

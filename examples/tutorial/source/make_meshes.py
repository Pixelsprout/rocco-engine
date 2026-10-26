# Builds pip.glb, the rigged tutorial character, into each chapter app that
# loads it, and the small skinned fixture for the engine's loader tests.
# Run from the repository root with Blender 5.2:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python examples/tutorial/source/make_meshes.py
#
# Blender is +Z up and the export turns that into glTF +Y up. Blender -Y
# becomes glTF +Z, so Pip faces Blender -Y and Pip's left is Blender +X.

import json
import math
import os
import struct

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

TUTORIAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FIXTURE = os.path.join(TUTORIAL, "..", "..", "engine", "testdata", "skinned.glb")

# Each chapter app keeps its own copy, so it runs with no ROCCO_ASSETS.
CHAPTERS = ["02-character", "03-moving", "04-lights", "05-pickups", "06-door", "07-hud", "08-sound", "09-gamepad", "10-animation"]

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

FPS = 24

# The engine skins at most 64 Joints.
MAX_JOINTS = 64


def shoulder(side):
    return Vector((side * 0.2, 0.0, 0.56))


def arm_down(side):
    return Vector((side * math.sin(ARM_ANGLE), 0.0, -math.cos(ARM_ANGLE)))


# (name, parent, head, tail) in Blender space. The order is the vertex group
# order, so a vertex group index is a Joint index here.
def joint_layout():
    joints = [
        ("root", None, (0.0, 0.0, 0.0), (0.0, 0.0, 0.1)),
        ("hips", "root", (0.0, 0.0, 0.28), (0.0, 0.0, 0.34)),
        ("spine", "hips", (0.0, 0.0, 0.34), (0.0, 0.0, 0.62)),
        ("head", "spine", (0.0, 0.0, 0.62), (0.0, 0.0, 0.95)),
    ]
    for side, tag in ((1.0, "L"), (-1.0, "R")):
        elbow = shoulder(side) + arm_down(side) * 0.22
        hand = shoulder(side) + arm_down(side) * 0.36
        joints.append((f"upper_arm.{tag}", "spine", tuple(shoulder(side)), tuple(elbow)))
        joints.append((f"lower_arm.{tag}", f"upper_arm.{tag}", tuple(elbow), tuple(hand)))
    for side, tag in ((1.0, "L"), (-1.0, "R")):
        joints.append((f"upper_leg.{tag}", "hips", (side * 0.1, 0.0, 0.33), (side * 0.1, 0.0, 0.09)))
        joints.append((f"lower_leg.{tag}", f"upper_leg.{tag}", (side * 0.1, 0.0, 0.09), (side * 0.1, -0.1, 0.09)))
    return joints


JOINTS = joint_layout()
JOINT_NAMES = [name for name, _, _, _ in JOINTS]


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


# Binds every vertex that has no Joint yet to this one with weight 1.0, so
# call it after each part.
def bind(bm, joint):
    deform = bm.verts.layers.deform.verify()
    group = JOINT_NAMES.index(joint)
    for v in bm.verts:
        if not v[deform]:
            v[deform][group] = 1.0


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


# One mesh with each limb apart from the body, so each limb binds rigidly to
# one Joint. The feet stand on z 0.
def make_pip(materials):
    shell, joint, accent, visor, eye = range(len(materials))
    bm = bmesh.new()

    for side, tag in ((1.0, "L"), (-1.0, "R")):
        ellipsoid(bm, joint, (side * 0.1, 0.0, 0.2), (0.06, 0.06, 0.13))
        bind(bm, f"upper_leg.{tag}")
        ellipsoid(bm, accent, (side * 0.1, -0.03, 0.045), (0.075, 0.1, 0.045))
        bind(bm, f"lower_leg.{tag}")
        ellipsoid(bm, joint, shoulder(side) + arm_down(side) * 0.13, (0.05, 0.05, 0.13), -side * ARM_ANGLE)
        bind(bm, f"upper_arm.{tag}")
        ellipsoid(bm, shell, shoulder(side) + arm_down(side) * 0.29, (0.065, 0.065, 0.065))
        bind(bm, f"lower_arm.{tag}")

    rounded_box(bm, shell, (0.0, 0.0, 0.45), (0.19, 0.14, 0.15), 0.06)
    rounded_box(bm, accent, (0.0, -0.135, 0.44), (0.08, 0.02, 0.06), 0.015)
    rounded_box(bm, accent, (0.0, 0.17, 0.47), (0.13, 0.05, 0.12), 0.03)
    bind(bm, "spine")

    ellipsoid(bm, shell, (0.0, 0.0, 0.8), (0.23, 0.21, 0.2))
    ellipsoid(bm, visor, (0.0, -0.15, 0.81), (0.17, 0.08, 0.1))
    for side in (-1.0, 1.0):
        ellipsoid(bm, eye, (side * 0.065, -0.225, 0.82), (0.03, 0.012, 0.04))
    cylinder(bm, joint, (0.0, 0.0, 1.03), 0.012, 0.1)
    ellipsoid(bm, accent, (0.0, 0.0, 1.1), (0.035, 0.035, 0.035))
    bind(bm, "head")

    sort_elements(bm)
    mesh = bpy.data.meshes.new("pip")
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new("pip", mesh)
    bpy.context.scene.collection.objects.link(obj)
    for name in JOINT_NAMES:
        obj.vertex_groups.new(name=name)
    return obj


# Bones are not connected, so a Clip can move a Joint as well as turn it.
def make_rig():
    rig = bpy.data.objects.new("rig", bpy.data.armatures.new("rig"))
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = rig.data.edit_bones
    for name, parent, head, tail in JOINTS:
        bone = bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.roll = 0.0
        if parent is not None:
            bone.parent = bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def attach(obj, rig):
    obj.parent = rig
    modifier = obj.modifiers.new("rig", "ARMATURE")
    modifier.object = rig


# A Clip is a list of (frame, {joint: (lift, axis, degrees)}). lift moves the
# Joint up along Blender Z; axis and degrees turn it about an axis in rig
# space, relative to its parent.
def key_clip(rig, name, frames):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame, pose in frames:
        for pose_bone in rig.pose.bones:
            lift, axis, degrees = pose.get(pose_bone.name, (0.0, "X", 0.0))
            rest = pose_bone.bone.matrix_local.to_3x3()
            turn = Matrix.Rotation(math.radians(degrees), 3, axis)
            pose_bone.location = rest.inverted() @ Vector((0.0, 0.0, lift))
            pose_bone.rotation_quaternion = (rest.inverted() @ turn @ rest).to_quaternion()
            pose_bone.keyframe_insert("location", frame=frame, group=pose_bone.name)
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=pose_bone.name)
    # A Bezier key would export as CUBICSPLINE, which the loader refuses.
    for channelbag in action.layers[0].strips[0].channelbags:
        for curve in channelbag.fcurves:
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"
    for pose_bone in rig.pose.bones:
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.rotation_quaternion = Quaternion()


# The last key repeats the first, so each Clip loops when the game wraps its
# time with the duration.
def looped(seconds, step, pose_at):
    total = round(seconds * FPS)
    return [(frame, pose_at((frame % total) / total)) for frame in range(0, total + 1, step)]


# A slow breath: the body rises and falls once, the arms open a little and
# the head nods.
def idle_pose(phase):
    breath = (1.0 - math.cos(2.0 * math.pi * phase)) / 2.0
    return {
        "spine": (0.012 * breath, "X", 0.0),
        "head": (0.0, "X", -3.0 * breath),
        "upper_arm.L": (0.0, "Y", -4.0 * breath),
        "upper_arm.R": (0.0, "Y", 4.0 * breath),
    }


# One cycle: two steps. The body is lowest when the legs are furthest apart.
def walk_pose(phase):
    swing = math.sin(2.0 * math.pi * phase)
    bob = math.cos(4.0 * math.pi * phase)
    return {
        "spine": (0.012 * bob, "X", 0.0),
        "head": (0.0, "X", 2.0 * bob),
        "upper_leg.L": (0.0, "X", 28.0 * swing),
        "lower_leg.L": (0.0, "X", -14.0 * swing),
        "upper_leg.R": (0.0, "X", -28.0 * swing),
        "lower_leg.R": (0.0, "X", 14.0 * swing),
        "upper_arm.L": (0.0, "X", -24.0 * swing),
        "lower_arm.L": (0.0, "X", -8.0 * swing),
        "upper_arm.R": (0.0, "X", 24.0 * swing),
        "lower_arm.R": (0.0, "X", 8.0 * swing),
    }


def make_scene():
    clear_scene()
    bpy.context.scene.render.fps = FPS
    materials = [material(name, colour) for name, colour in [("shell", SHELL), ("joint", JOINT), ("accent", ACCENT), ("visor", VISOR), ("eye", EYE)]]
    rig = make_rig()
    pip = make_pip(materials)
    attach(pip, rig)
    rig.animation_data_create()
    key_clip(rig, "Idle", looped(2.0, 4, idle_pose))
    key_clip(rig, "Walk", looped(1.0, 2, walk_pose))
    rig.animation_data.action = None
    return pip, rig


# Unsampled export keeps the LINEAR keys as made.
def export(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_texcoords=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=False,
        export_skins=True,
    )


def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, "the first chunk is not JSON"
    return json.loads(data[20 : 20 + length])


# Reads the JSON chunk back, so a change to the export options that drops the
# Skin or a Clip fails the run.
def check(path):
    gltf = glb_json(path)
    skins = gltf.get("skins", [])
    assert len(skins) == 1, f"{len(skins)} Skins"
    joints = len(skins[0]["joints"])
    assert joints <= MAX_JOINTS, f"{joints} Joints"
    primitive = gltf["meshes"][0]["primitives"][0]
    assert "JOINTS_0" in primitive["attributes"] and "WEIGHTS_0" in primitive["attributes"], "no JOINTS_0 or WEIGHTS_0"
    clips = {}
    for animation in gltf.get("animations", []):
        samplers = animation["samplers"]
        assert all(s.get("interpolation", "LINEAR") == "LINEAR" for s in samplers), f"{animation['name']} has keys that are not LINEAR"
        times = [gltf["accessors"][s["input"]] for s in samplers]
        # Blender writes a key time as frame / fps, so a Clip keyed from frame 1 would start late.
        assert min(t["min"][0] for t in times) == 0.0, f"{animation['name']} does not start at 0 s"
        clips[animation["name"]] = max(t["max"][0] for t in times)
    assert sorted(clips) == ["Idle", "Walk"], f"Clips {sorted(clips)}"
    print(f"pip.glb: 1 Skin, {joints} Joints, " + ", ".join(f"{name} {duration:.3f} s" for name, duration in clips.items()))


# A 3-Joint strip for the engine's loader and sampler tests. It is written by
# hand, not exported, so the tests can assert exact values. Change a value
# here only together with the tests.
def write_skinned_fixture(path):
    buffer = bytearray()
    views = []
    accessors = []

    def add(fmt, rows, kind, component, target=None, bounds=False):
        while len(buffer) % 4:
            buffer.append(0)
        offset = len(buffer)
        for row in rows:
            buffer.extend(struct.pack("<" + fmt, *row))
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(buffer) - offset}
        if target is not None:
            view["target"] = target
        views.append(view)
        accessor = {"bufferView": len(views) - 1, "componentType": component, "count": len(rows), "type": kind}
        if bounds:
            accessor["min"] = [min(row[i] for row in rows) for i in range(len(rows[0]))]
            accessor["max"] = [max(row[i] for row in rows) for i in range(len(rows[0]))]
        accessors.append(accessor)
        return len(accessors) - 1

    f32, u8, u16 = 5126, 5121, 5123
    vertex, index = 34962, 34963
    half = math.sqrt(0.5)
    positions = [(-0.5, 0.0, 0.0), (0.5, 0.0, 0.0), (-0.5, 1.0, 0.0), (0.5, 1.0, 0.0), (-0.5, 2.0, 0.0), (0.5, 2.0, 0.0)]
    joints = [(0, 0, 0, 0)] * 2 + [(0, 1, 0, 0)] * 2 + [(2, 0, 0, 0)] * 2
    weights = [(1.0, 0.0, 0.0, 0.0)] * 2 + [(0.25, 0.75, 0.0, 0.0)] * 2 + [(1.0, 0.0, 0.0, 0.0)] * 2
    triangles = [(0, 1, 3), (0, 3, 2), (2, 3, 5), (2, 5, 4)]
    inverse_binds = [Matrix.Translation((0.0, y, 0.0)) for y in (0.0, -1.0, -2.0)]

    position = add("3f", positions, "VEC3", f32, vertex, bounds=True)
    normal = add("3f", [(0.0, 0.0, 1.0)] * 6, "VEC3", f32, vertex)
    joint = add("4B", joints, "VEC4", u8, vertex)
    weight = add("4f", weights, "VEC4", f32, vertex)
    indices = add("H", [(i,) for t in triangles for i in t], "SCALAR", u16, index)
    inverse_bind = add("16f", [[m[r][c] for c in range(4) for r in range(4)] for m in inverse_binds], "MAT4", f32)
    turn_times = add("f", [(0.0,), (0.5,), (1.0,)], "SCALAR", f32, bounds=True)
    turns = add("4f", [(0.0, 0.0, 0.0, 1.0), (0.0, 0.0, half, half), (0.0, 0.0, 0.0, 1.0)], "VEC4", f32)
    stretch_times = add("f", [(0.0,), (0.25,), (0.75,)], "SCALAR", f32, bounds=True)
    stretches = add("3f", [(0.0, 1.0, 0.0), (0.0, 1.5, 0.0), (0.0, 1.0, 0.0)], "VEC3", f32)

    gltf = {
        "asset": {"version": "2.0", "generator": "rocco make_meshes.py"},
        "scene": 0,
        "scenes": [{"nodes": [0, 1]}],
        "nodes": [
            {"name": "strip", "mesh": 0, "skin": 0},
            {"name": "root", "children": [2]},
            {"name": "mid", "translation": [0.0, 1.0, 0.0], "children": [3]},
            {"name": "tip", "translation": [0.0, 1.0, 0.0]},
        ],
        "meshes": [
            {
                "name": "strip",
                "primitives": [
                    {"attributes": {"POSITION": position, "NORMAL": normal, "JOINTS_0": joint, "WEIGHTS_0": weight}, "indices": indices},
                ],
            }
        ],
        "skins": [{"name": "strip", "inverseBindMatrices": inverse_bind, "joints": [1, 2, 3]}],
        "animations": [
            {
                "name": "Bend",
                "samplers": [
                    {"input": turn_times, "output": turns, "interpolation": "LINEAR"},
                    {"input": stretch_times, "output": stretches, "interpolation": "STEP"},
                ],
                "channels": [
                    {"sampler": 0, "target": {"node": 2, "path": "rotation"}},
                    {"sampler": 1, "target": {"node": 3, "path": "translation"}},
                ],
            }
        ],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buffer)}],
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    while len(buffer) % 4:
        buffer.append(0)
    total = 12 + 8 + len(text) + 8 + len(buffer)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(buffer), 0x004E4942) + bytes(buffer))


pip, rig = make_scene()
for chapter in CHAPTERS:
    meshes = os.path.join(TUTORIAL, chapter, "assets", "meshes")
    os.makedirs(meshes, exist_ok=True)
    out = os.path.join(meshes, "pip.glb")
    export([rig, pip], out)
check(out)
write_skinned_fixture(os.path.normpath(FIXTURE))

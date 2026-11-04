# Builds salvage.glb and a double-sided glass tube into the glow example's
# assets. Run from the repository root with Blender 5.2:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python examples/glow/source/make_meshes.py
#
# Blender is +Z up and the export turns that into glTF +Y up. Blender -Y
# becomes glTF +Z, so the front of the block faces Blender -Y.

import json
import math
import os
import struct

import bmesh
import bpy
from mathutils import Matrix, Vector

GLOW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MESHES = os.path.join(GLOW, "assets", "meshes")
SALVAGE_OUT = os.path.join(MESHES, "salvage.glb")
TUBE_OUT = os.path.join(MESHES, "tube.glb")

# Linear colours. The ceramic and the rust multiply the same grime texture.
CERAMIC = (0.8, 0.78, 0.72, 1.0)
RUST = (0.5, 0.17, 0.05, 1.0)
NEON_BASE = (0.02, 0.02, 0.02, 1.0)
NEON = (0.1, 1.0, 0.75, 1.0)
NEON_STRENGTH = 4.0

GRIME_SIZE = 64
SEAM = 16

SEGMENTS = 24
GLASS = (0.38, 0.83, 0.96, 0.28)
TUBE_RADIUS = 0.42
TUBE_LENGTH = 1.6


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# A light grey with dark seams every SEAM pixels and a fixed speckle, so the
# committed file is the same from run to run.
def grime_image():
    image = bpy.data.images.new("grime", GRIME_SIZE, GRIME_SIZE)
    pixels = []
    for y in range(GRIME_SIZE):
        for x in range(GRIME_SIZE):
            speck = ((x * 73856093) ^ (y * 19349663)) % 97 / 97.0
            value = 0.45 if x % SEAM == 0 or y % SEAM == 0 else 0.92 - 0.2 * speck
            pixels += [value, value, value, 1.0]
    image.pixels = pixels
    image.file_format = "PNG"
    image.pack()
    return image


def material(name, roughness, metallic):
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat, bsdf


def socket(sockets, name, kind):
    return next(s for s in sockets if s.name == name and s.type == kind)


# The export writes the texture as baseColorTexture and the colour as
# baseColorFactor only for this shape: Image Texture into a Multiply Mix.
def textured(name, image, colour, roughness, metallic):
    mat, bsdf = material(name, roughness, metallic)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    socket(mix.inputs, "Factor", "VALUE").default_value = 1.0
    socket(mix.inputs, "B", "RGBA").default_value = colour
    links.new(texture.outputs["Color"], socket(mix.inputs, "A", "RGBA"))
    links.new(socket(mix.outputs, "Result", "RGBA"), bsdf.inputs["Base Color"])
    return mat


def emissive(name, base, colour, strength):
    mat, bsdf = material(name, 0.5, 0.0)
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Emission Color"].default_value = colour
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def placed(centre, size):
    return Matrix.Translation(Vector(centre)) @ Matrix.Diagonal(Vector((*size, 1.0)))


def paint(faces, index, smooth):
    for f in faces:
        f.material_index = index
        f.smooth = smooth


def faces_of(verts):
    return list(dict.fromkeys(f for v in verts for f in v.link_faces))


# The flat sides stay flat shaded and only the bevels are smooth.
def rounded_box(bm, index, centre, half, bevel):
    made = bmesh.ops.create_cube(bm, size=2.0, matrix=placed(centre, half), calc_uvs=True)
    verts = made["verts"]
    paint(faces_of(verts), index, False)
    edges = list(dict.fromkeys(e for v in verts for e in v.link_edges))
    rounded = bmesh.ops.bevel(bm, geom=verts + edges, offset=bevel, segments=3, profile=0.5, affect="EDGES")
    paint(rounded["faces"], index, True)


# A tube along Blender X.
def tube(bm, index, centre, radius, length):
    matrix = Matrix.Translation(Vector(centre)) @ Matrix.Rotation(math.pi / 2.0, 4, "Y")
    made = bmesh.ops.create_cone(bm, cap_ends=True, segments=SEGMENTS, radius1=radius, radius2=radius, depth=length, matrix=matrix, calc_uvs=True)
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


# A ceramic body under a rusted lid, with rusted ribs at the sides and a neon
# tubes across the front. It stands on z 0.
def make_block(materials):
    ceramic, rust, neon = range(len(materials))
    bm = bmesh.new()
    bm.loops.layers.uv.verify()

    rounded_box(bm, ceramic, (0.0, 0.0, 0.3), (0.35, 0.3, 0.3), 0.04)
    rounded_box(bm, rust, (0.0, 0.0, 0.64), (0.4, 0.35, 0.05), 0.02)
    for side in (-1.0, 1.0):
        rounded_box(bm, rust, (side * 0.37, 0.0, 0.3), (0.04, 0.33, 0.28), 0.015)
    tube(bm, neon, (0.0, -0.31, 0.42), 0.03, 0.5)
    tube(bm, neon, (0.0, -0.31, 0.22), 0.03, 0.5)

    sort_elements(bm)
    mesh = bpy.data.meshes.new("salvage")
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new("salvage", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def make_scene():
    clear_scene()
    grime = grime_image()
    materials = [
        textured("ceramic", grime, CERAMIC, 0.9, 0.0),
        textured("rust", grime, RUST, 0.45, 1.0),
        emissive("neon", NEON_BASE, NEON, NEON_STRENGTH),
    ]
    return make_block(materials)


def make_glass_tube():
    clear_scene()
    glass, bsdf = material("glass", 0.15, 0.0)
    glass.use_backface_culling = False
    bsdf.inputs["Base Color"].default_value = GLASS
    bsdf.inputs["Alpha"].default_value = GLASS[3]

    bm = bmesh.new()
    made = bmesh.ops.create_cone(bm, cap_ends=False, segments=SEGMENTS, radius1=TUBE_RADIUS, radius2=TUBE_RADIUS, depth=TUBE_LENGTH, matrix=Matrix.Rotation(math.pi / 2.0, 4, "Y"), calc_uvs=True)
    paint(faces_of(made["verts"]), 0, True)
    sort_elements(bm)
    mesh = bpy.data.meshes.new("tube")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(glass)
    obj = bpy.data.objects.new("tube", mesh)
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
        export_texcoords=True,
        export_animations=False,
        export_image_format="AUTO",
    )


def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, "the first chunk is not JSON"
    return json.loads(data[20 : 20 + length])


# Reads the JSON chunk back, so a change to the export or the node setup that
# drops a texture, a factor or the emissive strength fails the run.
def check_salvage(path):
    gltf = glb_json(path)
    materials = {m["name"]: m for m in gltf["materials"]}
    assert sorted(materials) == ["ceramic", "neon", "rust"], f"materials {sorted(materials)}"
    ceramic = materials["ceramic"]["pbrMetallicRoughness"]
    rust = materials["rust"]["pbrMetallicRoughness"]
    neon = materials["neon"]
    # The export writes one glTF texture per material, and the host decodes
    # textures with the same image and sampler once.
    textures = [gltf["textures"][m["baseColorTexture"]["index"]] for m in (ceramic, rust)]
    assert textures[0] == textures[1], f"the ceramic and the rust do not share the texture: {textures}"
    assert len(gltf["images"]) == 1, f"{len(gltf['images'])} images"
    assert ceramic["baseColorFactor"] != rust["baseColorFactor"], "the ceramic and the rust have the same base colour factor"
    assert rust.get("metallicFactor", 1.0) == 1.0 and ceramic.get("metallicFactor") == 0.0, "metallic factors"
    assert "baseColorTexture" not in neon.get("pbrMetallicRoughness", {}), "the neon has a texture"
    assert neon["extensions"]["KHR_materials_emissive_strength"]["emissiveStrength"] == NEON_STRENGTH, "no emissive strength"
    primitives = gltf["meshes"][0]["primitives"]
    print(f"salvage.glb: {len(primitives)} primitives, materials " + ", ".join(sorted(materials)))


def check_tube(path):
    gltf = glb_json(path)
    material = gltf["materials"][0]
    assert material["alphaMode"] == "BLEND", f"tube alphaMode: {material.get('alphaMode')}"
    assert material["doubleSided"] is True, f"tube doubleSided: {material.get('doubleSided')}"
    assert 0.0 < material["pbrMetallicRoughness"]["baseColorFactor"][3] < 1.0, "tube Alpha is not between 0 and 1"
    assert len(gltf["meshes"][0]["primitives"]) == 1, "tube has more than one part"
    print("tube.glb: double-sided Blend part")


os.makedirs(MESHES, exist_ok=True)
export(make_scene(), os.path.normpath(SALVAGE_OUT))
check_salvage(os.path.normpath(SALVAGE_OUT))
export(make_glass_tube(), os.path.normpath(TUBE_OUT))
check_tube(os.path.normpath(TUBE_OUT))

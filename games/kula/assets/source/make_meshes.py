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

# The engine multiplies the face texture by the draw's tint, so the centre
# matches the primitive plane's linear grey of 0.8 and the border reads lighter
# under any tint. Image pixels are sRGB: 0.906 is linear 0.8.
FACE_CENTRE = (0.906, 0.906, 0.906, 1.0)
FACE_BORDER = (1.0, 1.0, 1.0, 1.0)
FACE_TEXTURE_SIZE = 64
FACE_BORDER_TEXELS = 4

# Low enough that the sun leaves a small, sharp highlight on the ball.
BALL_ROUGHNESS = 0.2
BALL_WHITE = (0.9, 0.9, 0.9, 1.0)
BALL_RED = (0.8, 0.05, 0.03, 1.0)
BALL_SEGMENTS = 32
BALL_RINGS = 16
BALL_WEDGES = 8


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# The export writes metallicFactor 0 and the roughness as roughnessFactor.
def material(name, colour, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


# The export writes the image as a PNG in the .glb. Linear interpolation
# exports as a mipmapped minification filter.
def texture_material(name, image):
    mat = material(name, (1.0, 1.0, 1.0, 1.0))
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    mat.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def face_image():
    size = FACE_TEXTURE_SIZE
    image = bpy.data.images.new("face", size, size, alpha=False)
    pixels = []
    for y in range(size):
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            pixels.extend(FACE_BORDER if edge < FACE_BORDER_TEXELS else FACE_CENTRE)
    image.pixels = pixels
    image.file_format = "PNG"
    return image


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
        export_texcoords=True,
        export_image_format="AUTO",
        export_animations=False,
    )


# A 1 x 1 quad centred on the origin that winds counter-clockwise seen from
# +Z. Its uvs span the whole bordered texture.
def make_face():
    clear_scene()
    half = 0.5
    verts = [(-half, -half, 0.0), (half, -half, 0.0), (half, half, 0.0), (-half, half, 0.0)]
    mesh = bpy.data.meshes.new("face")
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    uvs = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        x, y, _ = verts[loop.vertex_index]
        uvs.data[loop.index].uv = (x + half, y + half)
    mesh.materials.append(texture_material("face", face_image()))
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
    mesh.materials.append(material("ball_white", BALL_WHITE, BALL_ROUGHNESS))
    mesh.materials.append(material("ball_red", BALL_RED, BALL_ROUGHNESS))
    export(new_object("ball", mesh), "ball.glb")


os.makedirs(MESHES, exist_ok=True)
make_face()
make_ball()

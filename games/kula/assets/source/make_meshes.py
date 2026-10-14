# Builds each Theme's <theme>_face.glb and ball.glb for Kula. Run from any directory:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python games/kula/assets/source/make_meshes.py
#
# Blender is +Z up. The glTF export turns that into +Y up, so a quad facing
# Blender +Z faces glTF +Y, like the engine's primitive plane.

import math
import os
import random

import bmesh
import bpy

MESHES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "meshes")

# Kula draws faces with a white tint, so each texture carries its Theme's
# colour. The exit's red tint multiplies it.
FACE_TEXTURE_SIZE = 64

# Low enough that the sun leaves a soft highlight on the ball.
BALL_ROUGHNESS = 0.4
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


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def scaled(colour, s):
    return tuple(c * s for c in colour)


# Each pattern takes the texel's distance from the nearest edge, its offset
# from the centre and a noise value near 1, and gives a linear colour.
def haze_texel(edge, dx, dy, noise):
    if edge < 4:
        return scaled((0.6, 0.63, 0.7), noise)
    return scaled((0.42, 0.45, 0.52), noise)


# A groove, a raised rim and a stepped diamond, like carved sandstone.
def inca_texel(edge, dx, dy, noise):
    if edge < 3:
        return scaled((0.3, 0.18, 0.08), noise)
    if edge < 6:
        return scaled((0.68, 0.47, 0.24), noise)
    step = int((abs(dx) + abs(dy)) / 5)
    shade = 0.55 if step % 2 == 0 else 0.47
    return scaled((shade, shade * 0.66, shade * 0.31), noise)


# Bright bevelled edges and faint diagonal frost lines.
def arctic_texel(edge, dx, dy, noise):
    if edge < 3:
        return scaled((0.9, 0.95, 1.0), noise)
    if int(dx + dy) % 16 == 0:
        return scaled((0.75, 0.86, 0.96), noise)
    return scaled((0.62, 0.75, 0.88), noise)


# Pack name, texel pattern and noise strength. The names match Theme.roc.
THEMES = [
    ("haze", haze_texel, 0.04),
    ("inca", inca_texel, 0.06),
    ("arctic", arctic_texel, 0.03),
]


# Blender stores byte image pixels as sRGB, so the linear colours convert here.
# A fixed seed keeps the committed files stable.
def face_image(name, texel, noise_amount):
    size = FACE_TEXTURE_SIZE
    rng = random.Random(name)
    image = bpy.data.images.new(name + "_face", size, size, alpha=False)
    pixels = []
    centre = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            noise = 1.0 + rng.uniform(-noise_amount, noise_amount)
            colour = texel(edge, x - centre, y - centre, noise)
            pixels.extend([linear_to_srgb(c) for c in colour] + [1.0])
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
# +Z. Its uvs span the whole texture.
def make_face(name, texel, noise_amount):
    clear_scene()
    half = 0.5
    verts = [(-half, -half, 0.0), (half, -half, 0.0), (half, half, 0.0), (-half, half, 0.0)]
    mesh = bpy.data.meshes.new("face")
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    uvs = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        x, y, _ = verts[loop.vertex_index]
        uvs.data[loop.index].uv = (x + half, y + half)
    mesh.materials.append(texture_material(name + "_face", face_image(name, texel, noise_amount)))
    mesh.update()
    export(new_object(name + "_face", mesh), name + "_face.glb")


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
for theme in THEMES:
    make_face(*theme)
make_ball()

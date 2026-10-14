# Renders each Theme's sky for Kula: six PNGs in assets/sky/<theme>/. Run from any directory:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python games/kula/assets/source/make_skies.py
#
# A Blender sky texture lights an empty world. One 90 degree camera renders
# each cube face. The face layout is the one engine/sky.odin states: face px
# holds the directions nearest +x, with its top row towards +y and its left
# column towards +z.

import math
import os

import bpy
import numpy
from mathutils import Matrix, Vector

SKY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sky")
SIDE = 256

# u and v run from -1 at the left and top to 1 at the right and bottom.
FACES = {
    "px": lambda u, v: (1.0, -v, -u),
    "nx": lambda u, v: (-1.0, -v, u),
    "py": lambda u, v: (u, 1.0, v),
    "ny": lambda u, v: (u, -1.0, -v),
    "pz": lambda u, v: (u, -v, 1.0),
    "nz": lambda u, v: (-u, -v, -1.0),
}


# Each light is the sun's dir in Theme.roc. The painted sun sits where the
# light comes from. tint colours the sky, and ground is the linear colour below
# the horizon.
THEMES = [
    {
        "name": "haze",
        "light": (-2.0 / 7.0, -6.0 / 7.0, -3.0 / 7.0),
        "air": 1.0,
        "aerosol": 4.0,
        "ozone": 1.0,
        "tint": (0.9, 0.9, 0.95),
        "ground": (0.2, 0.2, 0.22),
    },
    {
        "name": "inca",
        "light": (3.0 / 7.0, -6.0 / 7.0, -2.0 / 7.0),
        "air": 0.4,
        "aerosol": 8.0,
        "ozone": 0.0,
        "tint": (1.0, 0.62, 0.32),
        "ground": (0.25, 0.14, 0.06),
    },
    {
        "name": "arctic",
        "light": (-3.0 / 7.0, -6.0 / 7.0, 2.0 / 7.0),
        "air": 1.0,
        "aerosol": 0.5,
        "ozone": 2.0,
        "tint": (0.85, 0.95, 1.0),
        "ground": (0.35, 0.42, 0.5),
    },
]

# Scales the sky texture's radiance into display range.
BRIGHTNESS = 0.05

# EEVEE draws no sky texture sun disc, so the world paints its own. It is
# wider than the real sun, so it reads at 256 texels a face.
SUN_RADIUS = math.radians(2.0)
SUN_EDGE = math.radians(0.5)
SUN_COLOUR = (4.0, 3.8, 3.4)


# Engine directions are +y up. Blender is +z up.
def to_blender(d):
    return Vector((d[0], -d[2], d[1]))


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world(theme):
    w = bpy.data.worlds.new(theme["name"])
    w.use_nodes = True
    nodes = w.node_tree.nodes
    links = w.node_tree.links
    nodes.clear()

    sun = -to_blender(theme["light"]).normalized()
    sky = nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = False
    sky.sun_elevation = math.asin(sun.z)
    sky.sun_rotation = math.atan2(sun.x, sun.y)
    sky.air_density = theme["air"]
    sky.aerosol_density = theme["aerosol"]
    sky.ozone_density = theme["ozone"]

    tint = nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 1.0
    links.new(sky.outputs["Color"], tint.inputs["A"])
    tint.inputs["B"].default_value = (*(c * BRIGHTNESS for c in theme["tint"]), 1.0)

    coord = nodes.new("ShaderNodeTexCoord")
    view = nodes.new("ShaderNodeVectorMath")
    view.operation = "NORMALIZE"
    links.new(coord.outputs["Generated"], view.inputs[0])

    facing = nodes.new("ShaderNodeVectorMath")
    facing.operation = "DOT_PRODUCT"
    links.new(view.outputs["Vector"], facing.inputs[0])
    facing.inputs[1].default_value = sun
    disc = nodes.new("ShaderNodeMapRange")
    disc.inputs["From Min"].default_value = math.cos(SUN_RADIUS + SUN_EDGE)
    disc.inputs["From Max"].default_value = math.cos(SUN_RADIUS)
    links.new(facing.outputs["Value"], disc.inputs["Value"])
    painted = nodes.new("ShaderNodeMix")
    painted.data_type = "RGBA"
    links.new(disc.outputs["Result"], painted.inputs["Factor"])
    links.new(tint.outputs["Result"], painted.inputs["A"])
    painted.inputs["B"].default_value = (*SUN_COLOUR, 1.0)

    # Below the horizon the sky fades to the ground colour over a few degrees.
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(view.outputs["Vector"], xyz.inputs["Vector"])
    below = nodes.new("ShaderNodeMapRange")
    below.inputs["From Min"].default_value = 0.0
    below.inputs["From Max"].default_value = -0.05
    links.new(xyz.outputs["Z"], below.inputs["Value"])

    ground = nodes.new("ShaderNodeMix")
    ground.data_type = "RGBA"
    links.new(below.outputs["Result"], ground.inputs["Factor"])
    links.new(painted.outputs["Result"], ground.inputs["A"])
    ground.inputs["B"].default_value = (*theme["ground"], 1.0)

    background = nodes.new("ShaderNodeBackground")
    links.new(ground.outputs["Result"], background.inputs["Color"])
    out = nodes.new("ShaderNodeOutputWorld")
    links.new(background.outputs["Background"], out.inputs["Surface"])
    return w


# A cube face is a mirror image of a camera view, so the camera's +x points
# to the face's left and mirror() flips the render. The camera looks down its
# -z with +y up.
def face_rotation(direction):
    forward = Vector(direction(0.0, 0.0))
    left = forward - Vector(direction(1.0, 0.0))
    up = forward - Vector(direction(0.0, 1.0))
    columns = [to_blender(left), to_blender(up), -to_blender(forward)]
    return Matrix([[c[i] for c in columns] for i in range(3)]).to_quaternion()


# A new image carries no render stamp, so a rerun writes the same bytes.
def mirror(path):
    render = bpy.data.images.load(path)
    pixels = numpy.array(render.pixels[:]).reshape(SIDE, SIDE, 4)
    bpy.data.images.remove(render)
    image = bpy.data.images.new("face", SIDE, SIDE, alpha=False)
    image.pixels = pixels[:, ::-1].ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def render_theme(theme):
    clear_scene()
    scene = bpy.context.scene
    scene.world = world(theme)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = SIDE
    scene.render.resolution_y = SIDE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"

    cam_data = bpy.data.cameras.new("cube")
    cam_data.angle = math.pi / 2
    cam = bpy.data.objects.new("cube", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.rotation_mode = "QUATERNION"

    out = os.path.join(SKY, theme["name"])
    os.makedirs(out, exist_ok=True)
    for name, direction in FACES.items():
        cam.rotation_quaternion = face_rotation(direction)
        path = os.path.join(out, name + ".png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        mirror(path)


for theme in THEMES:
    render_theme(theme)

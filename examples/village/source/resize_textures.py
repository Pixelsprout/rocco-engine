"""Run inside Blender to prepare bounded PNGs without colour-space conversion."""
import json
from pathlib import Path
import sys
import bpy
args = sys.argv[sys.argv.index('--') + 1:]
maximum = int(args[1])
for filename in json.loads(Path(args[0]).read_text()):
    image = bpy.data.images.load(filename, check_existing=False)
    width, height = image.size
    if max(width, height) > maximum:
        image.colorspace_settings.name = 'Non-Color'
        image.scale(round(width * maximum / max(width, height)), round(height * maximum / max(width, height)))
        image.file_format = 'PNG'
        image.filepath_raw = filename
        image.save()
    bpy.data.images.remove(image)

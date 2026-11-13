"""Compose engine entry points and map diagnostics back to hook sources."""
from pathlib import Path
import re
from declarations import BuildError

DEFAULTS = {
    "vertex": "void rocco_vertex(inout Vertex vertex) {}",
    "surface": "void rocco_surface(inout Surface surface, SurfaceInput data) {}",
    "lighting": "vec3 rocco_lighting(Lighting data) { return (data.diffuse + data.specular) * data.radiance * (clamp(dot(data.normal, data.direction), 0.0, 1.0) * data.attenuation); }",
}
# The depth inputs are R32F, which WebGPU cannot filter. The engine samples
# every Post input with a nearest sampler, so no backend loses a filter.
UNFILTERABLE_INPUTS = ("scene_depth", "selection_depth")
POST_VERTEX = '''out vec2 v_uv;
void main() {
    vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
#if SOKOL_GLSL
    v_uv = p;
#else
    v_uv = vec2(p.x, 1.0 - p.y);
#endif
}'''

class Composer:
    def __init__(self, declaration, document, contract_dir):
        self.declaration = declaration
        self.document = document
        self.contract_dir = Path(contract_dir)
        self.lines = []
        self.locations = {}
        self.dependencies = set()

    def append(self, source, path=None):
        for number, line in enumerate(source.splitlines(), 1):
            self.lines.append(line)
            if path is not None:
                self.locations[len(self.lines)] = (str(path), number)

    def hook(self, name):
        if name not in self.declaration:
            self.append(DEFAULTS[name])
            return
        path = (self.document.path.parent / self.declaration[name]).resolve()
        source = path.read_text(encoding="utf-8")
        self.dependencies.add(path)
        if "\x00" in source or len(source.encode()) > 256 * 1024:
            raise BuildError(f"{path}:1:1: invalid hook size or embedded NUL")
        clean = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: "\n" * m[0].count("\n"), source, flags=re.S)
        forbidden = re.search(r"\b(uniform|buffer|layout|attribute|varying|main|discard|gl_FragDepth)\b|@|^\s*#\s*(?!if\b|ifdef\b|ifndef\b|elif\b|else\b|endif\b)\w+", clean, re.M)
        braces = parentheses = 0
        for token in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*|[{}()]", clean):
            value = token[0]
            if value in ("in", "out") and braces == 0 and parentheses == 0:
                forbidden = token
                break
            braces += (value == "{") - (value == "}")
            parentheses += (value == "(") - (value == ")")
        if forbidden:
            line = clean.count("\n", 0, forbidden.start()) + 1
            raise BuildError(f"{path}:{line}:1: hooks cannot declare resources, shader inputs/outputs, entry points, includes, macros, or fragment depth/coverage")
        self.append(source, path)

    def template(self, name, replacements, hooks):
        path = self.contract_dir / name
        self.dependencies.add(path)
        for number, line in enumerate(path.read_text().splitlines(), 1):
            token = line.strip()
            if token in hooks:
                self.hook(hooks[token])
            elif token in replacements:
                self.append(replacements[token])
            else:
                self.lines.append(line)
                self.locations[len(self.lines)] = (str(path), number)

    def game_resources(self, stage):
        params = [p for p in self.declaration["parameters"] if p["stage"] == stage]
        slot = 4 if stage == "vertex" else 5
        if params:
            self.append(f"layout(binding={slot}) uniform game_{stage} {{ vec4 {stage}_values[16]; }};")
        for p in params:
            lane = p["offset"] // 16
            value = f"{stage}_values[{lane}]"
            kind = p["type"]
            if kind == "Mat4":
                value = "mat4(" + ", ".join(f"{stage}_values[{lane + i}]" for i in range(4)) + ")"
            elif kind == "Bool":
                value += ".x != 0.0"
            elif kind == "F32":
                value += ".x"
            elif kind in ("Vec2", "Vec3"):
                value += "." + ("xy" if kind == "Vec2" else "xyz")
            gltype = {"F32": "float", "Bool": "bool", "Mat4": "mat4", "Vec2": "vec2", "Vec3": "vec3", "Vec4": "vec4", "Colour": "vec4"}[kind]
            self.append(f"{gltype} param_{p['name']}() {{ return {value}; }}")
        for t in self.declaration["textures"]:
            if t["stage"] != stage:
                continue
            name, binding = t["name"], t["view"]
            dimension = "2D" if t["type"] == "2d" else "Cube"
            coord = "vec2" if t["type"] == "2d" else "vec3"
            self.append(f"layout(binding={binding}) uniform texture{dimension} game_{name}_tex;\nlayout(binding={binding}) uniform sampler game_{name}_smp;")
            self.append(f"vec4 sample_{name}({coord} uv) {{ return textureLod(sampler{dimension}(game_{name}_tex, game_{name}_smp), uv, 0.0); }}")
            self.append(f"vec4 sample_{name}_lod({coord} uv, float lod) {{ return textureLod(sampler{dimension}(game_{name}_tex, game_{name}_smp), uv, lod); }}")

    def surface(self):
        layouts = ["surface", "skinned"] if self.declaration.get("skinning", True) else ["surface"]
        if self.declaration.get("instancing", True):
            layouts.append("instanced")
        for layout in layouts:
            self.append(f"@vs {layout}_vs\n@glsl_options fixup_clipspace")
            self.game_resources("vertex")
            skin = ""
            pose = "vertex.position = position; vertex.normal = normal; vertex.tangent = tangent;"
            if layout == "skinned":
                skin = "layout(binding=3) uniform engine_skin { mat4 joints[64]; };\nin uvec4 joint_ids;\nin vec4 joint_weights;"
                pose = "mat4 skin = joints[joint_ids.x] * joint_weights.x + joints[joint_ids.y] * joint_weights.y + joints[joint_ids.z] * joint_weights.z + joints[joint_ids.w] * joint_weights.w;\nvertex.position = (skin * vec4(position, 1.0)).xyz; vertex.normal = (skin * vec4(normal, 0.0)).xyz; vertex.tangent = vec4((skin * vec4(tangent.xyz, 0.0)).xyz, tangent.w);"
            instance_inputs = ""
            transforms = "mat4 world_model = model; mat4 world_normal = normal_model;"
            clip = "gl_Position = mvp * vec4(vertex.position, 1.0);"
            instance_tint = "v_instance_tint = vec4(1.0);"
            if layout == "instanced":
                instance_inputs = "\n".join(f"in vec4 instance_model_{i};" for i in range(4)) + "\n" + "\n".join(f"in vec3 instance_normal_{i};" for i in range(3)) + "\nin vec4 instance_tint;"
                transforms = "mat4 world_model = mat4(instance_model_0, instance_model_1, instance_model_2, instance_model_3); mat4 world_normal = mat4(vec4(instance_normal_0, 0.0), vec4(instance_normal_1, 0.0), vec4(instance_normal_2, 0.0), vec4(0.0, 0.0, 0.0, 1.0));"
                clip = "gl_Position = mvp * world_model * vec4(vertex.position, 1.0);"
                instance_tint = "v_instance_tint = instance_tint;"
            self.template("vertex.glsl", {"@@SKIN_INPUTS@@": skin, "@@POSE@@": pose, "@@INSTANCE_INPUTS@@": instance_inputs, "@@TRANSFORMS@@": transforms, "@@CLIP@@": clip, "@@INSTANCE_TINT@@": instance_tint}, {"@@VERTEX_HOOK@@": "vertex"})
            self.append("@end")
        for render_pass in ("colour", "shadow", "selection"):
            self.append(f"@fs {render_pass}_fs")
            self.game_resources("fragment")
            self.template("surface.glsl", {}, {"@@SURFACE_HOOK@@": "surface", "@@LIGHTING_HOOK@@": "lighting"})
            if render_pass == "colour":
                self.append("out vec4 frag_colour;\nvoid main() {\nvec4 c = surface_color(maps.z == 2.0);\nif (maps.z == 1.0 && c.a < material.w) { discard; }\nfrag_colour = c;\n}")
            elif render_pass == "shadow":
                self.append("void main() { float a = surface_coverage(); if (maps.z == 1.0 && a < material.w) { discard; } }")
            else:
                self.append("layout(location=0) out float selected_coverage;\nlayout(location=1) out float selected_depth;\nvoid main() { float a = surface_coverage(); if (maps.z == 1.0 && a < material.w) { discard; } selected_coverage = 1.0; selected_depth = gl_FragCoord.z; }")
            self.append("@end")
        for layout in layouts:
            for render_pass in ("colour", "shadow", "selection"):
                self.append(f"@program {layout}_{render_pass} {layout}_vs {render_pass}_fs")

    def post(self):
        self.append("@vs post_vs")
        self.append(POST_VERTEX)
        self.append("@end\n@fs post_fs")
        self.game_resources("fragment")
        inputs = ("scene_colour", "scene_depth", "selection_coverage", "selection_depth")
        for name in self.declaration["inputs"]:
            slot = inputs.index(name)
            if name in UNFILTERABLE_INPUTS:
                self.append(f"@image_sample_type {name} unfilterable_float\n@sampler_type {name}_smp nonfiltering")
            self.append(f"layout(binding={slot}) uniform texture2D {name};\nlayout(binding={slot}) uniform sampler {name}_smp;\nvec4 sample_{name}(vec2 uv) {{ return texture(sampler2D({name}, {name}_smp), uv); }}")
        self.template("post.glsl", {}, {"@@POST_HOOK@@": "post"})
        self.append("@end")
        for location in self.declaration["locations"]:
            program = "post_hdr" if location == "before_bloom" else "post_ldr"
            self.append(f"@program {program} post_vs post_fs")

    def compose(self):
        if self.declaration["kind"] == "surface":
            self.surface()
        else:
            self.post()
        return "\n".join(self.lines) + "\n"

    def diagnostic(self, output):
        def replace(match):
            line = int(match[1])
            if line in self.locations:
                path, source_line = self.locations[line]
                return f"{path}:{source_line}:"
            return match[0]
        return re.sub(r"(?:[^\n :]*[/\\])?input\.glsl:([0-9]+):", replace, output)

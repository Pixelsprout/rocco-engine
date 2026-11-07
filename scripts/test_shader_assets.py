"""Independent published-tool tests. Set ROCCO_SHDC to the pinned compiler."""
import copy
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "platform/shader-tools"
sys.path.insert(0, str(TOOLS))
from declarations import BuildError, Document, encode_parameter, validate
from helpers import mesh_materials
from build import write_changed
from package import HEADER, canonical, digest, fingerprint, parse_reflection, validate_reflection

EXAMPLE = ROOT / "scripts/shader_assets/example"
SHDC = os.environ.get("ROCCO_SHDC") or shutil.which("sokol-shdc")
ROC = shutil.which("roc")


def target_input_filenames(source):
    return {filename for inputs in re.findall(r"inputs:\s*\[([^]]*)\]", source)
            for filename in re.findall(r'"([^"/]+)"', inputs)}


class OutputTests(unittest.TestCase):
    def test_target_inputs_include_every_versioned_shared_library(self):
        source = 'targets: { a: { inputs: ["lib.a", "start.o", app] }, b: { inputs: ["libXcursor.so.1", "libc.so.6", "libextra.so.42", "host.lib", app] } }'
        self.assertEqual(target_input_filenames(source), {"lib.a", "start.o", "libXcursor.so.1", "libc.so.6", "libextra.so.42", "host.lib"})
        self.assertIn("libXcursor.so.1", target_input_filenames((ROOT / "platform/main.roc").read_text()))

    @unittest.skipIf(os.name == "nt", "POSIX permissions")
    def test_atomic_outputs_are_readable_with_a_restrictive_umask(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "generated.shaderpack"
            mask = os.umask(0o077)
            try:
                write_changed(path, b"first")
                self.assertEqual(path.stat().st_mode & 0o777, 0o644)
                before = path.stat().st_mtime_ns
                path.chmod(0o600)
                write_changed(path, b"first")
                self.assertEqual(path.stat().st_mtime_ns, before)
                self.assertEqual(path.stat().st_mode & 0o777, 0o644)
                with mock.patch("build.os.replace", side_effect=OSError("replacement failed")):
                    with self.assertRaises(OSError):
                        write_changed(path, b"second")
                self.assertEqual(path.read_bytes(), b"first")
                self.assertEqual(list(Path(directory).iterdir()), [path])
                write_changed(path, b"second")
                self.assertEqual(path.read_bytes(), b"second")
                self.assertEqual(path.stat().st_mode & 0o777, 0o644)
            finally:
                os.umask(mask)


def decode(path):
    data = path.read_bytes()
    magic, version, contract, size, metadata_size, payload_size, flags, mask, interface, checksum = HEADER.unpack_from(data)
    assert (magic, version, contract, size, flags, mask) == (b"RCSHADER", 1, 1, 96, 0, 7)
    assert len(data) == size + metadata_size + payload_size
    assert digest(data[size:]) == checksum
    manifest = json.loads(data[size:size + metadata_size])
    assert canonical(manifest) == data[size:size + metadata_size]
    assert fingerprint(manifest) == interface
    return manifest, data[size + metadata_size:]


class DeclarationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        shutil.copytree(EXAMPLE, self.game, dirs_exist_ok=True)
        self.source = json.loads((self.game / "shaders.json").read_text())

    def document(self, source=None):
        path = self.game / "shaders.json"
        path.write_text(json.dumps(self.source if source is None else source, indent=2))
        return Document(path)

    def test_offsets_follow_declaration_order_per_stage(self):
        shader = validate(self.document())["shaders"][0]
        self.assertEqual([p["offset"] for p in shader["parameters"]], [0, 0, 16])

    def test_source_location_for_wrong_default_and_duplicate_key(self):
        self.source["shaders"][0]["parameters"][0]["default"] = [True]
        with self.assertRaisesRegex(BuildError, r"shaders.json:[0-9]+:[0-9]+: /shaders/0/parameters/0/default:"):
            validate(self.document())
        (self.game / "shaders.json").write_text('{\n "contract": 1,\n "contract": 1, "shaders": []\n}')
        with self.assertRaisesRegex(BuildError, r"shaders.json:3:2:.*duplicate"):
            Document(self.game / "shaders.json")

    def test_invalid_declarations_fail_without_coercion(self):
        changes = [("type", "Int"), ("default", [float("nan")]), ("default", [float("inf")]),
                   ("default", [1e40]), ("default", []), ("name", "BadName"), ("stage", "compute"),
                   ("scope", "Global"), ("offset", 0)]
        for key, value in changes:
            source = copy.deepcopy(self.source)
            source["shaders"][0]["parameters"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(BuildError):
                validate(self.document(source))
        for displacement in (-1, float("inf"), True):
            source = copy.deepcopy(self.source)
            source["shaders"][0]["max_displacement"] = displacement
            with self.subTest(displacement=displacement), self.assertRaises(BuildError):
                validate(self.document(source))

    def test_stage_budget_and_post_scope(self):
        source = copy.deepcopy(self.source)
        source["shaders"][0]["parameters"] = [dict(name=f"value_{i}", type="Mat4", scope="Scene", stage="vertex", default=list(range(16))) for i in range(5)]
        with self.assertRaisesRegex(BuildError, "256-byte"):
            validate(self.document(source))
        source = copy.deepcopy(self.source)
        source["shaders"][1]["parameters"][0]["scope"] = "Material"
        with self.assertRaisesRegex(BuildError, "Post accepts"):
            validate(self.document(source))

    def test_texture_declarations_require_valid_defaults_and_policies(self):
        changes = [("default", None), ("default", {"pack": "", "asset": "x"}), ("default", {"imported": "normal"}),
                   ("optional", False), ("sampler_policy", {"min": "magic", "mag": "linear", "wrap": "repeat"}),
                   ("type", "storage"), ("colour_space", "unknown")]
        for key, value in changes:
            source = copy.deepcopy(self.source)
            source["shaders"][0]["textures"][0][key] = value
            with self.subTest(key=key), self.assertRaises(BuildError):
                validate(self.document(source))

    def test_parameter_encoding_matches_contract(self):
        self.assertEqual(encode_parameter("Vec3", [1, 2, 3]), struct.pack("<4f", 1, 2, 3, 0))
        self.assertEqual(encode_parameter("Bool", [False]), bytes(16))
        self.assertEqual(len(encode_parameter("Mat4", list(range(16)))), 64)
        with self.assertRaises(BuildError):
            encode_parameter("F32", [True])

    def test_named_slots_use_source_identity_and_reject_name_collisions(self):
        path = self.game / "tree.gltf"
        path.write_text(json.dumps({"materials": [{"name": "Bark"}, {}, {"name": "Leaves"}]}))
        self.assertEqual([m["source_material"] for m in mesh_materials(path)], [0, 2])
        for names in (["Leaf", "Leaf"], ["Leaf-A", "Leaf A"], ["123"], ["葉"]):
            path.write_text(json.dumps({"materials": [{"name": name} for name in names]}))
            with self.subTest(names=names), self.assertRaises(BuildError):
                mesh_materials(path)

    def test_reflection_parser_rejects_unrecognized_yaml(self):
        for source in ("key: &anchor\n", "key: [1,2]\n", "key: x\nkey: y\n", "key:\n", "shaders:\n   -\n     slang: x\n", "key: !execute\n"):
            with self.subTest(source=source), self.assertRaises(BuildError):
                parse_reflection(source)

@unittest.skipUnless(SHDC, "set ROCCO_SHDC to the pinned compiler")
class PublishedCompilerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="shader-external-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / "game"
        self.platform = self.root / "published-platform"
        shutil.copytree(EXAMPLE, self.game)
        shutil.copytree(TOOLS, self.platform / "shader-tools", ignore=shutil.ignore_patterns("__pycache__"))
        for path in (ROOT / "platform").glob("*.roc"):
            shutil.copy(path, self.platform)
        # Invalid Roc builds must reach type checking without requiring a runtime loader or native archive build.
        for target in ("arm64mac", "x64glibc", "x64win"):
            directory = self.platform / "targets" / target
            directory.mkdir(parents=True)
            for filename in target_input_filenames((self.platform / "main.roc").read_text()):
                (directory / filename).touch()
        self.out = self.game / "assets/shaders"
        self.command = [sys.executable, str(self.platform / "shader-tools/build.py"), "--shdc", str(Path(SHDC).resolve())]

    def run_build(self, success=True):
        result = subprocess.run(self.command, cwd=self.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_external_build_is_repeatable_and_has_all_resources_and_passes(self):
        self.run_build()
        manifest, payload = decode(self.out / "Foliage.shaderpack")
        self.assertEqual([s["slang"] for s in manifest["shaders"]], ["glsl430", "hlsl5", "metal_macos"])
        for backend in manifest["shaders"]:
            self.assertEqual(len(backend["programs"]), 9)
            for program in backend["programs"]:
                for function in (program["vertex_func"], program["fragment_func"]):
                    code = payload[function["offset"]:function["offset"] + function["size"]]
                    self.assertTrue(code and b"\0" not in code)
                    self.assertNotIn(str(self.root).encode(), code)
                sizes = {b["slot"]: b["size"] for b in program.get("uniform_blocks", [])}
                self.assertEqual(sizes[0], 256)
                self.assertEqual(sizes[1], 96)
                self.assertEqual(sizes[4], 256)
                if program["name"].startswith("instanced"):
                    self.assertEqual(len(program["attrs"]), 13)
                if program["name"].endswith("colour"):
                    self.assertEqual(sizes[2], 512)
                    storage = [v["storage_buffer"] for v in program["views"] if "storage_buffer" in v]
                    self.assertEqual([b["slot"] for b in storage], [12, 13, 14])
                    if backend["slang"] == "glsl430":
                        self.assertEqual([b["glsl_binding_n"] for b in storage], [0, 1, 2])
        post, _ = decode(self.out / "Outline.shaderpack")
        self.assertEqual([p["name"] for p in post["shaders"][0]["programs"]], ["post_hdr", "post_ldr"])
        files = {p.relative_to(self.game): p.read_bytes() for p in self.game.rglob("*") if p.is_file()}
        times = {p: (self.game / p).stat().st_mtime_ns for p in files}
        self.run_build()
        self.assertEqual(files, {p.relative_to(self.game): p.read_bytes() for p in self.game.rglob("*") if p.is_file()})
        self.assertEqual(times, {p: (self.game / p).stat().st_mtime_ns for p in files})
        other = self.root / "different-root"
        shutil.copytree(self.game, other)
        run = subprocess.run(self.command, cwd=other, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(run.returncode, 0, run.stdout)
        for name in ("Foliage.shaderpack", "Outline.shaderpack"):
            self.assertEqual((self.out / name).read_bytes(), (other / "assets/shaders" / name).read_bytes())

    def test_invalid_changed_glsl_fails_with_hook_location_and_preserves_assets(self):
        self.run_build()
        before = (self.out / "Foliage.shaderpack").read_bytes()
        path = self.game / "wind.glsl"
        path.write_text(path.read_text().replace("sin(vertex.time", "undefined_wind(vertex.time"))
        result = self.run_build(False)
        self.assertRegex(result.stdout, r"wind.glsl:3:[0-9]+:.*undefined_wind")
        self.assertEqual(before, (self.out / "Foliage.shaderpack").read_bytes())

    def test_unpinned_compiler_and_hook_resources_fail(self):
        fake = self.root / "fake-shdc"
        fake.write_text("not a pinned executable")
        result = subprocess.run(self.command[:-1] + [str(fake)], cwd=self.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum", result.stdout)
        for source in ("layout(binding=0) uniform stolen { vec4 values; };\n", "out vec4 injected;\n", "void rocco_vertex(inout Vertex vertex) { discard; }\n", "#define injected 1\n"):
            (self.game / "wind.glsl").write_text(source)
            result = self.run_build(False)
            self.assertIn("wind.glsl:1:1", result.stdout)
            self.assertIn("cannot declare resources", result.stdout)

    def test_world_inputs_use_resolved_models_in_shared_vertex_stages(self):
        (self.game / "wind.glsl").write_text('''void rocco_vertex(inout Vertex vertex) {
    vec3 world_offset = vec3(0.1, -0.2, 0.3) * sin(vertex.world_position.x + vertex.world_origin.z);
    vec3 local_offset = vertex.world_to_local_direction * world_offset;
    vertex.position += local_offset / max(1.0, length(local_offset) / 0.25);
}''')
        self.run_build()
        source = (self.out / "Foliage.sources/input.glsl").read_text()
        for layout in ("surface", "skinned", "instanced"):
            vertex = source.split(f"@vs {layout}_vs\n", 1)[1].split("@end", 1)[0]
            invoke = vertex.index("rocco_vertex(vertex);")
            self.assertLess(vertex.index("vertex.world_position = (world_model * vec4(vertex.position, 1.0)).xyz;"), invoke)
            self.assertLess(vertex.index("vertex.world_origin = world_model[3].xyz;"), invoke)
            self.assertLess(vertex.index("vertex.world_to_local_direction = transpose(mat3(world_normal));"), invoke)
            normal = "mat4 world_normal = mat4(vec4(instance_normal_0" if layout == "instanced" else "mat4 world_normal = normal_model;"
            self.assertIn(normal, vertex)
            model = "mat4 world_model = mat4(instance_model_0" if layout == "instanced" else "mat4 world_model = model;"
            self.assertIn(model, vertex)
        manifest, payload = decode(self.out / "Foliage.shaderpack")
        self.assertEqual(manifest["interface"]["surface"]["max_displacement"], 0.25)
        for backend in manifest["shaders"]:
            for layout in ("surface", "skinned", "instanced"):
                variants = [p for p in backend["programs"] if p["name"].startswith(layout + "_")]
                self.assertEqual(len(variants), 3)
                sources = [payload[p["vertex_func"]["offset"]:p["vertex_func"]["offset"] + p["vertex_func"]["size"]] for p in variants]
                self.assertEqual(sources[0], sources[1])
                self.assertEqual(sources[0], sources[2])

    def test_world_direction_conversion_preserves_resource_layout(self):
        self.run_build()
        converted, _ = decode(self.out / "Foliage.shaderpack")
        hook = self.game / "wind.glsl"
        hook.write_text(hook.read_text().replace("vertex.world_to_local_direction", "mat3(1.0)"))
        self.run_build()
        local_only, _ = decode(self.out / "Foliage.shaderpack")
        self.assertEqual(fingerprint(converted), fingerprint(local_only))

    def test_long_texture_names_preserve_compiler_reflection(self):
        declaration = json.loads((self.game / "shaders.json").read_text())
        name = "noise" * 64
        declaration["shaders"][0]["textures"][0]["name"] = name
        (self.game / "wind.glsl").write_text((self.game / "wind.glsl").read_text().replace("sample_noise", "sample_" + name))
        (self.game / "shaders.json").write_text(json.dumps(declaration))
        self.run_build()
        manifest, _ = decode(self.out / "Foliage.shaderpack")
        for backend in manifest["shaders"]:
            names = [pair["name"] for program in backend["programs"] for pair in program.get("texture_sampler_pairs", [])]
            self.assertTrue(any(len(resource) > 128 for resource in names))

    def test_defaults_rigid_only_and_single_post_location(self):
        source = json.loads((self.game / "shaders.json").read_text())
        source["shaders"][0] = {"name": "Plain", "kind": "surface", "max_displacement": 0, "skinning": False, "instancing": False}
        source["shaders"][1]["locations"] = ["after_tone_map"]
        (self.game / "shaders.json").write_text(json.dumps(source))
        self.run_build()
        manifest, _ = decode(self.out / "Plain.shaderpack")
        self.assertEqual(len(manifest["shaders"][0]["programs"]), 3)
        self.assertEqual(manifest["interface"]["surface"]["parameters"], [])
        post, _ = decode(self.out / "Outline.shaderpack")
        self.assertEqual([p["name"] for p in post["shaders"][0]["programs"]], ["post_ldr"])

    def test_unsupported_reflection_is_rejected(self):
        self.run_build()
        reflection = parse_reflection((self.out / "Foliage.sources/compiled_reflection.yaml").read_text())
        declaration = validate(Document(self.game / "shaders.json"))["shaders"][0]
        contract = json.loads((TOOLS / "contract-v1/contract.json").read_text())
        validate_reflection(reflection, declaration, contract)
        for mutate in (lambda p: p.update(unknown_section=[]),
                       lambda p: p["uniform_blocks"][0].update(size=704),
                       lambda p: p["attrs"][0].update(type="vec4"),
                       lambda p: p["views"][0]["texture"].update(slot=15)):
            changed = copy.deepcopy(reflection)
            mutate(changed["shaders"][0]["programs"][0])
            with self.assertRaises(BuildError):
                validate_reflection(changed, declaration, contract)

    @unittest.skipUnless(ROC, "roc is unavailable")
    def test_generated_helpers_typecheck_and_mistyped_values_fail_roc_build(self):
        source = json.loads((self.game / "shaders.json").read_text())
        source["meshes"] = [{"name": "Tree", "source": "tree.gltf"}]
        surface = source["shaders"][0]
        for name, kind, default in (("uv_scale", "Vec2", [1, 1]), ("axis", "Vec3", [0, 1, 0]), ("vector", "Vec4", [1, 2, 3, 4]), ("transform", "Mat4", [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])):
            surface["parameters"].append({"name": name, "type": kind, "scope": "Draw", "stage": "vertex", "default": default})
        surface["textures"].append({"name": "sky", "scope": "Draw", "stage": "fragment", "type": "cube", "colour_space": "linear", "sampler_policy": {"min": "linear", "mag": "linear", "wrap": "clamp"}, "default": {"pack": "sky", "asset": "sky/day"}})
        (self.game / "tree.gltf").write_text(json.dumps({"materials": [{"name": "Bark"}, {}, {"name": "Leaves"}]}))
        (self.game / "shaders.json").write_text(json.dumps(source))
        self.run_build()
        formatting = subprocess.run([ROC, "fmt", "--check", str(self.game / "Foliage.roc"), str(self.game / "Outline.roc"), str(self.game / "Tree.roc")], cwd=self.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(formatting.returncode, 0, formatting.stdout)
        main = self.game / "main.roc"
        valid = '''app [init, launch, loaded, step, view] { pf: platform "../published-platform/main.roc", roc: "nightly-2026-11-04-2622062" }
import pf.Vocabulary exposing [Command, Manifest]
import pf.Scene
import pf.Launch
import pf.Shader
import Foliage
import Outline
import Tree
Model : { values : Shader.Values }
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| Launch.default
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { values: Foliage.scene("trees", { ..Foliage.scene_default, wind: 0.5 }) }, commands: [] }
loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, _results, _dt| { model, commands: [] }
view : Model -> Vocabulary.Scene
view = |_model| Scene.empty
expect Outline.draw("trees", Outline.draw_default).scope == Draw
expect Foliage.draw_with_textures("trees", Foliage.draw_default, { sky: Cubemap({ pack: "sky", asset: "sky/day" }) }).scope == Draw
expect Foliage.draw_default.transform.c0.x == 1.0
expect Tree.slot_leaves("trees").source_material == 2
expect Foliage.material_with_textures("trees", Foliage.material_default, { ..Foliage.material_textures_default, detail: Image2D({ pack: "textures", asset: "image/detail" }) }).textures.len() == 1
expect Tree.bark("trees", Foliage.material_with_textures("trees", Foliage.material_default, { ..Foliage.material_textures_default, detail: Image2D({ pack: "textures", asset: "detail.png" }) })).slot.source_material == 0
expect Foliage.scene_with_textures("trees", Foliage.scene_default, { noise: Image2D({ pack: "textures", asset: "noise.png" }) }).scope == Scene
'''
        main.write_text(valid)
        result = subprocess.run([ROC, "test", str(main)], cwd=self.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        for old, new in (("wind: 0.5", 'wind: "bad"'), ("wind: 0.5", "wind: Bool.True"), ("wind: 0.5", "phase: 0.5"), ('Image2D({ pack: "textures"', 'Cubemap({ pack: "textures"')):
            main.write_text(valid.replace(old, new))
            result = subprocess.run([ROC, "build", str(main)], cwd=self.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertTrue("type mismatch" in result.stdout or "record" in result.stdout, result.stdout)

if __name__ == "__main__":
    unittest.main()

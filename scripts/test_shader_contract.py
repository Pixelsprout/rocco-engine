import copy
import importlib.util
import json
from pathlib import Path
import struct
import unittest

SPEC = importlib.util.spec_from_file_location("shader_contract", Path(__file__).parent / "shader_contract/contract.py")
contract = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(contract)


class PackageTests(unittest.TestCase):
    def setUp(self):
        interface = json.loads((contract.ROOT / "scripts/shader_contract/interface.json").read_text())
        stage = {"offset": 0, "size": 1, "entry_point": "main", "is_binary": False}
        self.manifest = {"interface": interface, "shaders": [{"slang": "glsl430", "programs": [
            {"name": "surface", "vertex_func": stage.copy(), "fragment_func": stage.copy(),
             "uniform_blocks": [{"slot": 4, "size": 256, "stage": "vertex"}]}]}]}
        self.blob = contract.pack(self.manifest, b"x")

    def test_header_and_roundtrip(self):
        self.assertEqual(contract.HEADER.size, 96)
        self.assertEqual(contract.unpack(self.blob), (self.manifest, b"x"))

    def test_version_flags_backend_and_size_rejection(self):
        for offset, value in [(8, 2), (10, 2), (12, 100), (16, 2**22), (20, 2**25), (24, 1), (28, 3)]:
            data = bytearray(self.blob)
            struct.pack_into("<H" if offset in (8, 10) else "<I", data, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                contract.unpack(data)
        for blob in (self.blob[:95], self.blob[:-1], self.blob + b"x"):
            with self.assertRaises(ValueError):
                contract.unpack(blob)

    def test_content_and_interface_corruption_rejection(self):
        for offset in (32, 64, 100, len(self.blob)-1):
            blob = bytearray(self.blob)
            blob[offset] ^= 1
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                contract.unpack(blob)

    def test_interface_includes_layout_and_defaults_but_excludes_code(self):
        changed = copy.deepcopy(self.manifest)
        fingerprint = contract.interface_hash(changed)
        changed["shaders"][0]["programs"][0]["vertex_func"]["size"] = 12
        self.assertEqual(fingerprint, contract.interface_hash(changed))
        changed["shaders"][0]["programs"][0]["uniform_blocks"][0]["inst_name"] = "_1234"
        self.assertEqual(fingerprint, contract.interface_hash(changed))
        changed["shaders"][0]["programs"][0]["uniform_blocks"][0]["size"] = 128
        self.assertNotEqual(fingerprint, contract.interface_hash(changed))
        changed = copy.deepcopy(self.manifest)
        changed["interface"]["surface"]["parameters"][0]["default"] = [0.5]
        self.assertNotEqual(fingerprint, contract.interface_hash(changed))

    def test_invalid_code_ranges(self):
        for offset, size in [(-1, 1), (0, 0), (0, 2), (True, 1)]:
            self.manifest["shaders"][0]["programs"][0]["vertex_func"].update(offset=offset, size=size)
            with self.assertRaises(ValueError):
                contract.unpack(contract.pack(self.manifest, b"x"))

    def test_parameter_encoding(self):
        self.assertEqual(contract.encode_parameter("Vec3", [1, 2, 3]), struct.pack("<4f", 1, 2, 3, 0))
        self.assertEqual(contract.encode_parameter("Bool", [True]), struct.pack("<4f", 1, 0, 0, 0))
        self.assertEqual(len(contract.encode_parameter("Mat4", list(range(16)))), 64)
        for kind, value in [("U32", [1]), ("Bool", [1]), ("F32", [float("nan")]),
                            ("F32", [float("inf")]), ("F32", [1e40]), ("Vec2", [1]), ("F32", [True])]:
            with self.subTest(kind=kind, value=value), self.assertRaises(ValueError):
                contract.encode_parameter(kind, value)

    def test_parameter_capacity_and_scope(self):
        for change in ({"offset": 256}, {"offset": 1}, {"scope": "Global"}, {"stage": "compute"}):
            interface = copy.deepcopy(self.manifest["interface"])
            interface["surface"]["parameters"][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_parameters(interface)
        interface = copy.deepcopy(self.manifest["interface"])
        interface["surface"]["parameters"].append(dict(interface["surface"]["parameters"][0], name="other"))
        with self.assertRaises(ValueError):
            contract.validate_parameters(interface)
        interface = copy.deepcopy(self.manifest["interface"])
        interface["surface"]["parameters"][0]["offset"] = 240
        contract.validate_parameters(interface)

    def test_texture_capacity_types_and_defaults(self):
        for change in ({"view": 7}, {"sampler": 10}, {"type": "array"}, {"sample_type": "uint"},
                       {"colour_space": "unknown"}, {"optional": False}, {"default": {"pack": "", "asset": "x"}}):
            interface = copy.deepcopy(self.manifest["interface"])
            interface["surface"]["textures"][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_parameters(interface)
        interface = copy.deepcopy(self.manifest["interface"])
        interface["surface"]["textures"].append(dict(interface["surface"]["textures"][0], name="other"))
        with self.assertRaises(ValueError):
            contract.validate_parameters(interface)

    def test_aligned_accounting(self):
        result = contract.budget({"uniform_blocks": [
            {"size": 16, "stage": "fragment"}, {"size": 256, "stage": "vertex"},
            {"size": 4096, "stage": "vertex"}]})
        self.assertEqual(result["uniform_bytes"], 4608)
        self.assertEqual(result["vertex_components"], 1088)
        self.assertEqual(result["fragment_components"], 4)

    def test_gl_storage_remap_preserves_sampler_and_requires_exact_declaration(self):
        program = {"views": [{"storage_buffer": {"slot": 12, "glsl_binding_n": 12, "struct_name": "points"}}]}
        source = b"layout(binding = 12, std430) readonly buffer points\n{ vec4 data[]; };\nlayout(binding = 0) uniform sampler2D tex;\n"
        result = contract.remap_gl_storage(program, source)
        self.assertIn(b"layout(binding = 0, std430) readonly buffer points", result)
        self.assertIn(b"layout(binding = 0) uniform sampler2D tex;", result)
        self.assertEqual(program["views"][0]["storage_buffer"]["glsl_binding_n"], 0)
        for invalid in (source, b"", result + result):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                contract.remap_gl_storage(program, invalid)

    def test_reflection_subset_rejects_yaml_features(self):
        self.assertEqual(contract.parse_reflection("shaders:\n  -\n    slang: glsl430\n    count: 3\n    binary: false\n"),
                         {"shaders": [{"slang": "glsl430", "count": 3, "binary": False}]})
        for source in ("key: &anchor\n", "key: [1,2]\n", "key: x\nkey: y\n", "key:\n"):
            with self.assertRaises(ValueError):
                contract.parse_reflection(source)


if __name__ == "__main__":
    unittest.main()

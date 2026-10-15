# Run from the repository root: python3 -m unittest scripts/test_make_macos_sysroot.py

import copy
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_macos_sysroot as sysroot

SOURCE = {
    "url": "https://developer.apple.com/documentation/appkit/nsview",
    "evidence_kind": "exact_C_identifier",
    "response_sha256": "0" * 64,
}


def library(name, install_name, symbols):
    return {
        "name": name,
        "path": f"System/Library/Frameworks/{name}.framework/{name}.tbd",
        "install_name": install_name,
        "path_sources": ["https://developer.apple.com/library/archive/"],
        "symbols": [{"name": s, "sources": [SOURCE]} for s in symbols],
    }


def catalog():
    system = library("libSystem", "/usr/lib/libSystem.B.dylib", ["_malloc"])
    system["path"] = "usr/lib/libSystem.tbd"
    objc = library("libobjc", "/usr/lib/libobjc.A.dylib", ["_objc_msgSend"])
    objc["path"] = "System/Library/Frameworks/objc.framework/objc.tbd"
    return {
        "schema_version": 1,
        "target": "arm64-macos",
        "libraries": [
            library(
                "AppKit",
                "/System/Library/Frameworks/AppKit.framework/AppKit",
                ["_OBJC_CLASS_$_NSView", "_NSApp"],
            ),
            library("Cocoa", "/System/Library/Frameworks/Cocoa.framework/Cocoa", []),
            objc,
            system,
        ],
    }


class RenderTest(unittest.TestCase):
    def test_writes_one_sorted_tbd_per_library(self):
        files = sysroot.render(sysroot.validate(catalog()))
        self.assertEqual(
            files["System/Library/Frameworks/AppKit.framework/AppKit.tbd"],
            "--- !tapi-tbd\n"
            "tbd-version: 4\n"
            "targets: [ arm64-macos ]\n"
            "install-name: '/System/Library/Frameworks/AppKit.framework/AppKit'\n"
            "exports:\n"
            "  - targets: [ arm64-macos ]\n"
            "    symbols:\n"
            "      - '_NSApp'\n"
            "      - '_OBJC_CLASS_$_NSView'\n"
            "...\n",
        )

    def test_a_library_with_no_symbols_has_no_exports(self):
        files = sysroot.render(sysroot.validate(catalog()))
        tbd = files["System/Library/Frameworks/Cocoa.framework/Cocoa.tbd"]
        self.assertNotIn("exports", tbd)
        self.assertTrue(tbd.endswith("Cocoa.framework/Cocoa'\n...\n"))

    def test_libobjc_is_a_framework_with_the_dylib_install_name(self):
        files = sysroot.render(sysroot.validate(catalog()))
        tbd = files["System/Library/Frameworks/objc.framework/objc.tbd"]
        self.assertIn("install-name: '/usr/lib/libobjc.A.dylib'\n", tbd)

    def test_write_replaces_the_old_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "macos-sysroot"
            (out / "System/Library/Frameworks/Stale.framework").mkdir(parents=True)
            sysroot.write(sysroot.render(sysroot.validate(catalog())), out)
            frameworks = sorted(p.name for p in (out / "System/Library/Frameworks").iterdir())
            self.assertEqual(frameworks, ["AppKit.framework", "Cocoa.framework", "objc.framework"])
            self.assertTrue((out / "usr/lib/libSystem.tbd").is_file())


class ValidateTest(unittest.TestCase):
    def rejects(self, change):
        bad = catalog()
        change(bad)
        with self.assertRaises(ValueError):
            sysroot.validate(bad)

    def test_accepts_the_example(self):
        sysroot.validate(catalog())

    def test_rejects_reexports(self):
        self.rejects(lambda c: c["libraries"][0].update(reexports=["/usr/lib/libobjc.A.dylib"]))

    def test_rejects_a_usr_lib_path_other_than_libsystem(self):
        self.rejects(lambda c: c["libraries"][2].update(path="usr/lib/libobjc.A.tbd"))

    def test_rejects_a_framework_path_that_does_not_match_its_folder(self):
        self.rejects(
            lambda c: c["libraries"][0].update(path="System/Library/Frameworks/AppKit.framework/Foo.tbd")
        )

    def test_rejects_a_missing_libsystem(self):
        self.rejects(lambda c: c["libraries"].pop())

    def test_rejects_a_symbol_twice(self):
        self.rejects(lambda c: c["libraries"][1]["symbols"].append(copy.deepcopy(c["libraries"][0]["symbols"][0])))

    def test_rejects_a_symbol_with_no_sources(self):
        self.rejects(lambda c: c["libraries"][0]["symbols"][0].update(sources=[]))

    def test_rejects_a_source_with_no_hash(self):
        self.rejects(lambda c: c["libraries"][0]["symbols"][0]["sources"][0].pop("response_sha256"))

    def test_rejects_a_source_that_is_not_https(self):
        self.rejects(lambda c: c["libraries"][0]["symbols"][0]["sources"][0].update(url="http://example.com"))

    def test_rejects_an_unknown_evidence_kind(self):
        self.rejects(lambda c: c["libraries"][0]["symbols"][0]["sources"][0].update(evidence_kind="linker_error"))

    def test_accepts_an_abi_variant_suffix(self):
        ok = catalog()
        ok["libraries"][3]["symbols"][0]["name"] = "_close$NOCANCEL"
        sysroot.validate(ok)

    def test_rejects_a_compiler_selector_stub_with_an_upper_case_selector(self):
        self.rejects(lambda c: c["libraries"][2]["symbols"][0].update(name="_objc_msgSend$UTF8String"))

    def test_rejects_a_compiler_selector_stub(self):
        self.rejects(lambda c: c["libraries"][2]["symbols"][0].update(name="_objc_msgSend$init"))


class UncoveredTest(unittest.TestCase):
    def test_lists_references_that_no_archive_defines_and_the_catalog_lacks(self):
        undefined = ["_malloc", "_free", "_objc_msgSend$init", "_roc__main", "_clay_layout", "_NSApp"]
        defined = ["_clay_layout"]
        self.assertEqual(sysroot.uncovered(sysroot.validate(catalog()), undefined, defined), ["_free"])

    def test_skips_odin_package_symbols(self):
        undefined = ["_os::is_tty", "_log::[file_console_logger.odin]::global_subtract_stderr_options", "_free"]
        self.assertEqual(sysroot.uncovered(sysroot.validate(catalog()), undefined, []), ["_free"])


if __name__ == "__main__":
    unittest.main()

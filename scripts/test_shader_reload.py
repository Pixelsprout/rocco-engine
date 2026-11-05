"""Watch dependency, publication, and source-snapshot regression checks."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "platform/shader-tools"))
import build
from declarations import BuildError


class WatchTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.declaration = self.root / "shaders.json"
        self.source = self.root / "wind.glsl"
        self.source.write_text("first")
        self.write_declaration("wind.glsl")
        self.compile = mock.Mock(return_value={"assets": [], "meshes": []})
        self.watcher = build.Watcher(self.declaration, self.compile)

    def write_declaration(self, source):
        self.declaration.write_text(json.dumps({"shaders": [{"vertex": source}]}))

    def test_content_changes_with_equal_timestamp_trigger_build(self):
        self.assertTrue(self.watcher.poll())
        self.assertFalse(self.watcher.poll())
        stamp = self.source.stat()
        self.source.write_text("other")
        os.utime(self.source, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.assertTrue(self.watcher.poll())
        self.assertEqual(self.compile.call_count, 2)

    def test_invalid_declaration_retains_previous_paths_and_recovers(self):
        self.watcher.poll()
        self.declaration.write_text("{")
        self.compile.side_effect = BuildError("bad declaration")
        self.watcher.poll()
        self.source.write_text("edit while declaration is invalid")
        self.assertTrue(self.watcher.poll())
        self.compile.side_effect = None
        self.write_declaration("new.glsl")
        self.watcher.poll()
        self.source.write_text("old path no longer watched")
        self.assertFalse(self.watcher.poll())
        (self.root / "new.glsl").write_text("missing path appears")
        self.assertTrue(self.watcher.poll())

    def test_semantically_invalid_declaration_still_follows_new_missing_path(self):
        self.watcher.poll()
        self.write_declaration("missing.glsl")
        self.compile.side_effect = BuildError("missing source")
        self.watcher.poll()
        self.assertFalse(self.watcher.poll())
        (self.root / "missing.glsl").write_text("now available")
        self.assertTrue(self.watcher.poll())

    def test_changes_during_failed_build_retry_without_another_edit(self):
        def compile_build():
            self.source.write_text("changed during compilation")
            raise BuildError("inputs changed")
        self.compile.side_effect = compile_build
        self.watcher.poll()
        self.assertIsNone(self.watcher.previous)
        self.compile.side_effect = None
        self.assertTrue(self.watcher.poll())

    def test_unrelated_files_and_meshes_are_not_watch_dependencies(self):
        self.watcher.poll()
        (self.root / "unused.glsl").write_text("unused")
        (self.root / "tree.glb").write_bytes(b"mesh")
        self.assertFalse(self.watcher.poll())
        self.assertEqual(self.watcher.paths, {self.declaration, self.source})

    def test_missing_declaration_recovers(self):
        self.declaration.unlink()
        self.compile.side_effect = OSError("missing declaration")
        self.watcher.poll()
        self.compile.side_effect = None
        self.write_declaration("wind.glsl")
        self.assertTrue(self.watcher.poll())

    def test_all_declared_hook_types_trigger_builds(self):
        hooks = ('vertex', 'surface', 'lighting', 'post')
        self.declaration.write_text(json.dumps({'shaders': [{hook: hook + '.glsl'} for hook in hooks]}))
        self.watcher.poll()
        for hook in hooks:
            (self.root / (hook + '.glsl')).write_text('new source')
            self.assertTrue(self.watcher.poll())
            self.assertFalse(self.watcher.poll())
        self.assertEqual(self.compile.call_count, 5)

    def test_windows_publication_recovers_after_the_reader_closes(self):
        error = PermissionError('reader denies replacement')
        error.winerror = 32
        self.compile.side_effect = [error, {'assets': [], 'meshes': []}]
        with mock.patch.object(build.sys, 'platform', 'win32'):
            self.watcher.poll()
            self.assertTrue(self.watcher.poll())
        self.assertEqual(self.compile.call_count, 2)


class PublicationTests(unittest.TestCase):
    def test_windows_permanent_access_error_fails_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'asset'
            path.write_bytes(b'old')
            error = PermissionError('access denied')
            error.winerror = 5
            with mock.patch.object(build.sys, 'platform', 'win32'), mock.patch.object(build.os, 'replace', side_effect=error) as replace, mock.patch.object(build.time, 'sleep') as sleep:
                with self.assertRaises(PermissionError):
                    build.write_changed(path, b'new')
            self.assertEqual(path.read_bytes(), b'old')
            self.assertEqual(replace.call_count, 1)
            sleep.assert_not_called()

    def test_windows_reader_sharing_violation_retries_atomic_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'asset'
            path.write_bytes(b'old')
            replace = os.replace
            calls = []
            def publish(source, target):
                calls.append(target)
                if len(calls) == 1:
                    error = PermissionError('reader denies replacement')
                    error.winerror = 32
                    raise error
                replace(source, target)
            with mock.patch.object(build.sys, 'platform', 'win32'), mock.patch.object(build.os, 'replace', side_effect=publish), mock.patch.object(build.time, 'sleep'):
                build.write_changed(path, b'new')
            self.assertEqual(path.read_bytes(), b'new')
            self.assertEqual(len(calls), 2)

    def test_persistent_windows_sharing_failure_is_bounded_and_keeps_old_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'asset'
            path.write_bytes(b'old')
            error = PermissionError('reader denies replacement')
            error.winerror = 32
            with mock.patch.object(build.sys, 'platform', 'win32'), mock.patch.object(build.os, 'replace', side_effect=error) as replace, mock.patch.object(build.time, 'sleep'):
                with self.assertRaises(PermissionError):
                    build.write_changed(path, b'new')
            self.assertEqual(path.read_bytes(), b'old')
            self.assertEqual(replace.call_count, 40)
            self.assertEqual([p.name for p in Path(directory).iterdir()], ['asset'])

    def test_changed_source_snapshot_never_publishes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "wind.glsl").write_text("void rocco_vertex(inout RoccoVertex vertex) {}")
            declaration = root / "shaders.json"
            declaration.write_text(json.dumps({"contract": 1, "shaders": [{"name": "Wind", "kind": "surface", "vertex": "wind.glsl", "max_displacement": 1}]}))
            def compile_shader(*args):
                (root / "wind.glsl").write_text("changed during compilation")
                args[-1].mkdir(parents=True)
                return b"package", {"interface": {}, "shaders": []}, {}, set()
            with mock.patch.object(build, "compiler_path", return_value=(Path("unused"), {"commit": "pin"})), mock.patch.object(build, "compile_shader", side_effect=compile_shader), mock.patch.object(build, "write_changed") as publish:
                with self.assertRaisesRegex(BuildError, "inputs changed"):
                    build.build(declaration, root / "assets", root / "helpers")
                publish.assert_not_called()

    def test_completion_record_publishes_after_all_other_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            declaration = root / "shaders.json"
            declaration.write_text('{"contract":1,"shaders":[]}')
            with mock.patch.object(build, "compiler_path", return_value=(Path("unused"), {"commit": "pin"})), mock.patch.object(build, "write_changed") as publish:
                build.build(declaration, root / "assets", root / "helpers")
            self.assertEqual(publish.call_args_list[-1].args[0].name, "build.json")
            record = json.loads(publish.call_args_list[-1].args[1])
            self.assertEqual(len(record["revision"]), 64)


if __name__ == "__main__":
    unittest.main()

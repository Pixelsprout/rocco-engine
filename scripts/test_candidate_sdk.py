"""Check candidate archive inputs and the independent fixture boundary."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import bundle_sdk
import candidate_sdk


class BundleTests(unittest.TestCase):
    def test_platform_explicitly_carries_tools_and_targets_without_debug_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            platform = root / 'platform'
            for name in ('main.roc', 'Vocabulary.roc', 'targets/arm64mac/libhost.a',
                         'targets/x64win/host.lib', 'targets/x64win/host.pdb',
                         'shader-tools/build.py', 'shader-tools/contract-v1/compiler.json',
                         'shader-tools/__pycache__/build.pyc'):
                path = platform / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'input')
            for package in bundle_sdk.PACKAGES[1:]:
                folder = root / 'packages' / package
                folder.mkdir(parents=True)
                (folder / 'main.roc').write_text('package [] {}')
            commands = []
            def run(command, cwd, check):
                commands.append((command, cwd))
                out = Path(command[command.index('--output-dir') + 1])
                (out / 'HASH.tar.zst').write_bytes(b'archive')
            with patch.object(bundle_sdk, 'ROOT', root), patch.object(bundle_sdk.subprocess, 'run', run):
                result = bundle_sdk.bundle(root / 'out')
            inputs = commands[0][0]
            self.assertIn('targets/arm64mac/libhost.a', inputs)
            self.assertIn('targets/x64win/host.lib', inputs)
            self.assertIn('shader-tools/build.py', inputs)
            self.assertIn('shader-tools/contract-v1/compiler.json', inputs)
            self.assertNotIn('targets/x64win/host.pdb', inputs)
            self.assertNotIn('shader-tools/__pycache__/build.pyc', inputs)
            self.assertEqual(set(result), set(bundle_sdk.PACKAGES))
            self.assertTrue(all(path.is_file() for path in result.values()))

    def test_candidate_fixture_has_no_repo_dependencies_or_built_outputs(self):
        fixture = candidate_sdk.ROOT / 'examples/authoring'
        for name in candidate_sdk.FIXTURE_FILES:
            self.assertTrue((fixture / name).is_file(), name)
            self.assertNotIn(Path(name).suffix, ('.odin', '.bin', '.exe', '.shaderpack'))
        for name in ('proof.py', 'bridge.py'):
            source = (fixture / name).read_text()
            self.assertNotIn('sys.path.insert', source)
            self.assertNotIn('from scripts', source)
            self.assertNotIn('import bridge_check', source)
        workflow = (candidate_sdk.ROOT / '.github/workflows/ci.yml').read_text()
        external = workflow.split('\n  external-authoring:', 1)[1]
        self.assertNotIn('uses: actions/checkout', external)
        self.assertNotIn('odin-lang/Odin', external)
        self.assertIn('unset LIB', external)
        self.assertIn("shutil.which('odin') is None", external)

    def test_candidate_refuses_an_incomplete_target_set(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(candidate_sdk, 'ROOT', Path(temporary)):
            with self.assertRaisesRegex(FileNotFoundError, 'ordinary release target'):
                candidate_sdk.candidate(Path(temporary) / 'out')

    def test_candidate_records_hashes_commit_and_every_fixture_file(self):
        def fake_bundle(out):
            out.mkdir(parents=True)
            archive = out / 'platform-HASH.tar.zst'
            archive.write_bytes(b'actual archive bytes')
            return {'platform': archive}
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary) / 'candidate'
            with patch.object(candidate_sdk, 'bundle', fake_bundle), \
                 patch.object(candidate_sdk.Path, 'is_file', return_value=True), \
                 patch.object(candidate_sdk.subprocess, 'check_output', return_value='abcdef\n'), \
                 patch.dict(os.environ, {'GITHUB_RUN_ID': '42', 'GITHUB_REPOSITORY': 'owner/repo'}):
                candidate_sdk.candidate(out)
            metadata = json.loads((out / 'candidate.json').read_text())
            self.assertEqual(metadata['commit'], 'abcdef')
            self.assertEqual(metadata['run_id'], '42')
            self.assertIn('not a stable release', metadata['kind'])
            self.assertEqual(metadata['bundles'], {'platform': 'platform-HASH.tar.zst'})
            checksums = dict(line.split('  ', 1)[::-1] for line in (out / 'SHA256SUMS').read_text().splitlines())
            self.assertEqual(set(checksums), {'platform-HASH.tar.zst', 'candidate.json', 'authoring-fixture.tar.gz'})
            for name, digest in checksums.items():
                self.assertEqual(hashlib.sha256((out / name).read_bytes()).hexdigest(), digest)
            with tarfile.open(out / 'authoring-fixture.tar.gz') as archive:
                self.assertEqual(set(archive.getnames()), {'authoring/' + name for name in candidate_sdk.FIXTURE_FILES})


class ProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture = candidate_sdk.ROOT / 'examples/authoring'
        def load(name, path):
            spec = importlib.util.spec_from_file_location(name, path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
        standalone_bridge = load('authoring_bridge', fixture / 'bridge.py')
        with patch.dict(sys.modules, {'bridge': standalone_bridge}):
            cls.proof = load('authoring_proof', fixture / 'proof.py')

    def setUp(self):
        self.candidate = dict(repository='owner/repo', run_id='42', commit='abcdef')
        self.provenance = dict(artifact_id='7', artifact_sha256='a' * 64,
                              artifact_url='https://github.com/owner/repo/actions/runs/42/artifacts/7')
        self.environment = dict(GITHUB_ACTIONS='true', GITHUB_RUN_ID='42', GITHUB_REPOSITORY='owner/repo',
                                CANDIDATE_COMMIT='abcdef')

    def test_local_sdk_with_artifact_fields_cannot_claim_the_published_gate(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(self.proof.published_provenance(self.candidate, self.provenance))

    def test_matching_clean_ci_artifact_provenance_can_claim_publication(self):
        with patch.dict(os.environ, self.environment, clear=True):
            self.assertTrue(self.proof.published_provenance(self.candidate, self.provenance))

    def test_missing_digest_or_different_run_rejects_publication(self):
        with patch.dict(os.environ, self.environment, clear=True):
            with self.assertRaisesRegex(AssertionError, 'SHA-256'):
                self.proof.published_provenance(self.candidate, {**self.provenance, 'artifact_sha256': None})
            with self.assertRaisesRegex(AssertionError, 'clean CI proof job'):
                self.proof.published_provenance({**self.candidate, 'commit': 'different'}, self.provenance)


if __name__ == '__main__':
    unittest.main()

"""Run with python3 -m unittest tools.test_portable_snapshot."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

class SnapshotTests(unittest.TestCase):
    def test_generated_manifest_matches_installed_profiles(self):
        import hashlib
        import json
        root = Path(__file__).resolve().parent.parent
        manifest = json.loads((root / 'data/collision/generated/manifest.json').read_text())
        profiles = sorted((root / 'data/collision/generated').glob('*.tres'))
        self.assertEqual(manifest['generated_count'], len(profiles))
        self.assertEqual(manifest['failed_count'], 0)
        self.assertEqual({e['profile'] for e in manifest['entries']},
                         {'res://' + p.relative_to(root).as_posix() for p in profiles})
        for entry in manifest['entries']:
            with self.subTest(character=entry['id']):
                path = root / entry['profile'].removeprefix('res://')
                self.assertEqual(entry['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_missing_referenced_navigation_rejected_before_copy(self):
        from tools.portable_snapshot import copy_manifest
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            (source / 'scripts/core/input').mkdir(parents=True)
            owner = 'scripts/core/input/repo_ai_match_input.gd'
            dependency = 'scripts/core/input/stage_navigation.gd'
            (source / owner).write_text('const Navigation = preload("res://' + dependency + '")\n')
            (source / dependency).write_text('extends RefCounted\n')
            target = Path(directory) / 'snapshot'
            with self.assertRaisesRegex(ValueError, 'stage_navigation'):
                copy_manifest(source, target, [owner])
            self.assertFalse(target.exists(), 'dependency rejection must precede mutation')

    def test_hash_sensitive_lf_checkout(self):
        """Regression for the observed presenter autocrlf provenance drift."""
        import re
        import subprocess
        root = Path(__file__).resolve().parent.parent
        files = list((root / 'data').rglob('*.tres'))
        presenters = {name for p in (root / 'data/collision/generated').glob('*.tres')
                      for name in re.findall(r'&?"presenter": "res://([^"]+)"', p.read_text())}
        files += [root / name for name in presenters]
        self.assertTrue(files)
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            subprocess.run(['git', 'init', '--quiet', str(scratch)], check=True)
            (scratch / '.gitattributes').write_bytes((root / '.gitattributes').read_bytes())
            for path in files:
                with self.subTest(path=path.relative_to(root).as_posix()):
                    data = path.read_bytes()
                    self.assertNotIn(b'\r\n', data)
                    blob = subprocess.check_output(['git', 'hash-object', '-w', '--stdin'],
                                                   cwd=scratch, input=data).decode().strip()
                    actual = subprocess.check_output(['git', '-c', 'core.autocrlf=true', 'cat-file',
                                                      '--filters', '--path=' + path.relative_to(root).as_posix(), blob],
                                                     cwd=scratch)
                    self.assertEqual(actual, data)

    def test_raw_plugin_includes_manifest_and_refuses_source(self):
        path = Path(__file__).with_name('raw_resource_packaging.py')
        self.assertTrue(path.exists(), 'raw packaging helper required')
        spec = importlib.util.spec_from_file_location('raw_pack', path)
        helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            (stage / '.verification/snapshot').mkdir(parents=True)
            import hashlib
            import json
            (stage / 'project.godot').write_text('[application]\n')
            (stage / 'raw.tres').write_text('raw source bytes\n')
            (stage / '.verification/snapshot/inputs.json').write_text(json.dumps({'files': {
                name: hashlib.sha256((stage / name).read_bytes()).hexdigest()
                for name in ['project.godot', 'raw.tres']}}))
            helper.install(stage, ['raw.tres'])
            self.assertIn('res://raw.tres', (stage / 'addons/portable_raw/export.gd').read_text())
            self.assertIn('false)', (stage / 'addons/portable_raw/export.gd').read_text())
            self.assertIn('portable_raw/plugin.cfg', (stage / 'project.godot').read_text())
            self.assertIn('host.configure', (stage / 'raw_pack_probe.gd').read_text())
            self.assertIn('generated_profile_sha256', (stage / 'raw_pack_probe.gd').read_text())
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                helper.install(Path(directory), [])

    def test_explicit_copy_no_cache_and_raw_resources(self):
        path = Path(__file__).with_name('portable_snapshot.py')
        self.assertTrue(path.exists(), 'explicit snapshot helper required')
        spec = importlib.util.spec_from_file_location('snapshot', path)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'source'; root.mkdir()
            (root / 'project.godot').write_text('[application]\n')
            (root / '.godot').mkdir(); (root / '.godot/private').write_text('cache')
            target = Path(directory) / 'stage'
            result = helper.copy_manifest(root, target, ['project.godot'])
            self.assertEqual(list(result), ['project.godot'])
            self.assertFalse((target / '.godot').exists())
            with self.assertRaises(ValueError):
                helper.copy_manifest(root, Path(directory) / 'bad', ['.godot/private'])
            with self.assertRaises(ValueError):
                helper.copy_manifest(root, root, ['project.godot'])
            with self.assertRaises(ValueError):
                helper.copy_manifest(root, Path(directory) / 'escape', ['../outside'])
            with self.assertRaises(ValueError):
                helper.copy_manifest(root, root / 'scripts/new', ['project.godot'])
            self.assertIn('sys.executable', path.read_text())

if __name__ == '__main__':
    unittest.main()

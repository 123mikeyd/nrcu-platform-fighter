"""Tests for the isolated movement-candidate export preparation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).with_name('export_core_lab.py')

class CoreExportTests(unittest.TestCase):
    def test_staging_changes_only_candidate_settings(self):
        self.assertTrue(MODULE.exists(), 'isolated candidate exporter must exist')
        spec = importlib.util.spec_from_file_location('core_export', MODULE)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'
            source.mkdir()
            project = '[application]\nconfig/name="NRCU Platform Fighter"\nrun/main_scene="res://scenes/home.tscn"\n[physics]\n'
            (source / 'project.godot').write_text(project)
            (source / 'export_presets.cfg').write_text('preset fixture')
            for folder in ['assets', 'scripts', 'scenes', 'tools', 'data']:
                (source / folder).mkdir()
                (source / folder / 'fixture.txt').write_text(folder)
            target = Path(tmp) / 'stage'
            module.prepare_project(source, target)
            self.assertEqual((source / 'project.godot').read_text(), project)
            staged = (target / 'project.godot').read_text()
            self.assertIn('res://scenes/training_lab.tscn', staged)
            self.assertIn('common/physics_ticks_per_second=60', staged)
            self.assertEqual((target / 'scripts/fixture.txt').read_text(), 'scripts')
            self.assertTrue((target / 'data/fixture.txt').exists(), 'candidate includes tuning resources')
            # Incremental rebuilds must remove stale deleted source files.
            (source / 'scripts/fixture.txt').unlink()
            (target / '.godot/exported').mkdir(parents=True)
            (target / '.godot/exported/stale.scn').write_text('old UID reference')
            module.prepare_project(source, target)
            self.assertFalse((target / 'scripts/fixture.txt').exists())
            self.assertFalse((target / '.godot/exported/stale.scn').exists(), 'fresh export must not reuse stale UID conversion cache')

class CollisionPackagingTests(unittest.TestCase):
    def test_staged_web_preset_preserves_raw_collision_sources(self):
        import configparser
        spec = importlib.util.spec_from_file_location('core_export', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        root = MODULE.parent.parent
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'stage'
            original = (root / 'export_presets.cfg').read_bytes()
            module.prepare_project(root, target)
            plugin = target / 'addons/collision_raw_export/export.gd'
            self.assertTrue(plugin.is_file(), 'raw imported files require an explicit export plugin')
            self.assertIn('add_file', plugin.read_text())
            self.assertEqual((root / 'export_presets.cfg').read_bytes(), original)

class ExportIsolationTests(unittest.TestCase):
    def test_rejects_aliases_before_any_mutation(self):
        import os
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('core_export', MODULE)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        cases = ['stage_project', 'stage_preset', 'stage_child', 'stage_ancestor',
                 'source_alias', 'source_child', 'source_ancestor', 'source_same',
                 'output_alias', 'output_child', 'output_ancestor',
                 'log_alias', 'log_child', 'log_ancestor', 'hardlink',
                 'stage_root_alias', 'source_project_alias', 'source_owned_target',
                 'output_wasm', 'log_manifest', 'stage_nested', 'stage_dangling']
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                source = base / 'source'
                source.mkdir()
                project = 'run/main_scene="res://scenes/home.tscn"\n[physics]\n'
                (source / 'project.godot').write_text(project)
                (source / 'export_presets.cfg').write_text('preset')
                for folder in ['assets', 'scripts', 'scenes', 'tools', 'data']:
                    (source / folder).mkdir()
                    (source / folder / 'keep').write_text(folder)
                legacy = source / 'builds/web'
                legacy.mkdir(parents=True)
                (legacy / 'index.html').write_text('legacy release')
                stage = source / '.verification/core/export-project'
                output = source / 'builds/core-lab'
                logs = source / '.verification/core/export'
                stage.mkdir(parents=True)
                (stage / '.godot').mkdir()
                (stage / '.godot/keep').write_text('cache must survive rejection')
                output.mkdir()
                logs.mkdir()
                target = stage
                src = source
                if case == 'stage_root_alias':
                    (base / 'alias').symlink_to(source, target_is_directory=True)
                    target = base / 'alias'
                elif case == 'source_project_alias':
                    (source / 'project.godot').rename(base / 'project')
                    (source / 'project.godot').symlink_to(base / 'project')
                elif case == 'source_owned_target': target = source / 'scripts/stage'
                elif case == 'output_wasm': (output / 'index.wasm').symlink_to(legacy / 'index.html')
                elif case == 'log_manifest': (logs / 'artifact-manifest.json').symlink_to(legacy / 'index.html')
                elif case == 'stage_nested':
                    (stage / 'scripts').mkdir()
                    (stage / 'scripts/link').symlink_to(source / 'scripts', target_is_directory=True)
                elif case == 'stage_dangling': (stage / 'project.godot').symlink_to(base / 'not-created')
                elif case == 'stage_project': (stage / 'project.godot').symlink_to(source / 'project.godot')
                elif case == 'stage_preset': (stage / 'export_presets.cfg').symlink_to(source / 'export_presets.cfg')
                elif case == 'stage_child': (stage / 'scripts').symlink_to(source / 'scripts', target_is_directory=True)
                elif case == 'stage_ancestor':
                    (base / 'alias').symlink_to(source / '.verification', target_is_directory=True)
                    target = base / 'alias/core/export-project'
                elif case == 'source_alias':
                    (base / 'alias').symlink_to(source, target_is_directory=True)
                    src = base / 'alias'
                elif case == 'source_child':
                    (source / 'scripts/link').symlink_to(source / 'project.godot')
                elif case == 'source_ancestor':
                    (base / 'alias').symlink_to(base, target_is_directory=True)
                    src = base / 'alias/source'
                elif case == 'source_same': target = source
                elif case == 'hardlink': os.link(source / 'project.godot', stage / 'project.godot')
                elif case.endswith('_alias'):
                    path = output if case.startswith('output') else logs
                    path.rmdir()
                    path.symlink_to(legacy, target_is_directory=True)
                elif case.endswith('_child'):
                    path = output / 'index.html' if case.startswith('output') else logs / 'import.log'
                    path.symlink_to(legacy / 'index.html')
                elif case.endswith('_ancestor'):
                    path = source / 'builds' if case.startswith('output') else source / '.verification'
                    moved = base / 'moved'
                    path.rename(moved)
                    path.symlink_to(moved, target_is_directory=True)
                with self.assertRaises(ValueError, msg=case):
                    if case.startswith(('output', 'log')):
                        with patch.object(module, '__file__', str(source / 'tools/export_core_lab.py')), patch('sys.argv', ['export', '--engine', '/bin/true']):
                            module.main()
                    else:
                        module.prepare_project(src, target)
                self.assertEqual((source / 'project.godot').read_text(), project)
                self.assertEqual((source / 'export_presets.cfg').read_text(), 'preset')
                self.assertEqual((legacy / 'index.html').read_text(), 'legacy release')
                self.assertEqual((stage / '.godot/keep').read_text(), 'cache must survive rejection')

if __name__ == '__main__':
    unittest.main(verbosity=2)

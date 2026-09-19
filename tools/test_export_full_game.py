"""Strict local full-game export gates."""
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

class FullGameExportTests(unittest.TestCase):
    def helper(self):
        path = Path(__file__).with_name('export_full_game.py')
        self.assertTrue(path.exists(), 'isolated full-game export helper required')
        spec = importlib.util.spec_from_file_location('full_export', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_web_preserves_upstream_raw_original_game_inputs(self):
        import configparser
        presets = configparser.ConfigParser(interpolation=None)
        presets.read(Path(__file__).resolve().parent.parent / 'export_presets.cfg')
        upstream = set(presets['preset.0']['include_filter'].strip('"').split(','))
        web_presets = [presets[section] for section in presets.sections()
                       if presets[section].get('platform') == '"Web"']
        self.assertEqual({p['name'] for p in web_presets}, {'"Web Browser"', '"Web LAN"'})
        for preset in web_presets:
            web = set(preset['include_filter'].strip('"').split(','))
            self.assertFalse(upstream - web, preset['name'] + ' must retain original game raw inputs')
            self.assertIn('.verification/*', preset['exclude_filter'])

    def test_exit_zero_dependent_compile_errors_abort_acceptance(self):
        helper = self.helper()
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'export.log'
            with self.assertRaises(RuntimeError):
                helper.run_checked([sys.executable, '-c', 'print(\'SCRIPT ERROR: Compile Error: Failed to compile depended scripts.\')'], log)
            self.assertIn('depended scripts', log.read_text())

    def test_current_upstream_title_entry_is_supported(self):
        helper = self.helper()
        text = '[application]\nrun/main_scene="res://scenes/title.tscn"\n'
        changed = helper.full_game_entry(text)
        self.assertEqual(changed.replace('experimental_full_game.tscn', 'title.tscn'), text)
        with self.assertRaises(ValueError):
            helper.full_game_entry(text + 'run/main_scene="res://scenes/home.tscn"\n')

    def test_only_staging_main_scene_changes(self):
        helper = self.helper()
        text = '[application]\nrun/main_scene="res://scenes/home.tscn"\n'
        changed = helper.full_game_entry(text)
        self.assertIn('res://scenes/experimental_full_game.tscn', changed)
        self.assertEqual(changed.replace('experimental_full_game.tscn', 'home.tscn'), text)
        with self.assertRaises(ValueError):
            helper.full_game_entry('[application]\n')

if __name__ == '__main__':
    unittest.main()

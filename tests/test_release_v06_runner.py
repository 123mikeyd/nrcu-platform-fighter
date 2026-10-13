"""Temporary fake-engine TEST FIXTURES, not Godot gameplay evidence."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('runner', ROOT / 'tools/release_v06_runner.py')
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)


NOISE_OK = ("print('ERROR: Parameter \"material\" is null.'); "
            "print('   at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)'); "
            "print('V06_RELEASE_COMPLETE')")
NOISE_BARE = "print('ERROR: Parameter \"material\" is null.'); print('V06_RELEASE_COMPLETE')"


class RunnerTests(unittest.TestCase):
    def test_bounded_process_contract(self):
        with tempfile.TemporaryDirectory(prefix='v06-runner-test-') as tmp:
            log = Path(tmp) / 'fixture.log'
            for script, expected in [("print('V06_RELEASE_COMPLETE')", True),
                                     ("print('nothing')", False),
                                     ("print('V06_RELEASE_COMPLETE'); exit(1)", False),
                                     ("print('V06_RELEASE_COMPLETE'); print('ERROR: fixture')", False),
                                     ("print('V06_RELEASE_COMPLETE'); print('V06_RELEASE_COMPLETE')", False),
                                     (NOISE_OK, True),
                                     (NOISE_BARE, False),
                                     ("import time; time.sleep(5)", False)]:
                with self.subTest(script=script):
                    result = r.run_process([sys.executable, '-c', script], log, 0.5, 'V06_RELEASE_COMPLETE')
                    self.assertEqual(result['passed'], expected)
            self.assertEqual(result['exit'], 124)

    def test_objectdb_leak_is_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            for warning in ['WARNING: 1 ObjectDB instance was leaked at exit (run with `--verbose` for details).',
                            'WARNING: ObjectDB instances leaked at exit (run with --verbose for details).']:
                with self.subTest(warning=warning):
                    result = r.run_process([sys.executable, '-c', "print('DONE'); print(" + repr(warning) + ")"], Path(tmp) / 'log', 5, 'DONE')
                    self.assertFalse(result['passed'])

    def test_focused_inventory_and_markers(self):
        expected = {'test_bobo_down_air', 'test_costume_integration', 'test_doge_super_punch',
                    'test_tek_polish_lifecycle', 'test_turbofit_victory_loop', 'test_v069420_frontend',
                    'test_v069420_help', 'test_witcheer_cane_airborne', 'test_witcheer_poke_lifecycle'}
        names = [name for name, marker in r.CONTRACTS]
        self.assertTrue(expected.issubset(names))
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(all(marker for _, marker in r.CONTRACTS))
        with tempfile.TemporaryDirectory() as tmp:
            for name, marker in r.CONTRACTS:
                for text, expected_pass in [(marker, True), ('', False), (marker + '\n' + marker, False), (marker + ' checks=1', False), ('WARNING: unrelated\n' + marker, True)]:
                    with self.subTest(name=name, text=text):
                        result = r.run_process([sys.executable, '-c', 'print(' + repr(text) + ')'], Path(tmp) / 'log', 5, marker)
                        self.assertEqual(result['passed'], expected_pass)

    def test_suite_persists_each_result_and_isolates_sinks(self):
        from unittest.mock import patch
        import json
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'project'
            (root / 'tests').mkdir(parents=True)
            (root / 'project.godot').write_text('; TEST FIXTURE')
            for name, _ in r.CONTRACTS:
                (root / 'tests' / (name + '.gd')).write_text('; TEST FIXTURE')
            # Exercise an alias spelling: the runner resolves output before use.
            output = root / '..' / 'evidence'
            calls = []
            def child(command, log, timeout, marker=None, env=None):
                if calls:
                    self.assertEqual(len(json.loads((output / 'results.json').read_text())), len(calls))
                self.assertTrue(Path(env['APPDATA']).is_relative_to(output.resolve()))
                self.assertTrue(Path(env['NRCU_CAPTURE_DIR']).is_relative_to(output.resolve()))
                self.assertNotIn('--headless', command)
                calls.append(command)
                return {'exit': 1 if len(calls) == 1 else 0, 'passed': len(calls) != 1, 'completion_count': 1}
            with patch.object(r, 'run_process', side_effect=child):
                results = r.run_suite('fixture', root, output, native=True)
            self.assertEqual(len(results), len(r.NATIVE_CONTRACTS))
            self.assertFalse(all(row['passed'] for row in results))
            with patch.object(r, 'run_suite', return_value=results), patch.object(sys, 'argv', ['runner', '--engine', 'fixture', '--project', str(root), '--output', str(output)]):
                self.assertEqual(r.main(), 1)
            with patch.object(r, 'CONTRACTS', r.CONTRACTS + [r.CONTRACTS[0]]):
                with self.assertRaisesRegex(ValueError, 'Duplicate'):
                    r.run_suite('fixture', root, output)
            with patch.object(r, 'CONTRACTS', [(r.CONTRACTS[0][0], None)]):
                with self.assertRaisesRegex(ValueError, 'missing completion'):
                    r.run_suite('fixture', root, output)

    def test_missing_contract_fails_without_engine(self):
        with tempfile.TemporaryDirectory(prefix='v06-runner-test-') as tmp:
            root = Path(tmp)
            (root / 'project.godot').write_text('; TEST FIXTURE')
            with self.assertRaises(ValueError):
                r.run_suite('nonexistent-engine', root, root / 'evidence', 1, False)


if __name__ == '__main__':
    unittest.main()

"""Portable runner self-tests; run with python tools/test_run_all_tests.py."""
import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).with_name('run_all_tests.py')

class RunnerTests(unittest.TestCase):
    def test_pass_requires_clean_full_output(self):
        self.assertTrue(MODULE.exists(), 'portable runner must exist')
        spec = importlib.util.spec_from_file_location('runner', MODULE)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        self.assertTrue(runner.classify('test_example', 0, 'PASS: example', '', False)['passed'])
        self.assertFalse(runner.classify('test_example', 0, 'PASS: example', 'SCRIPT ERROR: bad', False)['passed'])
        self.assertFalse(runner.classify('test_example', 0, 'ERROR: early\n' + 'x'*100000 + '\nPASS: example', '', False)['passed'])

    def test_exact_legacy_contracts_and_timeout(self):
        spec = importlib.util.spec_from_file_location('runner', MODULE)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        for name, marker in [('test_bobo_asset','BOBO_ASSET'), ('test_bobo_roster','BOBO_ROSTER'), ('test_bobo_story','BOBO_STORY'), ('test_story_combat','BOBO_INPUT')]:
            self.assertTrue(runner.classify(name, 0, marker + ' failures=0', '', False)['passed'])
            self.assertFalse(runner.classify(name, 0, marker + ' failures=1', '', False)['passed'])
        self.assertTrue(runner.classify('test_bobo_status', 0, '', '', False)['passed'])
        self.assertFalse(runner.classify('test_unknown', 0, '', '', False)['passed'])
        self.assertFalse(runner.classify('test_example', 1, 'PASS', '', False)['passed'])
        self.assertFalse(runner.classify('test_example', 0, 'PASS', '', True)['passed'])
        self.assertFalse(runner.classify('test_example', 0, 'PASS\nfailures=2', '', False)['passed'])

    def test_process_persistence_explicit_log_and_timeout(self):
        import sys
        import tempfile
        import json
        spec = importlib.util.spec_from_file_location('runner', MODULE)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        self.assertTrue(hasattr(runner, 'run_case'), 'subprocess runner required')
        (MODULE.parent.parent / '.verification').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=MODULE.parent.parent / '.verification') as directory:
            out = Path(directory)
            command = [sys.executable, '-c', "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text('SCRIPT ERROR: log-only failure'); print('PASS: fixture')", str(out / 'test_fixture.engine.log')]
            result = runner.run_case('test_fixture', command, out, 10)
            self.assertFalse(result['passed'])
            self.assertIn('log-only failure', result['engine_output'])
            self.assertEqual(json.loads((out / 'test_fixture.result.json').read_text())['passed'], False)
            result = runner.run_case('test_timeout', [sys.executable, '-c', "import time; print('started', flush=True); time.sleep(20)"], out, 0.2)
            self.assertTrue(result['timed_out'])
            self.assertIn('started', result['stdout'])

    def test_cli_discovery_and_output_confinement(self):
        import subprocess
        import sys
        import json
        process = subprocess.run([sys.executable, str(MODULE), '--engine', sys.executable, '--list'], capture_output=True, text=True)
        self.assertEqual(process.returncode, 0)
        self.assertIn('test_bobo_status', process.stdout)
        expected = sorted(p.stem for p in (MODULE.parent.parent / 'tests').glob('test_*.gd'))
        self.assertEqual(json.loads(process.stdout), expected)
        self.assertTrue(expected, 'test discovery must not be empty')
        process = subprocess.run([sys.executable, str(MODULE), '--engine', sys.executable, '--output', '..', '--list'], capture_output=True, text=True)
        self.assertNotEqual(process.returncode, 0)

if __name__ == '__main__':
    unittest.main(verbosity=2)

"""Temporary fake-engine TEST FIXTURES, not Godot gameplay evidence."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('runner', ROOT / 'tools/release_v05_runner.py')
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)


class RunnerTests(unittest.TestCase):
    def test_bounded_process_contract(self):
        with tempfile.TemporaryDirectory(prefix='v05-runner-test-') as tmp:
            log = Path(tmp) / 'fixture.log'
            for script, expected in [("print('V05_RELEASE_COMPLETE')", True),
                                     ("print('nothing')", False),
                                     ("print('V05_RELEASE_COMPLETE'); exit(1)", False),
                                     ("print('V05_RELEASE_COMPLETE'); print('ERROR: fixture')", False),
                                     ("print('V05_RELEASE_COMPLETE'); print('V05_RELEASE_COMPLETE')", False),
                                     ("import time; time.sleep(5)", False)]:
                with self.subTest(script=script):
                    result = r.run_process([sys.executable, '-c', script], log, 0.5, 'V05_RELEASE_COMPLETE')
                    self.assertEqual(result['passed'], expected)
            self.assertEqual(result['exit'], 124)

    def test_missing_contract_fails_without_engine(self):
        with tempfile.TemporaryDirectory(prefix='v05-runner-test-') as tmp:
            root = Path(tmp)
            (root / 'project.godot').write_text('; TEST FIXTURE')
            with self.assertRaises(ValueError):
                r.run_suite('nonexistent-engine', root, root / 'evidence', 1, False)


if __name__ == '__main__':
    unittest.main()

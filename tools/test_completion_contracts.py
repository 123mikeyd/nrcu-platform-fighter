import importlib.util,unittest
from pathlib import Path
p=Path(__file__).with_name('run_all_tests.py')
spec=importlib.util.spec_from_file_location('runner',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Contracts(unittest.TestCase):
 def test_inspected_terminal_success(self):
  self.assertTrue(m.classify('test_tumble_roster',0,'ROSTER_TUMBLE_COMPLETE checks=432 pairs=98 failures=0','',False)['passed'])
 def test_partial_rejected(self):
  self.assertFalse(m.classify('test_tumble_roster',0,'ROSTER_TUMBLE_COMPLETE checks=432 pairs=98 failures=1','',False)['passed'])
 def test_engine_error_rejected(self):
  self.assertFalse(m.classify('test_tumble_roster',0,'ROSTER_TUMBLE_COMPLETE checks=432 pairs=98 failures=0\nSCRIPT ERROR: interrupted','',False)['passed'])
 def test_unrecognized_marker_rejected(self):
  self.assertFalse(m.classify('unknown',0,'ROSTER_TUMBLE_COMPLETE checks=432 pairs=98 failures=0','',False)['passed'])
if __name__=='__main__':unittest.main()

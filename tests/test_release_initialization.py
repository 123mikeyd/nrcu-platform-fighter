"""Regression: release builds remove assertions, including their expressions."""
from pathlib import Path
import unittest,re
ROOT=Path(__file__).resolve().parents[1]
class ReleaseInitialization(unittest.TestCase):
 def test_weaver_initialization_survives_disabled_assertions(self):
  text=(ROOT/'current_game/scripts/weaver_gap_art.gd').read_text()
  release_lines=[line for line in text.splitlines() if not line.lstrip().startswith('assert(')]
  code='\n'.join(release_lines)
  self.assertRegex(code,r'(?m)^\s*(?:var\s+\w+\s*(?::[^=]+)?=\s*)?god\.setup\(self,\s*0\.8,\s*-2\.0\)', 'Required setup must execute outside debug-only assert')
if __name__=='__main__':unittest.main()

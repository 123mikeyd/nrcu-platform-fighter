"""Derived animation provenance must survive export remapping."""
import unittest
from pathlib import Path

class SwingExportTests(unittest.TestCase):
    def test_verifier_requires_portable_engine_argument(self):
        source = (Path(__file__).parent / 'verify_tek_swing_export.py').read_text()
        self.assertNotIn('/home/', source)
        self.assertIn("'--engine'", source)

    def test_raw_derived_animation_is_explicitly_packed(self):
        source = (Path(__file__).parent / 'export_core_lab.py').read_text()
        self.assertIn('"res://data/animation/teknium_swing_v1.tres"', source)

if __name__ == '__main__':
    unittest.main()

"""Real scene/input regression: Godot exit zero alone misses engine errors.

Run: python3 tests/test_core_combat_lab_navigation_output.py
Override the engine with GODOT if necessary.
"""
import os
from pathlib import Path
import re
import subprocess
import unittest


class CombatLabNavigationOutputTest(unittest.TestCase):
    def test_viewport_escape_has_clean_engine_output(self):
        project = Path(__file__).resolve().parents[1]
        result = subprocess.run(
            [os.environ.get("GODOT", "godot"), "--headless", "--path", str(project),
             "--fixed-fps", "60", "--script",
             "res://tests/test_core_combat_lab_navigation.gd"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90,
        )
        print(result.stdout, end="", flush=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIsNone(
            re.search(r"(?im)^.*\b(?:ERROR|WARNING|FAIL(?:ED)?)\s*:", result.stdout),
            result.stdout,
        )
        self.assertIn("PASS: combat lab UI navigation and cleanup", result.stdout)


if __name__ == "__main__":
    unittest.main()

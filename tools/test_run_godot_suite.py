"""Harness hygiene regression: windowed runs must leave no process behind.

- pass path: hygiene_quit_probe exits 0 -> runner rc 0, PID gone, no kill.
- timeout path: hygiene_hang_probe outlives the timeout -> runner rc 124,
  owned PID killed, PID gone afterwards.

Only exact owned PIDs are ever signalled (see run_godot_suite.py).
"""
import json
import subprocess
import sys

import run_godot_suite as runner


def _pid_gone(pid: int) -> bool:
    return not runner._alive(pid)


def main() -> int:
    failures = 0

    quick = runner.run("res://tests/hygiene_quit_probe_test.gd",
                       timeout=120, headless=True, extra=[])
    ok = (quick["rc"] == 0 and not quick["timed_out"]
          and _pid_gone(quick["pid"]))
    print("HYGIENE %s clean quit leaves no process (rc=%s)" %
          ("PASS" if ok else "FAIL", quick["rc"]))
    failures += 0 if ok else 1

    slow = runner.run("res://tests/hygiene_hang_probe_test.gd",
                      timeout=25, headless=True, extra=[])
    ok2 = (slow["rc"] == 124 and slow["timed_out"]
           and _pid_gone(slow["pid"]))
    print("HYGIENE %s timeout kills owned process, none lingers "
          "(rc=%s killed=%s)" % ("PASS" if ok2 else "FAIL",
                                 slow["rc"], slow["linger_killed"]))
    failures += 0 if ok2 else 1

    print("HYGIENE done failures=%d" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

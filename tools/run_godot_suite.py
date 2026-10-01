"""Run one Godot suite with guaranteed process teardown (harness hygiene).

START -> run -> evidence -> deterministic teardown -> process exit ->
verify no owned child remains. Applies to PASS, FAIL, crash, and timeout:
only processes started/owned by THIS runner are ever touched (exact PID,
never a global taskkill /IM).

Usage:
  python tools/run_godot_suite.py --script res://tests/foo_test.gd
      [--timeout 300] [--headless] [--extra-arg ...]

The CLI requires a `done ... checks=N failures=0` completion marker by
default and rejects parser/runtime markers even when Godot exits zero. Use
`--allow-no-marker` only for utility probes that intentionally have no suite
contract. It prints a metadata JSON line followed by the captured log.
Exit code mirrors the suite (124 on runner timeout; 1 on validation failure).
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

PROJECT = str(Path(__file__).resolve().parents[1])
ENGINE = os.environ.get("GODOT_ENGINE", "godot")


def _alive(pid: int) -> bool:
    if os.name == "nt":
        tasklist = shutil.which("tasklist") or "C:/Windows/System32/tasklist.exe"
        try:
            out = subprocess.run(
                [tasklist, "/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"],
                capture_output=True, text=True, timeout=15)
            return str(pid) in out.stdout
        except Exception:
            return False
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def _kill_tree(pid: int) -> None:
    # Exact-PID kill incl. owned children. The POSIX path uses a dedicated
    # process group; Windows uses taskkill with the owned PID and /T.
    if os.name == "nt":
        taskkill = shutil.which("taskkill") or "C:/Windows/System32/taskkill.exe"
        subprocess.run(
            [taskkill, "/F", "/T", "/PID", str(pid)],
            capture_output=True, timeout=30)
        return
    try:
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    except (OSError, ProcessLookupError):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def run(script: str, timeout: int, headless: bool, extra: list,
        engine: str = ENGINE, project: str = PROJECT) -> dict:
    cmd = [engine, "--path", project, "--script", script]
    if headless:
        cmd.insert(3, "--headless")
    else:
        cmd.append("--always-on-top")
    cmd.extend(extra)
    popen_kwargs = {}
    if os.name != "nt":
        popen_kwargs["start_new_session"] = True
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True,
                             **popen_kwargs)
    timed_out = False
    try:
        log, _ = proc.communicate(timeout=timeout)
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        log = ""
        try:
            part, _ = proc.communicate(timeout=5)
            log += part or ""
        except Exception:
            pass
        rc = 124
    finally:
        # Deterministic teardown: the owned PID must be gone afterwards.
        linger_killed = False
        if _alive(proc.pid):
            _kill_tree(proc.pid)
            linger_killed = True
            deadline = time.time() + 10
            while _alive(proc.pid) and time.time() < deadline:
                time.sleep(0.5)
        try:
            if proc.stdout:
                rest = proc.stdout.read()
                if rest:
                    log += rest
        except Exception:
            pass
    return {"rc": rc, "timed_out": timed_out, "linger_killed": linger_killed,
            "pid": proc.pid, "log": log or ""}


_COMPLETION_RE = re.compile(r"(?im)^.*\bdone\b.*\bchecks(?:=|\s+)[0-9]+.*\bfailures=([0-9]+)\b.*$")
_FATAL_RE = re.compile(
    r"(?im)^(?:.*(?:SCRIPT ERROR:|Parse Error:|Parser Error:|Invalid call\.|Cannot infer the type).*)$"
)


def validate_log(log: str, require_marker: bool = True) -> tuple[bool, str]:
    """Fail closed when a nominally-zero Godot child did not prove its suite."""
    if _FATAL_RE.search(log or ""):
        return False, "Godot log contains a script/parser/runtime error"
    markers = _COMPLETION_RE.findall(log or "")
    if require_marker and not markers:
        return False, "suite emitted no completion marker"
    if any(int(value) != 0 for value in markers):
        return False, "suite completion marker reports failures"
    return True, ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", required=True)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--engine", default=ENGINE,
                    help="Godot executable (default: GODOT_ENGINE or godot on PATH)")
    ap.add_argument("--project", default=PROJECT,
                    help="project directory (default: repository root)")
    ap.add_argument("--extra-arg", dest="extra_args", action="append", default=[],
                    help="Additional Godot argument; repeatable")
    ap.add_argument("extra", nargs="*",
                    help="Additional positional Godot arguments (legacy form)")
    ap.add_argument("--allow-no-marker", action="store_true",
                    help="Allow a utility script that does not emit a done/checks/failures marker")
    args = ap.parse_args()
    result = run(args.script, args.timeout, args.headless,
                 (args.extra_args or []) + (args.extra or []),
                 engine=args.engine, project=args.project)
    log = result["log"]
    if result["rc"] == 0:
        valid, reason = validate_log(log, require_marker=not args.allow_no_marker)
        if not valid:
            result["rc"] = 1
            result["validation_error"] = reason
    result.pop("log")
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.write(log)
    sys.stdout.write("RUNNER_RC=%d\n" % result["rc"])
    return result["rc"]


if __name__ == "__main__":
    sys.exit(main())

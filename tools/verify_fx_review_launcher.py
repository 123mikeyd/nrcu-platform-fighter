"""Windows native-window verification of the real persistent review launcher.
Only this verifier's spawned launchers/Godot PIDs are closed. No production data.
"""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from fx_review import PROJECT, SCENARIOS


def wait_for(predicate, timeout=40):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.1)
    raise AssertionError("verification wait expired")


def window_for(pid):
    user32 = ctypes.windll.user32
    found = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    @callback_type
    def visit(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        title = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(hwnd, title, 512)
        if owner.value == pid and user32.IsWindowVisible(hwnd) and title.value.startswith("NRCU FX"):
            found.append(hwnd)
        return True
    user32.EnumWindows(visit, 0)
    return found[0] if found else None


def post_key(hwnd, key):
    user32 = ctypes.windll.user32
    user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user32.PostMessageW(hwnd, 0x100, key, 0)
    user32.PostMessageW(hwnd, 0x101, key, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("Native window verifier requires Windows; launcher itself is cross-platform.")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    workspace = out / ("workspace_" + str(os.getpid()))
    results = []
    canonical = None
    for scenario, mode in [(s, "lab") for s in SCENARIOS] + [("CLASH_OVERDRIVE", "lab"), ("CLASH_OVERDRIVE", "game")]:
        data = workspace / scenario
        ready_path = data / "review_ready.json"
        ready_path.unlink(missing_ok=True)
        log_path = data / (mode + ".log")
        screenshot = out / (scenario + "_" + mode + ".png")
        env = os.environ.copy()
        env["NRCU_FX_REVIEW_CAPTURE"] = str(screenshot)
        command = [sys.executable, str(PROJECT / "tools/fx_review.py"), "--engine", args.engine, "--workspace", str(workspace), "--scenario", scenario, "--mode", mode]
        transcript = out / (scenario + "_" + mode + "_launcher.log")
        pid = None
        hwnd = None
        with transcript.open("w", encoding="utf-8") as stream:
            proc = subprocess.Popen(command, cwd=PROJECT, env=env, stdout=stream, stderr=subprocess.STDOUT)
            try:
                wait_for(lambda: ready_path.exists() or proc.poll() is not None)
                assert proc.poll() is None, transcript.read_text()
                ready = json.loads(ready_path.read_text(encoding="utf-8"))
                pid = ready["pid"]
                hwnd = wait_for(lambda: window_for(pid))
                assert ready["scenario"] == scenario and ready["mode"] == mode
                assert Path(ready["production"]).resolve() == data / "production"
                assert Path(ready["drafts"]).resolve() == data / "drafts"
                assert Path(ready["workspace"]).resolve() == data / "workspace.json"
                assert len(ready["composition"]["metadata"]["recipe_instances"]) == 1
                if mode == "lab":
                    assert ready["selected_target"] == "composition" and ready["apply_enabled"] and ready["preview_mounted"]
                else:
                    assert ready["runtime_summary"]["ok"] and not ready["preview_lifetime"]
                saved = (data / "production/composition.json").read_bytes()
                if scenario == "CLASH_OVERDRIVE":
                    if canonical is None:
                        canonical = saved
                    else:
                        assert saved == canonical, "reopening must not overwrite saved artist state"
                duplicate = subprocess.run(command, cwd=PROJECT, env=env, capture_output=True, text=True, timeout=10)
                assert duplicate.returncode == 2 and "already open" in duplicate.stderr, duplicate.stdout + duplicate.stderr
                if mode == "game":
                    for key, marker in [(ord("1"), "SEEK 0.29"), (ord("2"), "SEEK 0.45"), (ord("4"), "SEEK 1.11"), (ord("N"), "NEUTRAL true"), (ord("N"), "NEUTRAL false")]:
                        before = log_path.read_text(encoding="utf-8").count(marker)
                        post_key(hwnd, key)
                        wait_for(lambda: log_path.read_text(encoding="utf-8").count(marker) > before, 10)
                    post_key(hwnd, 0x74)  # F5: real playing entry, cover and exit
                    wait_for(lambda: "GAME_FINISHED" in log_path.read_text(encoding="utf-8"), 15)
                    assert proc.poll() is None, "game completion must not autoquit the review"
                    post_key(hwnd, ord("3"))  # new adapter after completed teardown
                    wait_for(lambda: log_path.read_text(encoding="utf-8").count("SEEK 0.81") >= 3, 10)
                time.sleep(2)
                assert proc.poll() is None and screenshot.is_file()
                assert (data / "production/composition.json").read_bytes() == saved
                ctypes.windll.user32.PostMessageW(hwnd, 0x10, 0, 0)  # WM_CLOSE, exact owned window
                assert proc.wait(timeout=15) == 0
                log = log_path.read_text(encoding="utf-8")
                assert not any(mark in log for mark in ("SCRIPT ERROR", "ERROR:", "WARNING:")), log
                result = {"scenario": scenario, "mode": mode, "pid": pid, "rc": proc.returncode, "ready": str(ready_path), "log": str(log_path), "screenshot": str(screenshot), "single_instance": True, "data_preserved": True}
                results.append(result)
                print("PASS", scenario, mode, "ready / persistent / isolated / single-instance / clean-close", flush=True)
            finally:
                if proc.poll() is None:
                    # Failure cleanup also stays exact-PID scoped.
                    if pid is None and (data / "launcher_session.json").exists():
                        pid = json.loads((data / "launcher_session.json").read_text())["pid"]
                    if pid is not None:
                        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
                    proc.terminate()
                    proc.wait(timeout=15)
                (out / "launcher_verification.json").write_text(json.dumps({"completed": len(results), "expected": 7, "results": results}, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

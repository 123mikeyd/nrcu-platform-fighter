"""Persistent, isolated FX review. No timeout, autoquit or production-tree writes.
Run: python tools/fx_review.py --scenario CLASH_OVERDRIVE [--mode game]
"""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
SCENARIOS = ("CLASH_OVERDRIVE", "VACUUM_CLASH", "KINETIC_RUSH", "DISTORTION_ONLY", "PATTERN_CUT")


def discover_engine(explicit=None):
    requested = explicit or os.environ.get("GODOT_BIN") or os.environ.get("GODOT_ENGINE")
    if requested:
        found = shutil.which(requested) or (str(Path(requested).expanduser().resolve()) if Path(requested).expanduser().is_file() else None)
        if not found:
            raise RuntimeError("Godot not found: set GODOT_BIN or pass --engine to a Godot 4.7 executable.")
        return found
    for folder in (PROJECT / "engine", PROJECT / "tools" / "engine"):
        for pattern in ("Godot*_console.exe", "Godot*.exe", "godot", "godot4", "Godot*"):
            for candidate in sorted(folder.glob(pattern)):
                if candidate.is_file() and os.access(candidate, os.X_OK):
                    return str(candidate)
    for name in ("godot", "godot4", "Godot"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError("Godot 4.7 not found. Put it in engine/, on PATH, set GODOT_BIN, or use --engine.")


def default_workspace():
    base = os.environ.get("LOCALAPPDATA") if os.name == "nt" else os.environ.get("XDG_DATA_HOME")
    return Path(base) / "NRCU-FX-Review" if base else Path.home() / ".local" / "share" / "NRCU-FX-Review"


@contextmanager
def single_instance(workspace):
    """OS-held lock: a crash releases it, and stale lock files are harmless."""
    workspace.mkdir(parents=True, exist_ok=True)
    with (workspace / "review.lock").open("a+b") as lock:
        lock.seek(0, 2)
        if lock.tell() == 0:
            lock.write(b"0")
            lock.flush()
        lock.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise RuntimeError("A review is already open in this workspace. Close it before switching scenario or mode.") from exc
        try:
            yield
        finally:
            lock.seek(0)
            if os.name == "nt":
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(lock, fcntl.LOCK_UN)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=SCENARIOS, default="CLASH_OVERDRIVE")
    parser.add_argument("--mode", choices=("lab", "game"), default="lab")
    parser.add_argument("--workspace", type=Path, default=default_workspace(), help="Isolated review data root; each scenario keeps its own edits")
    parser.add_argument("--engine", help="Godot executable; alternatively GODOT_BIN/GODOT_ENGINE, engine/ or PATH")
    args = parser.parse_args(argv)
    try:
        engine = discover_engine(args.engine)
        workspace = args.workspace.expanduser().resolve()
        # Review output must live outside the checkout. This protects the
        # source tree even when a user passes ./review, ./evidence, or a
        # symlink-resolved project subdirectory.
        try:
            workspace.relative_to(PROJECT)
        except ValueError:
            pass
        else:
            raise RuntimeError("Use a dedicated review workspace outside the project checkout.")
        with single_instance(workspace):
            data = workspace / args.scenario
            data.mkdir(parents=True, exist_ok=True)
            env = os.environ.copy()
            env.update({
                "NRCU_FX_DATA_DIR": (data / "production").as_posix(),
                "NRCU_FX_DRAFT_DIR": (data / "drafts").as_posix(),
                "NRCU_FX_WORKSPACE_PATH": (data / "workspace.json").as_posix(),
                "NRCU_FX_REVIEW_DIR": data.as_posix(),
                "NRCU_FX_REVIEW_SCENARIO": args.scenario,
                "NRCU_FX_REVIEW_MODE": args.mode,
            })
            for name in ("review_ready.json",):
                (data / name).unlink(missing_ok=True)
            log = data / (args.mode + ".log")
            command = [engine, "--path", str(PROJECT), "--windowed", "--resolution", "1280x720", "--log-file", str(log), "--script", "res://tools/fx_review.gd"]
            print("LOCAL ADAPTER REVIEW / UPSTREAM INTEGRATION PENDING", flush=True)
            print("Scenario:", args.scenario, " Mode:", args.mode, flush=True)
            print("Saved review data:", data, "\nLog:", log, flush=True)
            print("Close the window to stop. Reopening preserves your edits. No automatic exit.", flush=True)
            proc = subprocess.Popen(command, cwd=PROJECT, env=env)
            session = {"pid": proc.pid, "scenario": args.scenario, "mode": args.mode, "project": str(PROJECT), "workspace": str(data), "engine": engine, "log": str(log)}
            (data / "launcher_session.json").write_text(json.dumps(session, indent=2), encoding="utf-8")
            try:
                return proc.wait()
            except KeyboardInterrupt:
                # Only this launcher's child, never other Godot instances.
                proc.terminate()
                proc.wait()
                return 130
    except (OSError, RuntimeError) as exc:
        print("Review launch failed:", exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

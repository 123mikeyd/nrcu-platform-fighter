"""Drive tools/pause_live_probe.gd with REAL window mouse messages.

The probe runs the production route in a real window and reports where the
Pause items are. This driver finds that window and posts genuine
WM_MOUSEMOVE / WM_LBUTTONDOWN / WM_LBUTTONUP messages at the item centres, so
the pointer path under test is the engine's own Windows event loop -- not
Input.parse_input_event. Only the window this driver started is touched; the
user's physical pointer is never moved.

    python tools/pause_live_probe.py --engine <godot console exe> [--out <dir>]
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import json
import re
import subprocess
import threading
import time
from pathlib import Path

WM_MOUSEMOVE = 0x0200
WM_LBUTTONDOWN = 0x0201
WM_LBUTTONUP = 0x0202
WM_MOUSEACTIVATE = 0x0021

user32 = ctypes.windll.user32


def make_lparam(x: int, y: int) -> int:
    return (y << 16) | (x & 0xFFFF)


def process_tree(pid: int) -> set:
    """The pid plus every descendant process (the console launcher spawns the
    engine as a child, so its window is not owned by the launcher pid)."""
    TH32CS_SNAPPROCESS = 0x00000002
    kernel32 = ctypes.windll.kernel32

    class PROCESSENTRY32(ctypes.Structure):
        _fields_ = [('dwSize', wt.DWORD), ('cntUsage', wt.DWORD),
                    ('th32ProcessID', wt.DWORD),
                    ('th32DefaultHeapID', ctypes.POINTER(ctypes.c_ulong)),
                    ('th32ModuleID', wt.DWORD), ('cntThreads', wt.DWORD),
                    ('th32ParentProcessID', wt.DWORD),
                    ('pcPriClassBase', ctypes.c_long), ('dwFlags', wt.DWORD),
                    ('szExeFile', ctypes.c_char * 260)]

    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == -1:
        return {pid}
    entry = PROCESSENTRY32()
    entry.dwSize = ctypes.sizeof(PROCESSENTRY32)
    parents = {}
    if kernel32.Process32First(snapshot, ctypes.byref(entry)):
        while True:
            parents[entry.th32ProcessID] = entry.th32ParentProcessID
            if not kernel32.Process32Next(snapshot, ctypes.byref(entry)):
                break
    kernel32.CloseHandle(snapshot)
    tree = {pid}
    changed = True
    while changed:
        changed = False
        for child, parent in parents.items():
            if parent in tree and child not in tree:
                tree.add(child)
                changed = True
    return tree


def find_window(pids: set, timeout: float):
    # ONLY a visible top-level window owned by the process tree this driver
    # started: other Godot windows on the desktop (the user's own sessions) are
    # never touched, whatever they are titled.
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = []

        @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
        def enum_proc(hwnd, _lparam):
            owner = wt.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            if owner.value not in pids or not user32.IsWindowVisible(hwnd):
                return True
            length = user32.GetWindowTextLengthW(hwnd)
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            found.append((hwnd, buf.value))
            return True

        user32.EnumWindows(enum_proc, 0)
        if found:
            return found[0]
        time.sleep(0.25)
    return None


def post_move(hwnd, x: int, y: int):
    user32.PostMessageW(hwnd, WM_MOUSEMOVE, 0, make_lparam(x, y))


def post_click(hwnd, x: int, y: int, hold: float = 0.08):
    lp = make_lparam(x, y)
    post_move(hwnd, x, y)
    time.sleep(hold)
    user32.PostMessageW(hwnd, WM_LBUTTONDOWN, 1, lp)
    time.sleep(hold)
    user32.PostMessageW(hwnd, WM_LBUTTONUP, 0, lp)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True)
    parser.add_argument('--out', default='.verification/evidence/pause-live')
    parser.add_argument('--timeout', type=float, default=120.0)
    args = parser.parse_args()

    project = Path(__file__).resolve().parent.parent
    out_dir = (project / args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    log_path = out_dir / 'pause_live_probe.stdout.log'

    command = [str(Path(args.engine).resolve()), '--path', str(project),
               '--resolution', '1280x720', '--quit-after', '7200',
               'res://tools/pause_live_probe.tscn']
    print('driver: launching ' + ' '.join(command), flush=True)
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True,
                               encoding='utf-8', errors='replace')
    lines = []
    state = {'resume': None, 'leave': None, 'phase_a': False, 'phase_b': False,
             'a_fired': False, 'b_fired': False, 'done': False}
    lock = threading.Lock()

    def reader():
        assert process.stdout is not None
        for line in process.stdout:
            line = line.rstrip('\n')
            with lock:
                lines.append(line)
                log_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            print('probe: ' + line, flush=True)
            m = re.search(r'RESUME_CENTER=([\d.]+),([\d.]+) LEAVE_CENTER=([\d.]+),([\d.]+)', line)
            if m:
                state['resume'] = (float(m.group(1)), float(m.group(2)))
                state['leave'] = (float(m.group(3)), float(m.group(4)))
            if 'PHASE_A_READY' in line:
                state['phase_a'] = True
            if 'PHASE_B_READY' in line:
                state['phase_b'] = True
            if 'A_ACTION_FIRED' in line:
                state['a_fired'] = True
            if 'B_ACTION_FIRED' in line:
                state['b_fired'] = True
            if 'PROBE: DONE' in line:
                state['done'] = True

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()

    window = find_window(process_tree(process.pid), args.timeout)
    if window is None:
        print('driver: FAILED window not found for pid %d' % process.pid, flush=True)
        process.kill()
        return 1
    hwnd, title = window
    rect = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    print('driver: window="%s" client=%dx%d' % (title, rect.right, rect.bottom), flush=True)

    deadline = time.time() + args.timeout
    while (state['resume'] is None or state['leave'] is None) and time.time() < deadline \
            and process.poll() is None:
        time.sleep(0.2)
    # Never post input when the probe never reported the item geometry.
    if state['resume'] is None or state['leave'] is None:
        print('driver: FAILED no item geometry reported; not posting any input', flush=True)
        process.kill()
        return 1

    deadline = time.time() + args.timeout
    while not state['phase_a'] and time.time() < deadline:
        time.sleep(0.2)
    rx, ry = state['resume'] or (0.0, 0.0)
    lx, ly = state['leave'] or (0.0, 0.0)

    def wait_for(flag: str, limit: float) -> bool:
        end = time.time() + limit
        while not state[flag] and process.poll() is None and time.time() < end:
            time.sleep(0.2)
        return bool(state[flag])

    # Phase A: real hover over both items, then a real click on RESUME.
    post_move(hwnd, int(rx), int(ry))
    time.sleep(0.6)
    post_move(hwnd, int(lx), int(ly))
    time.sleep(0.6)
    post_move(hwnd, int(rx), int(ry))
    time.sleep(0.6)
    print('driver: real left-click on RESUME (%.0f,%.0f)' % (rx, ry), flush=True)
    post_click(hwnd, int(rx), int(ry))
    wait_for('a_fired', 25.0)

    # Phase B: the probe re-opened Pause; hover both again, then click LEAVE.
    wait_for('phase_b', 20.0)
    time.sleep(0.5)
    post_move(hwnd, int(rx), int(ry))
    time.sleep(0.5)
    post_move(hwnd, int(lx), int(ly))
    time.sleep(0.5)
    print('driver: real left-click on LEAVE (%.0f,%.0f)' % (lx, ly), flush=True)
    post_click(hwnd, int(lx), int(ly))
    wait_for('b_fired', 25.0)

    wait_for('done', 25.0)
    observed = bool(state['a_fired'] and state['b_fired'] and state['done'])
    if process.poll() is None:
        time.sleep(1.0)   # let the probe's own quit() land before any kill
    if process.poll() is None:
        process.kill()
    process.wait()
    print('driver: observed_all=%s probe_exit=%s a_fired=%s b_fired=%s done=%s' % (
        observed, process.returncode, state['a_fired'], state['b_fired'], state['done']), flush=True)
    (out_dir / 'pause_live_probe.summary.json').write_text(
        json.dumps({'observed_all': observed, 'probe_exit': process.returncode,
                    'a_fired': state['a_fired'], 'b_fired': state['b_fired'],
                    'done': state['done'], 'lines': lines}, indent=2) + '\n',
        encoding='utf-8')
    return 0 if observed else 1


if __name__ == '__main__':
    raise SystemExit(main())

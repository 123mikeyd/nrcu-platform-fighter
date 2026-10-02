"""Bounded nested-project import and v0.6 integration contract runner.

Evidence is private: keep --output outside the repo or under .verification.
A zero exit without exactly one completion marker per contract is NOT success.
The only tolerated ERROR text is the headless dummy-renderer line
'Parameter "material" is null' (plus its following "at:" line); any other ERROR fails.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess


# Headless dummy-renderer noise (engine-side, no script source); the only tolerated ERROR.
NOISE = re.compile(r'^ERROR: Parameter "material" is null\.[ \t]*\r?\n[ \t]*at: material_get_instance_shader_parameters \(servers/rendering/dummy/[^\n]*\n?', re.MULTILINE)


def run_process(command, log, timeout, marker=None):
    if timeout <= 0 or timeout > 1800:
        raise ValueError('Timeout must be within (0, 1800] seconds')
    with Path(log).open('w', encoding='utf-8') as stream:
        proc = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                start_new_session=os.name != 'nt')
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True, timeout=15)
            else:
                os.killpg(proc.pid, signal.SIGKILL)
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=15)
            code = 124
    text = Path(log).read_text(encoding='utf-8', errors='replace')
    markers = sum(line.strip() == marker for line in text.splitlines()) if marker else 0
    scrubbed = re.sub(NOISE, '', text)
    passed = code == 0 and not re.search(r'SCRIPT ERROR:|ERROR:|FAIL(?:[: ]|$)', scrubbed, re.MULTILINE)
    if marker:
        passed = passed and markers == 1
    return {'exit': code, 'passed': passed, 'completion_count': markers}


CONTRACTS = [('test_v06_release', 'V06_RELEASE_COMPLETE'),
             ('test_v06_worlds', 'V06_WORLDS_COMPLETE'),
             ('test_v06_contact_lifecycle', 'V06_CONTACT_COMPLETE'),
             ('test_v06_mobile', 'V06_MOBILE_COMPLETE'),
             ('test_v06_touch_pause', 'V06_TOUCH_PAUSE_COMPLETE'),
             ('test_mobile_touch', 'PASS mobile touch'),
             # Ported live tests: they report through exit code + FAIL lines (no marker).
             ('test_ledge_grab', None),
             ('test_unlocks_gauntlet', None),
             ('test_heavy_bag', None),
             ('test_story_glowup', None)]


def run_suite(engine, project, output, timeout=180, fresh_import=False):
    project, output = Path(project).resolve(), Path(output).resolve()
    if not (project / 'project.godot').is_file() or not all((project / 'tests' / (name + '.gd')).is_file() for name, _ in CONTRACTS):
        raise ValueError('Missing project or a required tests/test_v06_*.gd contract; no tests skipped')
    if output.is_relative_to(project):
        raise ValueError('Keep runner evidence outside the game project')
    output.mkdir(parents=True, exist_ok=True)
    results = []
    if fresh_import:
        results.append({'step': 'import', **run_process(
            [engine, '--headless', '--path', str(project), '--editor', '--import'],
            output / 'import.log', timeout)})
    if not results or results[-1]['passed']:
        for name, marker in CONTRACTS:
            results.append({'step': name, **run_process(
                [engine, '--headless', '--path', str(project), '--script', 'res://tests/%s.gd' % name],
                output / (name + '.log'), timeout, marker)})
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True)
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--timeout', type=float, default=180, help='Per-process bound in seconds, max 1800')
    parser.add_argument('--import-project', action='store_true', help='Run bounded import before tests; use a fresh checkout in CI')
    args = parser.parse_args()
    try:
        results = run_suite(args.engine, args.project, args.output, args.timeout, args.import_project)
        print(json.dumps(results))
        return 0 if all(r['passed'] for r in results) else 1
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        parser.exit(1, 'v0.6 contract failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())

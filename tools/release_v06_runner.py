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


def run_process(command, log, timeout, marker=None, env=None):
    if timeout <= 0 or timeout > 1800:
        raise ValueError('Timeout must be within (0, 1800] seconds')
    with Path(log).open('w', encoding='utf-8') as stream:
        proc = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                start_new_session=os.name != 'nt', env=env)
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
    passed = code == 0 and not re.search(r'SCRIPT ERROR:|ERROR:|FAIL(?:[: ]|$)|WARNING:[^\n]*ObjectDB[^\n]*leaked|Leaked instance:', scrubbed, re.MULTILINE)
    if marker:
        passed = passed and markers == 1
    return {'exit': code, 'passed': passed, 'completion_count': markers}


CONTRACTS = [('test_v06_release', 'V06_RELEASE_COMPLETE'),
             ('test_v06_worlds', 'V06_WORLDS_COMPLETE'),
             ('test_v06_contact_lifecycle', 'V06_CONTACT_COMPLETE'),
             ('test_v06_mobile', 'V06_MOBILE_COMPLETE'),
             ('test_v06_touch_pause', 'V06_TOUCH_PAUSE_COMPLETE'),
             ('test_mobile_touch', 'PASS mobile touch'),
             ('test_ledge_grab', 'LEDGE_GRAB_COMPLETE'),
             ('test_unlocks_gauntlet', 'UNLOCKS_GAUNTLET_COMPLETE'),
             ('test_heavy_bag', 'HEAVY_BAG_COMPLETE'),
             ('test_story_glowup', 'STORY_GLOWUP_COMPLETE'),
             ('test_bobo_down_air', 'BOBO_DOWN_AIR_COMPLETE'),
             ('test_costume_integration', 'COSTUME_INTEGRATION_COMPLETE'),
             ('test_doge_super_punch', 'SUPER_DOGE_COMPLETE'),
             ('test_tek_polish_lifecycle', 'TEK_POLISH_LIFECYCLE_COMPLETE'),
             ('test_turbofit_victory_loop', 'TURBO_VICTORY_COMPLETE'),
             ('test_v069420_frontend', 'V069420_FRONTEND_COMPLETE'),
             ('test_v069420_early_exit', 'V069420_EARLY_EXIT_COMPLETE'),
             ('test_v069420_help', 'V069420_HELP_COMPLETE'),
             ('test_witcheer_cane_airborne', 'WITCHEER_CANE_AIRBORNE_COMPLETE'),
             ('test_witcheer_poke_lifecycle', 'WITCHEER_POKE_LIFECYCLE_COMPLETE')]

# Native rendering remains a separate required local gate, not headless evidence.
NATIVE_CONTRACTS = [item for item in CONTRACTS if item[0] in
                    ('test_v069420_frontend', 'test_v069420_help', 'test_v069420_early_exit')]


def run_suite(engine, project, output, timeout=180, fresh_import=False, native=False):
    project, output = Path(project).resolve(), Path(output).resolve()
    if not (project / 'project.godot').is_file() or not all((project / 'tests' / (name + '.gd')).is_file() for name, _ in CONTRACTS):
        raise ValueError('Missing project or a required tests/test_v06_*.gd contract; no tests skipped')
    if output.is_relative_to(project):
        raise ValueError('Keep runner evidence outside the game project')
    output.mkdir(parents=True, exist_ok=True)
    results = []
    contracts = NATIVE_CONTRACTS if native else CONTRACTS
    if len({name for name, _ in contracts}) != len(contracts) or not all(marker for _, marker in contracts):
        raise ValueError('Duplicate contract or missing completion marker')
    def record(row):
        results.append(row)
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(row), flush=True)
    def environment(name):
        sink = output / name
        sink.mkdir(exist_ok=True)
        env = os.environ.copy()
        for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
            env[key] = str(sink / key.lower())
            Path(env[key]).mkdir(exist_ok=True)
        for key in ('NRCU_CAPTURE_DIR', 'VICTORY_CAPTURE_DIR', 'LEDGE_TEST_OUT'):
            env[key] = str(sink)
        return env
    if fresh_import:
        record({'step': 'import', **run_process(
            [engine, '--headless', '--path', str(project), '--editor', '--import'],
            output / 'import.log', timeout, env=environment('import'))})
    if not results or results[-1]['passed']:
        for name, marker in contracts:
            mode = ['--rendering-method', 'gl_compatibility', '--position', '-2400,-2400', '--resolution', '1280x720'] if native else ['--headless']
            record({'step': name, 'mode': 'native' if native else 'headless', **run_process(
                [engine, *mode, '--path', str(project), '--verbose', '--script', 'res://tests/%s.gd' % name],
                output / (name + '.log'), timeout, marker, environment(name))})
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True)
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--timeout', type=float, default=180, help='Per-process bound in seconds, max 1800')
    parser.add_argument('--import-project', action='store_true', help='Run bounded import before tests; use a fresh checkout in CI')
    parser.add_argument('--native', action='store_true', help='Required local rendered frontend/Help gate; separate from headless CI')
    args = parser.parse_args()
    try:
        results = run_suite(args.engine, args.project, args.output, args.timeout, args.import_project, args.native)
        print(json.dumps(results))
        return 0 if all(r['passed'] for r in results) else 1
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        parser.exit(1, 'v0.6 contract failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())

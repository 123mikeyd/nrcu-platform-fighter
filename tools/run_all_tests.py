"""Run the project's independent Godot tests with strict, persistent logs."""
import re
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def run_case(name, command, output, timeout):
    output.mkdir(parents=True, exist_ok=True)
    engine_log = output / (name + '.engine.log')
    stdout_path = output / (name + '.stdout.log')
    # Never classify a stale engine log from an earlier run.
    engine_log.unlink(missing_ok=True)
    started = time.monotonic()
    timed_out = False
    with stdout_path.open('wb') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            if process.poll() is None:
                process.kill()
            returncode = process.wait()
    stdout = stdout_path.read_text(encoding='utf-8', errors='replace')
    log = engine_log.read_text(encoding='utf-8', errors='replace') if engine_log.exists() else ''
    result = classify(name, returncode, stdout, log, timed_out)
    if '--log-file' in command and not engine_log.exists():
        result['passed'] = False
        result['errors'].append('Explicit engine log was not created')
    result.update(name=name, command=command, seconds=round(time.monotonic()-started, 3),
                  stdout=stdout, engine_output=log, stdout_log=str(stdout_path), engine_log=str(engine_log))
    write_json(output / (name + '.result.json'), result)
    return result

ERROR = re.compile(r'\b(?:SCRIPT ERROR|ERROR|FAIL(?:ED)?|Parse Error|Compile Error)\s*:', re.I)

def classify(name, returncode, stdout, log, timed_out):
    text = stdout + '\n' + log
    errors = [line for line in text.splitlines() if ERROR.search(line)]
    legacy = {'test_bobo_asset': 'BOBO_ASSET', 'test_bobo_roster': 'BOBO_ROSTER',
              'test_bobo_story': 'BOBO_STORY', 'test_story_combat': 'BOBO_INPUT'}
    # test_bobo_status has no success print: its final quit(1 if failures else 0)
    # is the inspected contract. Do not generalize this to unknown runners.
    marker = bool(re.search(r'(?m)^PASS\b', text))
    # Inspected completion contracts; fixed totals reject partial matrices.
    complete = {
        'test_tumble_roster': 'ROSTER_TUMBLE_COMPLETE checks=432 pairs=98 failures=0',
        'test_tumble_roster_routes': 'ROSTER_NATIVE_ROUTES_COMPLETE rows=26 failures=0',
        'test_mephisto_paired_body': 'PAIRED_BODY_COMPLETE failures=0',
        'test_mephisto_paired_form': 'PAIRED_FORM_COMPLETE failures=0',
        'test_mephisto_paired_combat': 'PAIRED_COMBAT_COMPLETE checks=18 failures=0',
        'test_mephisto_paired_lifecycle': 'PAIRED_LIFECYCLE_COMPLETE checks=112 failures=0',
        'test_mephisto_paired_contacts': 'PAIRED_GROUND_MATRIX_COMPLETE rows=96 failures=0',
        'test_mephisto_paired_air': 'PAIRED_AIR_COMPLETE failures=0',
        'test_mephisto_paired_antiair': 'PAIRED_ANTI_AIR_COMPLETE rows=10 failures=0',
    }
    if name in complete:
        marker = complete[name] in text.splitlines()
    if name in legacy:
        marker = bool(re.search(r'(?m)^' + legacy[name] + r' failures=0\s*$', text))
    elif name in {'test_bobo_status', 'project_smoke', 'clean_import'}:
        marker = True
    errors += [line for line in text.splitlines()
               if re.search(r'\bfailures\s*[=:]\s*[1-9]\d*', line, re.I)]
    return {'passed': returncode == 0 and not timed_out and not errors and marker,
            'returncode': returncode, 'timed_out': timed_out,
            'success_contract_met': marker, 'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True, help='Godot console executable')
    parser.add_argument('--output', default='.verification', help='Log/report directory inside this project')
    parser.add_argument('--only', nargs='+', help='Exact test stems or filenames (no globbing)')
    parser.add_argument('--timeout', type=float, default=180, help='Seconds per test')
    parser.add_argument('--list', action='store_true', help='List selected runners without executing')
    parser.add_argument('--import-only', action='store_true', help='Import project and stop; never deletes caches')
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    output = (project / args.output).resolve()
    verification = project / '.verification'
    if not output.is_relative_to(verification) or output == project:
        parser.error('--output must be .verification or a subdirectory (no external writes)')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    runners = sorted((project / 'tests').glob('test_*.gd'))
    if args.only:
        requested = {Path(name).stem for name in args.only}
        missing = requested - {p.stem for p in runners}
        if missing:
            parser.error('Unknown tests: ' + ', '.join(sorted(missing)))
        runners = [p for p in runners if p.stem in requested]
    if not runners:
        parser.error('No tests discovered')
    if args.list:
        print(json.dumps([p.stem for p in runners]))
        return 0
    engine = Path(args.engine).resolve()
    if not engine.is_file():
        parser.error('Engine executable not found')
    output.mkdir(parents=True, exist_ok=True)
    verification.mkdir(exist_ok=True)
    (verification / '.gdignore').touch()
    # Literal output destinations are reviewed res:// paths. Both direct file
    # paths and OUT directory constants are created, including inherited tests.
    for folder in ['tests', 'tools']:
        for script in (project / folder).glob('*.gd'):
            for literal in re.findall(r'''["'](res://\.verification/evidence/[^"']*)["']''', script.read_text(encoding='utf-8')):
                target = (project / literal.removeprefix('res://')).resolve()
                if not target.is_relative_to(verification / 'evidence'):
                    parser.error('Unsafe evidence path: ' + literal)
                (target if literal.endswith('/') else target.parent).mkdir(parents=True, exist_ok=True)
    os.chdir(project)
    def command(name, extra):
        return [str(engine), '--headless', '--path', str(project), '--log-file',
                str(output / (name + '.engine.log'))] + extra
    if args.import_only:
        result = run_case('clean_import', command('clean_import', ['--editor', '--import']), output, max(args.timeout, 600))
        print(json.dumps({k:result[k] for k in ['name','passed','returncode','seconds','errors']}), flush=True)
        return 0 if result['passed'] else 1
    report = {'discovered': len(list((project/'tests').glob('test_*.gd'))),
              'selected': [p.stem for p in runners], 'complete': False, 'results': [], 'smoke': None}
    write_json(output / 'report.json', report)
    for index, script in enumerate(runners, 1):
        result = run_case(script.stem, command(script.stem, ['--fixed-fps', '60', '--script',
                          'res://tests/' + script.name]), output, args.timeout)
        report['results'].append(result)
        report['passed'] = sum(r['passed'] for r in report['results'])
        report['failed'] = len(report['results']) - report['passed']
        write_json(output / 'report.json', report)
        print(f"{index}/{len(runners)} {script.stem}: {'PASS' if result['passed'] else 'FAIL'} ({result['seconds']}s)", flush=True)
    report['smoke'] = run_case('project_smoke', command('project_smoke', ['--fixed-fps', '60', '--quit-after', '120']), output, args.timeout)
    report['complete'] = len(report['results']) == len(runners)
    write_json(output / 'report.json', report)
    print(json.dumps({'report': str(output / 'report.json'), 'passed': report['passed'],
                      'failed': report['failed'], 'smoke_passed': report['smoke']['passed']}), flush=True)
    return 0 if report['failed'] == 0 and report['smoke']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

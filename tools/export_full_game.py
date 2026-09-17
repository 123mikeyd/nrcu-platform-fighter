"""Export a disposable authenticated snapshot to a new local-only directory.

First run portable_snapshot.py and its tests. No publication or source recopy.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

try:
    from tools.portable_snapshot import ENGINE_VERSION, check_ancestors
    from tools.raw_resource_packaging import install
    from tools.export_core_lab import run_checked
except ModuleNotFoundError:
    from portable_snapshot import ENGINE_VERSION, check_ancestors
    from raw_resource_packaging import install
    from export_core_lab import run_checked


def full_game_entry(text):
    original = 'run/main_scene="res://scenes/home.tscn"'
    if text.count(original) != 1:
        raise ValueError('Expected original home entry in disposable snapshot')
    return text.replace(original, 'run/main_scene="res://scenes/experimental_full_game.tscn"')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--engine', required=True)
    args = parser.parse_args()
    engine = shutil.which(args.engine)
    if not engine or subprocess.check_output([engine, '--version'], text=True).strip() != ENGINE_VERSION:
        parser.error('Required engine: ' + ENGINE_VERSION)
    for path in [args.stage.absolute(), args.output.absolute()]:
        check_ancestors(path)
    stage, output = args.stage.resolve(), args.output.resolve()
    if output.exists() or output == stage or output.is_relative_to(stage) or stage.is_relative_to(output):
        parser.error('Output must be a new directory separate from stage')
    # Installer authenticates project/raw bytes before modifying the disposable
    # project. Read the raw manifest from that same authenticated inventory.
    inventory = json.loads((stage / '.verification/snapshot/inputs.json').read_text())
    manifest_path = 'docs/manifests/pr-portability-raw.json'
    check_ancestors(stage / manifest_path)
    raw_bytes = (stage / manifest_path).read_bytes()
    if hashlib.sha256(raw_bytes).hexdigest() != inventory['files'].get(manifest_path):
        raise ValueError('Raw manifest is not authenticated snapshot input')
    full_game_entry((stage / 'project.godot').read_text())
    install(stage, json.loads(raw_bytes)['files'])
    project = stage / 'project.godot'
    temporary = stage / '.full-game-project.tmp'
    with temporary.open('x') as stream:
        stream.write(full_game_entry(project.read_text()))
    os.replace(temporary, project)
    output.mkdir(parents=True)
    logs = stage / '.verification/full-game-export'
    logs.mkdir()
    common = [engine, '--headless', '--path', str(stage)]
    run_checked(common + ['--editor', '--import'], logs / 'import.log')
    run_checked(common + ['--export-release', 'Web LAN', str(output / 'index.html')], logs / 'export.log')
    files = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
             for p in sorted(output.iterdir()) if p.is_file()}
    (logs / 'candidate.json').write_text(json.dumps({'engine': ENGINE_VERSION, 'local_only': True,
        'main_scene': 'res://scenes/experimental_full_game.tscn', 'files': files}, indent=2) + '\n')
    print(json.dumps(files, indent=2))

if __name__ == '__main__':
    main()

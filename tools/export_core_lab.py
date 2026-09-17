"""Export the isolated P0-P2 movement candidate without changing the legacy game.

Run: python3 tools/export_core_lab.py --engine /absolute/path/to/godot
Output: builds/core-lab/index.html; logs: .verification/core/export/
The existing builds/web release and source project.godot are never modified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


COPY_FOLDERS = ['assets', 'scripts', 'scenes', 'tools', 'data']


def validate_path(path: Path, recursive: bool = False) -> Path:
    """Reject aliases before resolving; never follow writable symlinks/hardlinks.

    This is a local preflight, not protection against concurrent hostile renames.
    """
    path = path.expanduser().absolute()
    if '..' in path.parts:
        raise ValueError('Refusing parent traversal: ' + str(path))
    for item in [*reversed(path.parents), path]:
        if item.is_symlink():
            raise ValueError('Refusing symlink: ' + str(item))
        if item.exists() and item.is_file() and item.stat().st_nlink > 1:
            raise ValueError('Refusing hardlink: ' + str(item))
    if recursive and path.is_dir():
        for child in path.iterdir():
            validate_path(child, recursive=True)
    return path


def validate_project_paths(source: Path, target: Path) -> tuple[Path, Path]:
    source = validate_path(source)
    target = validate_path(target, recursive=True)
    protected = [source / folder for folder in COPY_FOLDERS] + [source / 'builds/web']
    if source == target or source.is_relative_to(target) or any(
            target == item or target.is_relative_to(item) or item.is_relative_to(target)
            for item in protected):
        raise ValueError('Staging must be separate from source inputs and legacy release')
    for name in COPY_FOLDERS + ['project.godot', 'export_presets.cfg']:
        validate_path(source / name, recursive=True)
    return source, target


def prepare_project(source: Path, target: Path) -> None:
    source, target = validate_project_paths(source, target)
    target.mkdir(parents=True, exist_ok=True)
    cache = target / '.godot'
    if cache.is_symlink():
        raise ValueError('Refusing symlinked staging cache')
    if cache.exists():
        # Fresh source sidecars can change IDs; old binary scene exports may retain
        # stale UIDs even when the scene text itself has not changed.
        shutil.rmtree(cache)
    for folder in COPY_FOLDERS:
        destination = target / folder
        if destination.is_symlink():
            raise ValueError('Refusing symlink in staging: ' + str(destination))
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source / folder, destination,
                        ignore=shutil.ignore_patterns('__pycache__'))
    text = (source / 'project.godot').read_text(encoding='utf-8')
    original = 'run/main_scene="res://scenes/home.tscn"'
    if original not in text:
        raise ValueError('Unexpected source main scene; review exporter before continuing')
    text = text.replace(original, 'run/main_scene="res://scenes/training_lab.tscn"')
    text = text.replace('config/name="NRCU Platform Fighter"', 'config/name="NRCU Movement Lab"')
    if 'common/physics_ticks_per_second=' not in text:
        text = text.replace('[physics]', '[physics]\n\ncommon/physics_ticks_per_second=60')
    (target / 'project.godot').write_text(text, encoding='utf-8')
    shutil.copy2(source / 'export_presets.cfg', target / 'export_presets.cfg')
    # include_filter does not preserve raw imported GLBs. An export-only plugin
    # adds original bytes alongside their normal imported scenes, without remap.
    plugin = target / 'addons/collision_raw_export'
    plugin.mkdir(parents=True, exist_ok=True)
    (plugin / 'plugin.cfg').write_text('[plugin]\nname="Collision raw provenance"\ndescription="Pack immutable collision source bytes"\nauthor="NRCU"\nversion="1"\nscript="plugin.gd"\n')
    (plugin / 'plugin.gd').write_text('''@tool
extends EditorPlugin
var exporter = preload("export.gd").new()
func _enter_tree(): add_export_plugin(exporter)
func _exit_tree(): remove_export_plugin(exporter)
''')
    (plugin / 'export.gd').write_text('''@tool
extends EditorExportPlugin
func _get_name(): return "CollisionRawProvenance"
func _export_begin(_features, _debug, _path, _flags):
    for path in ["res://assets/teknium/teknium_animations.glb", "res://assets/turbofit/turbofit_animations.glb", "res://data/animation/teknium_swing_v1.tres"]:
        add_file(path, FileAccess.get_file_as_bytes(path), false)
''')
    text += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/collision_raw_export/plugin.cfg")\n'
    (target / 'project.godot').write_text(text, encoding='utf-8')


def run_checked(command: list[str], log: Path) -> None:
    validate_path(log)
    with log.open('w', encoding='utf-8') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=600, check=False)
    text = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode or 'ERROR:' in text or 'SCRIPT ERROR' in text:
        raise RuntimeError(f'Engine step failed ({result.returncode}); inspect {log}')
    print(f'PASS: {log.name}', flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True)
    args = parser.parse_args()
    engine = Path(args.engine).expanduser().resolve()
    if not engine.is_file():
        parser.error('Engine executable not found')
    root = validate_path(Path(__file__).absolute()).parent.parent
    staging = root / '.verification/core/export-project'
    output = root / 'builds/core-lab'
    logs = root / '.verification/core/export'
    # Validate ALL engine write trees and exact log destinations before any mutation.
    validate_project_paths(root, staging)
    validate_path(output, recursive=True)
    validate_path(logs, recursive=True)
    for name in ['import.log', 'export.log', 'artifact-manifest.json']:
        validate_path(logs / name)
    validate_path(output / 'index.html')
    output.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    prepare_project(root, staging)
    common = [str(engine), '--headless', '--path', str(staging)]
    run_checked(common + ['--editor', '--import'], logs / 'import.log')
    run_checked(common + ['--export-release', 'Web LAN', str(output / 'index.html')],
                logs / 'export.log')
    files = {}
    for path in sorted(output.iterdir()):
        if path.is_file():
            with path.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            files[path.name] = {'bytes': path.stat().st_size, 'sha256': digest}
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    manifest = {'engine': version, 'main_scene': 'res://scenes/training_lab.tscn',
                'milestone': 'P0-P2 candidate; P2 human-feel gate pending', 'files': files}
    (logs / 'artifact-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Candidate: ' + str(output / 'index.html'))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

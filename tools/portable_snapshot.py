"""Copy an explicit source manifest into a new cache-free directory; never export."""
import argparse
import hashlib
import json
from pathlib import Path
import unicodedata
import shutil
import subprocess
import sys
import tempfile

ENGINE_VERSION = '4.7.2.stable.official.ed1daf0bf'
FORBIDDEN = {'.git', '.godot', '.verification', 'builds', '__pycache__'}


def validate_names(paths):
    names = list(paths)
    seen = set()
    prefixes = {}
    reserved = {'con', 'prn', 'aux', 'nul', 'conin$', 'conout$'} | {
        prefix + digit for prefix in ('com', 'lpt') for digit in '123456789¹²³'}
    for name in names:
        if not isinstance(name, str) or not name or '\\' in name or ':' in name:
            raise ValueError('Nonportable input path')
        parts = name.split('/')
        for i, part in enumerate(parts):
            folded = part.casefold()
            if (part in ('', '.', '..') or folded in FORBIDDEN or
                    folded == '.env' or folded.startswith('.env.') or
                    folded in {'credentials', '.ssh', '.aws', 'id_rsa', 'id_ed25519'} or
                    folded.endswith(('.pem', '.key', '.p12', '.pfx')) or
                    part.endswith(('.', ' ')) or part.split('.')[0].casefold() in reserved or
                    any(ord(c) < 32 or c in '<>"|?*' for c in part)):
                raise ValueError('Forbidden input: ' + name)
            prefix = '/'.join(parts[:i + 1])
            key = unicodedata.normalize('NFC', prefix).casefold()
            if key in prefixes and prefixes[key] != prefix:
                raise ValueError('Case/normalization collision: ' + name)
            prefixes[key] = prefix
        if name.casefold() in seen:
            raise ValueError('Duplicate input: ' + name)
        seen.add(name.casefold())
    return names


def check_ancestors(path):
    """Reject aliases before resolve; callers must use a trusted, quiescent tree."""
    for item in [path, *path.parents]:
        if item.is_symlink():
            raise ValueError('Aliased path: ' + str(item))
        if item != path and item.exists() and not item.is_dir():
            raise ValueError('Non-directory ancestor: ' + str(item))


def copy_manifest(source, target, paths):
    paths = validate_names(paths)
    check_ancestors(source.absolute())
    check_ancestors(target.absolute())
    source = source.resolve()
    if target.is_symlink() or target.exists():
        raise ValueError('Target must not exist (fresh snapshot required)')
    target = target.resolve()
    if source == target or source.is_relative_to(target):
        raise ValueError('Target overlaps source')
    if target.is_relative_to(source) and not target.is_relative_to(source / '.verification'):
        raise ValueError('In-repository snapshots must be below .verification')
    checked = []
    for name in paths:
        path = source / name
        if any(p.is_symlink() for p in [path, *path.parents]) or not path.is_file():
            raise ValueError('Missing or aliased source: ' + name)
        data = path.read_bytes()
        if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
            raise ValueError('Unmaterialized LFS input: ' + name)
        checked.append((name, data))
    # Audit every declared text owner, not only the selected entry scene. Dynamic
    # paths still need explicit manifest review; historical evidence is not input.
    import re
    declared = set(paths)
    for name, data in checked:
        if Path(name).suffix not in {'.gd', '.tscn', '.tres', '.godot'}:
            continue
        for dependency in re.findall(r'''["']res://([^"'\n]+)["']''', data.decode('utf-8', errors='replace')):
            if dependency.startswith(('.verification/', '.godot/')):
                continue
            if (source / dependency).is_file() and dependency not in declared:
                raise ValueError('Undeclared resource dependency: ' + name + ' -> ' + dependency)
    target.parent.mkdir(parents=True, exist_ok=True)
    hashes = {}
    with tempfile.TemporaryDirectory(prefix='.snapshot-', dir=target.parent) as temporary:
        work = Path(temporary) / 'tree'
        work.mkdir()
        for name, data in checked:
            destination = work / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        # Exclusive reservation; replace only our own empty directory. Trusted
        # quiescent parents are required: this is not hostile-writer race proof.
        target.mkdir()
        try:
            work.replace(target)
        except OSError:
            target.rmdir()
            raise
    return hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--manifest', type=Path, default=Path('docs/manifests/pr-portability-source.json'))
    parser.add_argument('--target', required=True, type=Path)
    parser.add_argument('--engine', required=True)
    parser.add_argument('--import-project', action='store_true')
    args = parser.parse_args()
    engine = shutil.which(args.engine)
    if not engine:
        parser.error('Engine executable not found')
    version = subprocess.check_output([engine, '--version'], text=True).strip()
    if version != ENGINE_VERSION:
        parser.error('Required engine: ' + ENGINE_VERSION + '; got ' + version)
    manifest = json.loads((args.repo / args.manifest).read_text())
    hashes = copy_manifest(args.repo, args.target, manifest['files'])
    evidence = args.target / '.verification/snapshot'
    evidence.mkdir(parents=True)
    (args.target / '.verification/.gdignore').touch()
    (evidence / 'inputs.json').write_text(json.dumps({'engine': version, 'files': hashes}, indent=2) + '\n')
    print(json.dumps({'files': len(hashes), 'target': str(args.target), 'engine': version}), flush=True)
    if args.import_project:
        return subprocess.call([sys.executable, str(args.target / 'tools/run_all_tests.py'), '--engine', engine,
                                '--import-only', '--output', '.verification/import'])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

"""Package already-exported v0.5 artifacts; never exports or infers source identity.

Use a clean, frozen source checkout and explicitly supply its full HEAD SHA.
Export-byte provenance remains the caller's responsibility; this tool cannot prove
which source produced an arbitrary pre-existing executable/PCK.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

NOTICES = ('third_party/Godot-LICENSE.txt', 'third_party/Godot-COPYRIGHT.txt', 'third_party/OFL-ZillaSlab.txt', 'third_party/ASSET-NOTICES.txt')
PRESETS = {'web': 'Web Browser', 'windows': 'Windows Playtest'}


def digest(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def metadata(sha, release, engine):
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Expected explicit full lowercase source commit')
    if not re.fullmatch(r'v0\.5(?:[.-][A-Za-z0-9.-]+)?', release):
        raise ValueError('Expected v0.5 release identifier')
    if not re.fullmatch(r'4\.7\.2\.stable\.official\.[A-Za-z0-9]+', engine):
        raise ValueError('Expected official Godot 4.7.2 version')
    return {'source_commit': sha, 'release': release, 'engine': engine}


def package(project, exported, output, sha, release, engine, platform):
    build = metadata(sha, release, engine)
    project, exported, output = map(lambda p: Path(p).resolve(), (project, exported, output))
    def git(*args):
        return subprocess.check_output(['git', '-C', str(project), *args], text=True).strip()
    if not (project / 'project.godot').is_file() or git('rev-parse', 'HEAD') != sha:
        raise ValueError('Source project/HEAD mismatch')
    if git('status', '--porcelain', '--untracked-files=all', '--', '.'):
        raise ValueError('Source project must be clean')
    if not exported.is_dir() or output.exists():
        raise ValueError('Require export directory and a new output ZIP')
    with tempfile.TemporaryDirectory(prefix='v05-package-') as temp:
        stage = Path(temp)
        for path in sorted(exported.rglob('*')):
            if path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
                raise ValueError('Linked export members forbidden')
            if path.is_dir():
                continue
            relative = path.relative_to(exported)
            name = relative.as_posix()
            safe_name(name)
            if not stat.S_ISREG(path.stat().st_mode):
                raise ValueError('Non-regular export member')
            if name == 'build.json':
                if strict_json(path.read_bytes()) != build:
                    raise ValueError('Existing export source metadata mismatch')
                continue
            if name == 'manifest.json':
                continue
            allowed = (name in NOTICES or ('/' not in name and
                       (re.fullmatch(r'index(?:\.[A-Za-z0-9_-]+)*\.(?:html|js|wasm|pck|png|ico|svg|webmanifest)', name)
                        if platform == 'web' else re.fullmatch(r'[A-Za-z0-9_.-]+\.(?:exe|pck|dll)', name))))
            if not allowed:
                raise ValueError('Unexpected export member; use a dedicated clean export directory')
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        (stage / 'build.json').write_text(json.dumps(build, indent=2) + '\n', encoding='utf-8')
        files = [{'file': p.relative_to(stage).as_posix(), 'bytes': p.stat().st_size, 'sha256': digest(p)}
                 for p in sorted(stage.rglob('*')) if p.is_file() and p.name != 'manifest.json']
        manifest = {'engine': engine, 'preset': PRESETS[platform], 'threaded': False,
                    'files': files, 'total_bytes': sum(row['bytes'] for row in files)}
        (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        output.parent.mkdir(parents=True, exist_ok=True)
        candidate = stage / '_candidate.zip'
        payloads = [p for p in sorted(stage.rglob('*')) if p.is_file()]
        with zipfile.ZipFile(candidate, 'x', compression=zipfile.ZIP_DEFLATED) as z:
            for p in payloads:
                if p.is_file():
                    info = zipfile.ZipInfo(p.relative_to(stage).as_posix())
                    info.create_system = 3
                    info.external_attr = (stat.S_IFREG | 0o644) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    with p.open('rb') as source, z.open(info, 'w', force_zip64=True) as destination:
                        shutil.copyfileobj(source, destination)
        result = verify(candidate, sha, release, engine, platform)
        with candidate.open('rb') as source, output.open('xb') as destination:
            shutil.copyfileobj(source, destination)
        return result


def safe_name(name):
    if not isinstance(name, str) or not name or '\\' in name or ':' in name:
        raise ValueError('Unsafe member path')
    for part in name.split('/'):
        if (part in ('', '.', '..') or part[-1:] in (' ', '.')
                or re.search(r'[\x00-\x1f<>"|?*]', part)
                or re.fullmatch(r'(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])', part.split('.')[0])):
            raise ValueError('Unsafe member path')


def required(names, platform):
    needed = set(NOTICES) | {'build.json', 'manifest.json'}
    if platform == 'web':
        needed |= {'index.html', 'index.js', 'index.wasm', 'index.pck'}
    else:
        executables = [n for n in names if n.lower().endswith('.exe') and '/' not in n]
        if not executables:
            raise ValueError('Missing Windows executable')
        if not any(str(Path(n).with_suffix('.pck')) in names for n in executables):
            raise ValueError('Missing matching external Windows PCK')
    if not needed <= set(names):
        raise ValueError('Missing export files or required notices')


def strict_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=pairs)


def verify(archive, sha, release, engine, platform):
    expected = metadata(sha, release, engine)
    with zipfile.ZipFile(archive) as z, tempfile.TemporaryDirectory(prefix='v05-verify-') as temp:
        infos = z.infolist()
        names = [i.filename for i in infos]
        if not 1 <= len(names) <= 10000 or len({n.casefold() for n in names}) != len(names):
            raise ValueError('Duplicate members or member count exceeded')
        if sum(i.file_size for i in infos) > 8_000_000_000:
            raise ValueError('Archive size limit exceeded')
        for info in infos:
            safe_name(info.filename)
            if (info.orig_filename != info.filename or info.is_dir()
                    or not stat.S_ISREG(info.external_attr >> 16) or info.flag_bits & 1
                    or not 0 < info.file_size <= 4_000_000_000):
                raise ValueError('Non-regular, encrypted, empty or oversized member')
            if any('/'.join(info.filename.split('/')[:n]).casefold() in {s.casefold() for s in names}
                   for n in range(1, len(info.filename.split('/')))):
                raise ValueError('File/directory member collision')
        required(names, platform)
        if z.getinfo('manifest.json').file_size > 4_000_000 or z.getinfo('build.json').file_size > 4096:
            raise ValueError('Metadata size limit exceeded')
        manifest = strict_json(z.read('manifest.json'))
        if not isinstance(manifest, dict) or set(manifest) != {'engine', 'preset', 'threaded', 'files', 'total_bytes'}:
            raise ValueError('Manifest schema mismatch')
        if (manifest['engine'] != engine or manifest['preset'] != PRESETS[platform]
                or manifest['threaded'] is not False):
            raise ValueError('Manifest engine/preset/threading mismatch')
        if strict_json(z.read('build.json')) != expected:
            raise ValueError('Build metadata mismatch')
        rows = manifest['files']
        if not isinstance(rows, list):
            raise ValueError('Invalid manifest entries')
        listed = []
        for row in rows:
            if not isinstance(row, dict) or set(row) != {'file', 'bytes', 'sha256'}:
                raise ValueError('Invalid manifest entry schema')
            safe_name(row['file'])
            if type(row['bytes']) is not int or row['bytes'] <= 0 or not isinstance(row['sha256'], str) or not re.fullmatch('[0-9a-f]{64}', row['sha256']):
                raise ValueError('Invalid manifest size/hash')
            listed.append(row['file'])
        if len(set(listed)) != len(listed) or set(listed) != set(names) - {'manifest.json'}:
            raise ValueError('Manifest exact membership mismatch')
        if type(manifest['total_bytes']) is not int or sum(r['bytes'] for r in rows) != manifest['total_bytes']:
            raise ValueError('Manifest total size mismatch')
        for row in rows:
            with z.open(row['file']) as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest()
            if z.getinfo(row['file']).file_size != row['bytes'] or actual != row['sha256']:
                raise ValueError('Member hash/size mismatch')
        if z.testzip() is not None:
            raise ValueError('ZIP CRC mismatch')
        z.extractall(temp)
        for row in rows:
            path = Path(temp) / row['file']
            if path.stat().st_size != row['bytes'] or digest(path) != row['sha256']:
                raise ValueError('Fresh extraction hash/size mismatch')
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('package', 'verify'):
        sub = commands.add_parser(name)
        sub.add_argument('--engine', required=True, help='Official Godot executable (queried with --version only)')
        sub.add_argument('--source-commit', required=True, help='Explicit full committed source SHA')
        sub.add_argument('--version', required=True, help='Public release identifier, e.g. v0.5')
        sub.add_argument('--platform', choices=PRESETS, required=True)
        if name == 'package':
            sub.add_argument('--project', type=Path, required=True, help='Clean frozen project directory')
            sub.add_argument('--export-dir', type=Path, required=True, help='Already exported files and required third_party notices')
            sub.add_argument('--output', type=Path, required=True, help='New ZIP outside the source checkout')
        else:
            sub.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    try:
        version = subprocess.check_output([args.engine, '--version'], text=True, timeout=15).strip()
        if args.command == 'package':
            source_root = Path(subprocess.check_output(['git', '-C', str(args.project), 'rev-parse', '--show-toplevel'], text=True).strip()).resolve()
            if args.output.resolve().is_relative_to(source_root) or args.output.resolve().is_relative_to(args.export_dir.resolve()):
                raise ValueError('Output must be outside source checkout and export directory')
            result = package(args.project, args.export_dir, args.output, args.source_commit, args.version, version, args.platform)
        else:
            result = verify(args.archive, args.source_commit, args.version, version, args.platform)
        print(json.dumps({'verified': True, **result}))
    except (ValueError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, KeyError, TypeError) as exc:
        parser.exit(1, 'Release verification failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()

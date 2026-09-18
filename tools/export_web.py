"""Build the full single-threaded Godot Web artifact outside the source tree."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, help='Godot 4.7.2 executable')
    parser.add_argument('--output', type=Path, required=True, help='Dedicated output directory outside this checkout')
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or ROOT in output.parents:
        parser.error('Keep the large Web artifact outside the source checkout')
    version = subprocess.check_output([args.godot, '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'):
        parser.error('This preset is verified with Godot 4.7.2.stable and matching official templates')
    output.mkdir(parents=True, exist_ok=True)
    logs = output.parent / (output.name + '_logs')
    logs.mkdir(exist_ok=True)
    for name, options in [('import', ['--editor', '--import']), ('export', ['--export-release', 'Web Browser', str(output / 'index.html')])]:
        with (logs / (name + '.log')).open('w', encoding='utf-8') as log:
            subprocess.run([args.godot, '--headless', '--path', str(ROOT), *options], stdout=log, stderr=subprocess.STDOUT, check=True)
        text = (logs / (name + '.log')).read_text(encoding='utf-8', errors='replace')
        if 'ERROR:' in text or 'SCRIPT ERROR:' in text:
            raise RuntimeError(f'Inspect {logs / (name + ".log")}: engine reported errors')
    required = ['index.html', 'index.js', 'index.wasm', 'index.pck']
    for name in required:
        if not (output / name).is_file() or not (output / name).stat().st_size:
            raise RuntimeError(f'Missing export file: {name}')
    notices = output / 'third_party'
    notices.mkdir(exist_ok=True)
    for name in ['Godot-LICENSE.txt', 'Godot-COPYRIGHT.txt', 'OFL-ZillaSlab.txt']:
        shutil.copy2(ROOT / 'third_party' / name, notices / name)
    # Bind each published artifact to the frozen source commit (no local paths).
    source_commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    (output / 'build.json').write_text(json.dumps({'source_commit': source_commit, 'release': 'Mephisto duo browser playtest', 'engine': version}, indent=2) + '\n', encoding='utf-8')
    # No source paths, usernames, private evidence or credentials in the artifact.
    files = []
    for path in sorted(output.rglob('*')):
        if path.is_file() and path.name != 'manifest.json':
            with path.open('rb') as handle:
                digest = hashlib.file_digest(handle, 'sha256').hexdigest()
            files.append({'file': path.relative_to(output).as_posix(), 'bytes': path.stat().st_size, 'sha256': digest})
    manifest = {'engine': version, 'preset': 'Web Browser', 'threaded': False, 'files': files, 'total_bytes': sum(row['bytes'] for row in files)}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))
    print(f'HTTP preview: python -m http.server 8873 --bind 127.0.0.1 --directory "{output}"')


if __name__ == '__main__':
    main()

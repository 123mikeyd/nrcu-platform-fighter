"""Lossless physical CTEX sharing for unencrypted Godot 4.7.2 PCK v4.

Preserves every logical resource byte and path. Does not change GPU resources,
import policies or source artwork. Keep the ordinary export as a fallback.
Usage: python tools/share_web_texture_payloads.py INPUT.pck OUTPUT.pck PROOF.json
"""
import hashlib
import json
from pathlib import Path
import struct
import sys


def parse(path):
    with path.open('rb') as f:
        header = f.read(112)
        magic, version, major, minor, patch, flags, base, directory = struct.unpack('<4s5IQQ', header[:40])
        assert (magic, version, major, minor, patch, flags) == (b'GDPC', 4, 4, 7, 2, 2)
        f.seek(directory)
        count = struct.unpack('<I', f.read(4))[0]
        rows = []
        for _ in range(count):
            n = struct.unpack('<I', f.read(4))[0]
            name = f.read(n)
            offset, size = struct.unpack('<QQ', f.read(16))
            md5 = f.read(16)
            entry_flags = struct.unpack('<I', f.read(4))[0]
            assert entry_flags == 0
            rows.append((name, offset, size, md5, entry_flags))
        assert len({r[0] for r in rows}) == len(rows)
        return header, base, rows, f.read()


def share(source, target, proof):
    assert not target.exists() and not proof.exists()
    header, base, rows, tail = parse(source)
    offsets, canonical, manifests = {}, {}, []
    with source.open('rb') as src, target.open('xb') as dst:
        dst.write(header)
        for name, offset, size, md5, flags in rows:
            src.seek(base + offset)
            data = src.read(size)
            assert len(data) == size and hashlib.md5(data).digest() == md5
            digest = hashlib.sha256(data).hexdigest()
            path = name.rstrip(b'\0').decode()
            key = (digest, size, flags) if path.endswith('.ctex') else ('path', path)
            if key not in canonical:
                dst.write(b'\0' * ((-dst.tell()) % 16))
                canonical[key] = dst.tell() - base
                dst.write(data)
            offsets[name] = canonical[key]
            manifests.append({'path': path, 'bytes': size, 'sha256': digest})
        dst.write(b'\0' * ((-dst.tell()) % 16))
        directory = dst.tell()
        dst.write(struct.pack('<I', len(rows)))
        for name, _, size, md5, flags in rows:
            dst.write(struct.pack('<I', len(name)) + name + struct.pack('<QQ', offsets[name], size) + md5 + struct.pack('<I', flags))
        dst.write(tail)
        dst.seek(32)
        dst.write(struct.pack('<Q', directory))
    _, new_base, new_rows, new_tail = parse(target)
    assert len(new_rows) == len(rows) and tail == new_tail
    with target.open('rb') as f:
        for old, new, manifest in zip(rows, new_rows, manifests):
            assert old[0] == new[0] and old[2:] == new[2:]
            f.seek(new_base + new[1])
            assert hashlib.sha256(f.read(new[2])).hexdigest() == manifest['sha256']
    result = {'before_bytes': source.stat().st_size, 'after_bytes': target.stat().st_size,
              'saved_bytes': source.stat().st_size - target.stat().st_size,
              'verified_paths': len(rows), 'payloads': manifests}
    proof.write_text(json.dumps(result, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in result.items() if k != 'payloads'}))


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    share(*(Path(p) for p in sys.argv[1:]))

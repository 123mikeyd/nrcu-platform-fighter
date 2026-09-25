"""Generated temporary TEST FIXTURES only; never game/export acceptance evidence."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('release_v05', ROOT / 'tools/release_v05.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='v05-test-fixture-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / 'project'
        self.project.mkdir()
        (self.project / 'project.godot').write_text('; TEST FIXTURE\n')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'test fixture')
        self.sha = self.git('rev-parse', 'HEAD').strip()
        self.export = self.root / 'export'
        self.export.mkdir()
        for name in ['index.html', 'index.js', 'index.wasm', 'index.pck', *m.NOTICES]:
            path = self.export / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'TEST FIXTURE ONLY\n')
        self.archive = self.root / 'test.zip'

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.project), *args], text=True, stderr=subprocess.STDOUT)

    def package(self):
        return m.package(self.project, self.export, self.archive, self.sha, 'v0.5', '4.7.2.stable.official.test', 'web')

    def verify(self):
        return m.verify(self.archive, self.sha, 'v0.5', '4.7.2.stable.official.test', 'web')

    def rewrite(self, change):
        with zipfile.ZipFile(self.archive) as z:
            entries = [(i, z.read(i)) for i in z.infolist()]
        entries = change(entries)
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.archive, 'w') as z:
                for info, data in entries:
                    z.writestr(info, data)

    def test_reject_duplicate(self):
        self.package()
        self.rewrite(lambda e: e + [e[0]])
        with self.assertRaises(ValueError):
            self.verify()

    def test_reject_unsafe_extra_paths_and_nonregular(self):
        import stat
        for name in ['../escape', '/absolute', 'C:/drive', 'a\\\\b', 'a//b', 'a/./b', 'CON', 'a. ', 'link']:
            with self.subTest(name=name):
                if self.archive.exists():
                    self.archive.unlink()
                self.package()
                info = zipfile.ZipInfo(name)
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16 if name == 'link' else (stat.S_IFREG | 0o644) << 16
                self.rewrite(lambda e: e + [(info, b'test')])
                with self.assertRaises(ValueError):
                    self.verify()

    def test_hash_mismatch(self):
        self.package()
        self.rewrite(lambda e: [(i, b'corrupt' if i.filename == 'index.pck' else d) for i, d in e])
        with self.assertRaises(ValueError):
            self.verify()

    def test_missing_notices(self):
        for notice in m.NOTICES:
            with self.subTest(notice=notice):
                p = self.export / notice
                p.unlink()
                with self.assertRaises(ValueError):
                    self.package()
                p.write_bytes(b'TEST FIXTURE ONLY')
                if self.archive.exists():
                    self.archive.unlink()

    def test_asset_notices_required(self):
        notice = self.export / 'third_party/ASSET-NOTICES.txt'
        if notice.exists():
            notice.unlink()
        with self.assertRaises(ValueError):
            self.package()

    def test_wrong_source(self):
        with self.assertRaises(ValueError):
            m.package(self.project, self.export, self.archive, '0' * 40, 'v0.5', '4.7.2.stable.official.test', 'web')
        self.package()
        with self.assertRaises(ValueError):
            m.verify(self.archive, '0' * 40, 'v0.5', '4.7.2.stable.official.test', 'web')

    def test_metadata_and_membership_tampering(self):
        for field, value in [('total_bytes', 1), ('threaded', True), ('preset', 'wrong'), ('engine', 'wrong'), ('files', [])]:
            with self.subTest(field=field):
                if self.archive.exists():
                    self.archive.unlink()
                self.package()
                def alter(entries):
                    result = []
                    for info, data in entries:
                        if info.filename == 'manifest.json':
                            doc = json.loads(data)
                            doc[field] = value
                            data = json.dumps(doc).encode()
                        result.append((info, data))
                    return result
                self.rewrite(alter)
                with self.assertRaises(ValueError):
                    self.verify()

    def test_windows_missing_or_mismatched_pck_rejected(self):
        for p in self.export.glob('index.*'):
            p.unlink()
        (self.export / 'NRCU.exe').write_bytes(b'TEST FIXTURE NOT EXECUTABLE')
        for mismatch in (False, True):
            with self.subTest(mismatch=mismatch):
                if self.archive.exists():
                    self.archive.unlink()
                if mismatch:
                    (self.export / 'other.pck').write_bytes(b'TEST FIXTURE PCK')
                with self.assertRaises(ValueError):
                    m.package(self.project, self.export, self.archive, self.sha, 'v0.5', '4.7.2.stable.official.test', 'windows')
                if self.archive.exists():
                    self.archive.unlink()

    def test_windows_roundtrip(self):
        for p in self.export.glob('index.*'):
            p.unlink()
        (self.export / 'NRCU.exe').write_bytes(b'TEST FIXTURE NOT EXECUTABLE')
        (self.export / 'NRCU.pck').write_bytes(b'TEST FIXTURE PCK')
        m.package(self.project, self.export, self.archive, self.sha, 'v0.5', '4.7.2.stable.official.test', 'windows')
        m.verify(self.archive, self.sha, 'v0.5', '4.7.2.stable.official.test', 'windows')
        with zipfile.ZipFile(self.archive) as z:
            self.assertEqual(json.loads(z.read('manifest.json'))['preset'], 'Windows Playtest')

    def test_crc_corruption(self):
        self.package()
        # Rewrite stored members, then flip payload bytes without updating CRC.
        def stored(entries):
            for info, _ in entries:
                info.compress_type = zipfile.ZIP_STORED
            return entries
        self.rewrite(stored)
        import struct
        with zipfile.ZipFile(self.archive) as z:
            info = z.getinfo('index.pck')
            offset = info.header_offset
        data = bytearray(self.archive.read_bytes())
        name_len, extra_len = struct.unpack_from('<HH', data, offset + 26)
        data[offset + 30 + name_len + extra_len] ^= 1
        self.archive.write_bytes(data)
        with self.assertRaises((ValueError, zipfile.BadZipFile, __import__('zlib').error)):
            self.verify()

    def test_invalid_public_metadata(self):
        for sha, release, engine in [(self.sha, 'C:/private', '4.7.2.stable.official.test'),
                                     ('main', 'v0.5', '4.7.2.stable.official.test'),
                                     (self.sha, 'v0.5', 'C:/engine')]:
            with self.subTest(release=release, engine=engine):
                with self.assertRaises(ValueError):
                    m.metadata(sha, release, engine)

    def test_stale_export_metadata_rejected(self):
        (self.export / 'build.json').write_text(json.dumps({'source_commit': '0' * 40}))
        with self.assertRaises(ValueError):
            self.package()

    def test_dirty_source_rejected(self):
        (self.project / 'project.godot').write_text('; changed fixture')
        with self.assertRaises(ValueError):
            self.package()

    def test_private_extra_rejected(self):
        (self.export / 'private.log').write_text('private test fixture')
        with self.assertRaises(ValueError):
            self.package()

    def test_cli_help(self):
        result = subprocess.run([__import__('sys').executable, str(ROOT / 'tools/release_v05.py'), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('package', result.stdout)

    def test_roundtrip(self):
        self.package()
        result = self.verify()
        self.assertEqual(result['source_commit'], self.sha)
        with zipfile.ZipFile(self.archive) as z:
            manifest = json.loads(z.read('manifest.json'))
            self.assertEqual(set(manifest), {'engine', 'preset', 'threaded', 'files', 'total_bytes'})
            self.assertNotIn(str(self.root), z.read('build.json').decode())
        self.assertFalse((self.export / 'build.json').exists())


if __name__ == '__main__':
    unittest.main()

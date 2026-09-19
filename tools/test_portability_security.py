"""Isolated regression fixtures; never attack the working project."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from tools import portable_snapshot as snap, raw_resource_packaging as raw


def inventory(s):
    files = {p.relative_to(s).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in s.rglob('*') if p.is_file() and '.verification' not in p.parts}
    (s / '.verification/snapshot/inputs.json').write_text(json.dumps({'engine': snap.ENGINE_VERSION, 'files': files}))


def fixture(t):
    s = t / 'stage'; s.mkdir()
    (s / '.verification/snapshot').mkdir(parents=True)
    (s / '.verification/snapshot/inputs.json').write_text('{}')
    (s / 'project.godot').write_text('[application]\n')
    (s / 'raw.tres').write_text('raw')
    return s


class OriginalRepros(unittest.TestCase):
    def test_original_windows_path(self):
        with tempfile.TemporaryDirectory() as d:
            t = Path(d); s = t / 'source'; s.mkdir()
            (s / 'C:\\escape').write_text('nonportable')
            with self.assertRaises(ValueError): snap.copy_manifest(s, t / 'windows', ['C:\\escape'])
            self.assertFalse((t / 'windows').exists())

    def test_original_raw_attacks(self):
        for attack in ['symlink', 'hardlink', 'parent', 'evidence', 'probe', 'output']:
            with self.subTest(attack=attack), tempfile.TemporaryDirectory() as d:
                t = Path(d); s = fixture(t); victim = t / 'victim'; victim.write_text('[application]\n')
                outside = t / 'external'; outside.mkdir(); (outside / 'private.tres').write_text('private')
                paths = ['raw.tres']
                if attack in ('symlink', 'hardlink'):
                    (s / 'project.godot').unlink()
                    getattr(s / 'project.godot', 'symlink_to' if attack == 'symlink' else 'hardlink_to')(victim)
                if attack == 'parent':
                    (s / 'alias').symlink_to(outside, target_is_directory=True); paths = ['alias/private.tres']
                if attack == 'evidence': paths = ['.verification/snapshot/inputs.json']
                if attack == 'probe': (s / 'raw_pack_probe.gd').write_text('existing source')
                if attack == 'output': (s / 'addons').symlink_to(outside, target_is_directory=True)
                before = {str(p): p.read_bytes() for p in t.rglob('*') if p.is_file()}
                with self.assertRaises(ValueError): raw.install(s, paths)
                self.assertEqual(before, {str(p): p.read_bytes() for p in t.rglob('*') if p.is_file()})


class AuthenticatedPreflight(unittest.TestCase):
    def test_rejects_unsafe_stage_without_any_write(self):
        attacks = ['project_link', 'project_hard', 'root_link', 'marker_link', 'marker_hard',
                   'input_parent', 'input_hard', 'tamper', 'unlisted', 'evidence', 'project_input',
                   'output_parent', 'output_directory', 'probe', 'probe_link', 'probe_hard', 'pins',
                   'plugin', 'missing', 'directory', 'duplicate', 'case_collision']
        for attack in attacks:
            with self.subTest(attack=attack), tempfile.TemporaryDirectory() as d:
                t = Path(d); s = fixture(t); inventory(s); stage = s
                victim = t / 'victim'; victim.write_text('[application]\n')
                outside = t / 'outside'; outside.mkdir(); (outside / 'private.tres').write_text('private')
                paths = ['raw.tres']
                if attack.startswith('project_') and attack != 'project_input':
                    (s / 'project.godot').unlink()
                    getattr(s / 'project.godot', 'hardlink_to' if attack.endswith('hard') else 'symlink_to')(victim)
                if attack == 'root_link': stage = t / 'alias'; stage.symlink_to(s, target_is_directory=True)
                if attack.startswith('marker_'):
                    marker = s / '.verification/snapshot/inputs.json'; victim.write_bytes(marker.read_bytes()); marker.unlink()
                    getattr(marker, 'hardlink_to' if attack.endswith('hard') else 'symlink_to')(victim)
                if attack == 'input_parent':
                    (s / 'alias').symlink_to(outside, target_is_directory=True); paths = ['alias/private.tres']; inventory(s)
                if attack == 'input_hard':
                    (s / 'raw.tres').unlink(); (s / 'raw.tres').hardlink_to(victim); inventory(s)
                if attack == 'tamper': (s / 'raw.tres').write_text('changed')
                if attack == 'unlisted': (s / 'other.tres').write_text('private'); paths = ['other.tres']
                if attack == 'evidence': paths = ['.verification/snapshot/inputs.json']
                if attack == 'project_input': paths = ['project.godot']
                if attack == 'output_parent': (s / 'addons').symlink_to(outside, target_is_directory=True)
                if attack == 'output_directory': (s / 'raw_pack_probe.gd').mkdir()
                if attack == 'probe': (s / 'raw_pack_probe.gd').write_text('preserve')
                if attack in ('probe_link', 'probe_hard'):
                    getattr(s / 'raw_pack_probe.gd', 'hardlink_to' if attack.endswith('hard') else 'symlink_to')(victim)
                if attack == 'pins': (s / '.verification/snapshot/raw-pins.json').write_text('preserve')
                if attack == 'plugin': (s / 'addons/portable_raw').mkdir(parents=True)
                if attack == 'missing': paths = ['missing']
                if attack == 'directory': paths = ['.verification']
                if attack == 'duplicate': paths *= 2
                if attack == 'case_collision': (s / 'RAW.tres').write_text('raw'); inventory(s); paths += ['RAW.tres']
                before = {str(p): (('link', str(p.readlink())) if p.is_symlink() else ('file', p.read_bytes()) if p.is_file() else ('dir',)) for p in t.rglob('*')}
                with self.assertRaises(ValueError): raw.install(stage, paths)
                after = {str(p): (('link', str(p.readlink())) if p.is_symlink() else ('file', p.read_bytes()) if p.is_file() else ('dir',)) for p in t.rglob('*')}
                self.assertEqual(before, after)


class PortableGrammar(unittest.TestCase):
    def test_windows_superscript_device_names(self):
        for name in ['COM¹', 'LPT².txt', 'nested/COM³.bin']:
            with self.subTest(name=name):
                with self.assertRaises(ValueError): snap.validate_names([name])

    def test_both_entrypoints_reject_nonportable_names_before_write(self):
        for name in ['', '.', './raw.tres', 'x//y', 'raw.tres/', 'C:escape', 'C:\\escape', '\\\\host\\share',
                     'CON', 'COM¹', 'LPT².txt', 'nested/COM³.bin', 'a/NUL.txt', 'trail.', 'trail ', 'a\x01b', 'a?b', '../escape', '/root',
                     '.env', 'keys/private.pem', '.VERIFICATION/private', 'builds/output']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as d:
                t = Path(d); s = fixture(t); inventory(s)
                if name not in ('', '.', '../escape', '/root') and not name.startswith(('C:', '\\')):
                    p = s / name
                    if not p.exists():
                        p.parent.mkdir(parents=True, exist_ok=True); p.write_text('fixture')
                with self.assertRaises(ValueError): snap.copy_manifest(s, t / 'copy', [name])
                self.assertFalse((t / 'copy').exists())
                with self.assertRaises(ValueError): raw.install(s, [name])
                self.assertFalse((s / 'addons').exists())

    def test_snapshot_aliases_collisions_and_hardlink_copy(self):
        for attack in ['source_alias', 'target_parent', 'duplicate', 'case', 'component_case']:
            with self.subTest(attack=attack), tempfile.TemporaryDirectory() as d:
                t = Path(d); s = fixture(t); target = t / 'copy'; paths = ['raw.tres']
                if attack == 'source_alias': alias = t / 'alias'; alias.symlink_to(s); s = alias
                if attack == 'target_parent': alias = t / 'alias'; alias.symlink_to(t); target = alias / 'copy'
                if attack == 'duplicate': paths *= 2
                if attack == 'case': (s / 'RAW.tres').write_text('raw'); paths += ['RAW.tres']
                if attack == 'component_case':
                    for name in ['Foo/a', 'foo/b']:
                        (s / name).parent.mkdir(exist_ok=True); (s / name).write_text('raw')
                    paths = ['Foo/a', 'foo/b']
                with self.assertRaises(ValueError): snap.copy_manifest(s, target, paths)
                self.assertFalse(target.exists())
        with tempfile.TemporaryDirectory() as d:
            t = Path(d); s = fixture(t); (s / 'hard').hardlink_to(s / 'raw.tres')
            snap.copy_manifest(s, t / 'copy', ['hard'])
            self.assertNotEqual((s / 'hard').stat().st_ino, (t / 'copy/hard').stat().st_ino)


class AtomicPublication(unittest.TestCase):
    def test_snapshot_write_failure_does_not_publish_partial_target(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            t = Path(d); s = fixture(t)
            with patch.object(Path, 'write_bytes', side_effect=OSError('simulated disk failure')):
                with self.assertRaises(OSError): snap.copy_manifest(s, t / 'copy', ['raw.tres'])
            self.assertFalse((t / 'copy').exists())

    def test_project_replaced_not_truncated_and_unrelated_files_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            s = fixture(Path(d)); inventory(s)
            (s / 'addons').mkdir(); (s / 'addons/unrelated').write_bytes(b'keep')
            with (s / 'project.godot').open('rb') as original:
                pins = raw.install(s, ['raw.tres'])
                self.assertEqual(original.read(), b'[application]\n')
            self.assertEqual((s / 'addons/unrelated').read_bytes(), b'keep')
            self.assertEqual(pins['res://raw.tres'], hashlib.sha256(b'raw').hexdigest())
            self.assertIn('portable_raw', (s / 'project.godot').read_text())


if __name__ == '__main__': unittest.main()

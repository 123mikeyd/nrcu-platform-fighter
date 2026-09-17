"""Install raw authenticated-resource packing in a disposable snapshot only.

Does not export, choose a main scene, or change the source project.
"""
import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path

try:
    from tools.portable_snapshot import validate_names, check_ancestors
except ModuleNotFoundError:  # Direct CLI execution from outside the repository.
    from portable_snapshot import validate_names, check_ancestors


def install(stage, paths):
    check_ancestors(stage.absolute())
    stage = stage.resolve()
    marker = stage / '.verification/snapshot/inputs.json'
    project = stage / 'project.godot'
    for path in (marker, project):
        check_ancestors(path)
        if not path.is_file() or path.stat().st_nlink != 1:
            raise ValueError('Missing or multiply linked snapshot input: ' + str(path))
    if (stage / '.git').exists() or (stage / '.git').is_symlink():
        raise ValueError('Only an explicitly created disposable snapshot is allowed')
    inventory = json.loads(marker.read_bytes())
    if not isinstance(inventory, dict) or not isinstance(inventory.get('files'), dict):
        raise ValueError('Snapshot hash inventory required')
    allowed = inventory['files']
    validate_names(allowed)
    paths = validate_names(paths)
    outputs = ['addons/portable_raw', 'raw_pack_probe.gd', '.verification/snapshot/raw-pins.json']
    for name in outputs:
        path = stage / name
        check_ancestors(path)
        if path.exists():
            raise ValueError('Output already exists: ' + name)
    pins = {}
    for name in ['project.godot', *paths]:
        if name in paths and (name == 'project.godot' or any(name == o or name.startswith(o + '/') or o.startswith(name + '/') for o in outputs)):
            raise ValueError('Input/output overlap: ' + name)
        path = stage / name
        check_ancestors(path)
        if name not in allowed or not path.is_file() or path.stat().st_nlink != 1:
            raise ValueError('Undeclared or aliased raw input: ' + name)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != allowed[name]:
            raise ValueError('Snapshot hash mismatch: ' + name)
        if name in paths:
            pins['res://' + name] = digest
    text = project.read_text()
    if '[editor_plugins]' in text:
        raise ValueError('Existing plugins require explicit integration review')
    payloads = {}
    payloads['addons/portable_raw/plugin.cfg'] = '[plugin]\nname="Portable raw provenance"\ndescription="Preserve authenticated source bytes"\nauthor="NRCU tooling contributors (not asset attribution)"\nversion="1"\nscript="plugin.gd"\n'
    payloads['addons/portable_raw/plugin.gd'] = '@tool\nextends EditorPlugin\nvar exporter = preload("export.gd").new()\nfunc _enter_tree(): add_export_plugin(exporter)\nfunc _exit_tree(): remove_export_plugin(exporter)\n'
    payloads['addons/portable_raw/export.gd'] = '@tool\nextends EditorExportPlugin\nfunc _get_name(): return "PortableRawProvenance"\nfunc _export_begin(_features, _debug, _path, _flags):\n    for path in ' + json.dumps(list(pins)) + ':\n        add_file(path, FileAccess.get_file_as_bytes(path), false)\n'
    payloads['project.godot'] = text + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/portable_raw/plugin.cfg")\n'
    # The probe runs from the packed project and requires every exact raw hash.
    runtime_probe = '''    for id in ["teknium", "turbofit"]:
        var base_path = "res://data/collision/generated/%s.tres" % id
        var profile = load(base_path)
        var override = load("res://data/collision/overrides/%s_anatomical_v1.tres" % id)
        if override.provenance.get("generated_profile_sha256", "") != FileAccess.get_sha256(base_path):
            push_error("Override fingerprint mismatch: " + id)
            failures += 1
        var host = load("res://scripts/core/collision/collision_host.gd").new()
        var errors = host.configure(profile, "portable-packed-proof")
        if not errors.is_empty():
            push_error("Packed source configuration failed: " + str(errors))
            failures += 1
'''
    payloads['raw_pack_probe.gd'] = 'extends SceneTree\nfunc _initialize():\n    var pins = ' + json.dumps(pins) + '\n    var failures := 0\n    for path in pins:\n        if FileAccess.get_sha256(path) != pins[path]:\n            push_error("Raw pack mismatch: " + path)\n            failures += 1\n' + runtime_probe + '    if failures == 0: print("PASS: raw pack authenticated resources ", pins.size(), " and generated hosts/overrides")\n    quit(failures)\n'
    payloads['.verification/snapshot/raw-pins.json'] = json.dumps(pins, indent=2) + '\n'
    # Private exclusive staging: finish every byte before publishing any output.
    # Per-file atomic publication, not a transaction against concurrent writers.
    with tempfile.TemporaryDirectory(prefix='.raw-install-', dir=stage) as temporary:
        work = Path(temporary)
        for index, (name, content) in enumerate(payloads.items()):
            staged = work / str(index)
            with staged.open('xb') as stream:
                stream.write(content.encode('utf-8'))
        (stage / 'addons').mkdir(exist_ok=True)
        (stage / 'addons/portable_raw').mkdir()
        for index, name in enumerate(payloads):
            if name != 'project.godot':
                # link() is exclusive: an unexpected existing leaf is never clobbered.
                os.link(work / str(index), stage / name)
        project_index = list(payloads).index('project.godot')
        os.replace(work / str(project_index), project)
    return pins


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).resolve().parent.parent / 'docs/manifests/pr-portability-raw.json')
    args = parser.parse_args()
    print(json.dumps(install(args.stage, json.loads(args.manifest.read_text())['files']), indent=2))


if __name__ == '__main__':
    main()

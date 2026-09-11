# NRCU Platform Fighter

Private work-in-progress Godot game for development and collaborative playtesting.

## Play

Use the Windows ZIP in [Releases](../../releases). Extract everything and launch `NRCU.exe` beside `NRCU.pck`. See [TESTING.md](TESTING.md) for a short Bobo test pass and bug-report instructions. Release notes distinguish automated checks from actual release-window testing.

## Open the source

Install **Godot 4.7.2**, Git, and Git LFS. Clone this private repository using an account with access, run `git lfs pull` inside the clone, then import `project.godot` in Godot. Let the initial import finish, then press F5 to launch the project home screen.

The project uses the Compatibility renderer. The `.godot` cache regenerates locally; it is deliberately not versioned. Keep the source `.import` settings, `.uid` sidecars, and `tools/import_*.gd` hooks: they preserve the intended animation sampling. Blender and the author's personal source library are not required to play or import the supplied assets.

Large models, textures, video, and binary test fixtures use Git LFS. Prefer cloning to GitHub's source ZIP so LFS retrieval is explicit. Keep quota usage in mind when updating binaries; do not enable paid overages without agreement.

## Test and export

Use Python 3.11+ and the matching Godot console executable. The portable test runner lives in `tools/run_all_tests.py`; run it with `--help` for engine and output options. Generated logs and evidence belong in ignored `.verification/`, not in commits. Tests include independent reference fixtures rather than depending on the author's machine.

Install the matching Godot **4.7.2 export templates** and use the **Windows Playtest** preset. Exports belong in ignored `builds/`. Exported files and a source-project test run are not proof of a working release: verify a fresh extraction of the final player ZIP before publishing it.

## Current scope

- Freeplay with local keyboard/gamepad slots and bots; no online multiplayer is claimed.
- Story Mode currently contains the passive 400-HP Bobo encounter for testing.
- Fighters and homepage remain in progress. Mephisto is unfinished and deferred from this test pass.
- Shared agent workflow: [Godot development and testing skill](skills/nous-game-dev-testing/SKILL.md).

## Collaborate

Use Issues for reproducible bugs and separate design suggestions. Include the exact build tag or commit. Prefer a branch and pull request for changes so we can review them together; avoid simultaneous edits to the same binary asset or shared fighter controller. Never overwrite someone else's uncommitted work.

This repository is a sanitized collaboration snapshot of the current local game. Changes made here must be deliberately reconciled with the author's local working project; do not assume the two folders synchronize automatically.

## Sharing boundaries

No blanket open-source or asset redistribution license is granted here. Access is for this private collaboration. Ask before reusing art, characters, music, or other assets in a different game or making material public. Private acquisition notes, local source-library paths, Blender masters, and historical review outputs are intentionally excluded. Preserve third-party notices and review rights before broader distribution.

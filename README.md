# NRCU Platform Fighter — v0.3

**Unfinished alpha playtest — this is not a finished game.** New frontend by [Arts Bro](https://github.com/realartsbro), integrated with the current gameplay snapshot. See [v0.3 release notes](RELEASE_NOTES_v0.3.md) for changes, known issues, and the checks actually completed.

## Play

[![Play Now — Download for Windows](https://img.shields.io/badge/PLAY_NOW-Download_for_Windows-267B52?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/123mikeyd/nrcu-platform-fighter/releases/download/v0.3/NRCU-v0.3-Windows.zip)

**Windows 64-bit download, not a browser game.** [Download v0.3](https://github.com/123mikeyd/nrcu-platform-fighter/releases/download/v0.3/NRCU-v0.3-Windows.zip) · [Release notes and checksum](https://github.com/123mikeyd/nrcu-platform-fighter/releases/tag/v0.3)

Extract the complete ZIP, open `NRCU-Alpha`, and launch `NRCU.exe` beside `NRCU.pck`. Choose **PLAY** for a local match or **STORY MODE** for Bobo. P1: WASD move/aim, Space jump, F basic, G special, E shield. Escape pauses. See [TESTING.md](TESTING.md) for bug-report instructions.

The freshly extracted Windows build was exercised with native keyboard/mouse inputs, including Story combat and pause. The final focused selection passed **35/35**; the broader inherited selection remains **142 passed / 48 failed**. This is a playable development snapshot, not all-green certification. Physical controllers and exhaustive matchups are not verified.

## Open the source

Install **Godot 4.7.2**, Git, and Git LFS. Clone this public repository (no collaborator invitation is required to read or download it), run `git lfs pull` inside the clone, then import `project.godot` in Godot. Let the initial import finish, then press F5 to launch the project home screen.

The project uses the Compatibility renderer. The `.godot` cache regenerates locally; it is deliberately not versioned. Keep the source `.import` settings, `.uid` sidecars, and `tools/import_*.gd` hooks: they preserve the intended animation sampling. Blender and the author's personal source library are not required to play or import the supplied assets.

Large models, textures, video, and binary test fixtures use Git LFS. Prefer cloning to GitHub's source ZIP so LFS retrieval is explicit. Keep quota usage in mind when updating binaries; do not enable paid overages without agreement.

## Test and export

Use Python 3.11+ and the matching Godot console executable. The portable test runner lives in `tools/run_all_tests.py`; run it with `--help` for engine and output options. Generated logs and evidence belong in ignored `.verification/`, not in commits. Tests include independent reference fixtures rather than depending on the author's machine.

Install the matching Godot **4.7.2 export templates** and use the **Windows Playtest** preset. Exports belong in ignored `builds/`. Exported files and a source-project test run are not proof of a working release: verify a fresh extraction of the final player ZIP before publishing it.

## Current scope

- Freeplay with local keyboard/gamepad slots and bots; no online multiplayer is claimed.
- Story Mode contains a stationary 400-HP Bobo encounter. Bobo now attempts a slow two-part thrust/slash when an opponent is nearby.
- New title, home, character/stage selection, glove cursor, and shared pause/quit/back navigation from [PR #1](https://github.com/123mikeyd/nrcu-platform-fighter/pull/1). Unfinished VS presentation and VFX Lab are excluded.
- Integrated tumble/contact fixes, Witcheer's native DefaultSwim and the paired-Mephisto starter. Character kits, dark stage readability and other polish remain in progress; later Mephisto experiments are not part of this snapshot.
- Shared agent workflow: [Godot development and testing skill](skills/nous-game-dev-testing/SKILL.md).

## Collaborate

Use Issues for reproducible bugs and separate design suggestions. Include the exact build tag or commit. Prefer a branch and pull request for changes so we can review them together; avoid simultaneous edits to the same binary asset or shared fighter controller. Never overwrite someone else's uncommitted work.

This repository is a sanitized collaboration snapshot of the current local game. Changes made here must be deliberately reconciled with the author's local working project; do not assume the two folders synchronize automatically.

## Sharing boundaries

No blanket open-source or asset redistribution license is granted here. Public visibility is not permission to reuse the assets. Ask before reusing art, characters, music, or other assets in a different game or redistributing them separately. Private acquisition notes, local source-library paths, Blender masters, and historical review outputs are intentionally excluded. Preserve third-party notices and review rights before broader distribution.

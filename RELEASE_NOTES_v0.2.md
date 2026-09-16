# v0.2 — unfinished alpha playtest

**This game is not finished.** This is an early Windows playtest, not a stable or complete release. Expect incomplete fighters, provisional balance, visual rough edges, and bugs.

## Changes since the earlier playtest

- Updated the playable source snapshot and Windows export to the current runtime, rather than reusing the previous exported game.
- Doge Man: Lead-first tap-chained ground punches, directional roundhouse, neutral-air Superman, and the edited directional airborne Drop Kick. Held-input guards and interruption/landing cleanup are covered by focused tests. The existing down-basic Tyson route remains separate.
- Humanoid aerial attack resources and routing, body-contact queries, fitted reactions, and Teknium recovery resources are included. This does not mean every fighter or move is finished.
- Bobo remains a stationary 400-HP Story encounter, but now attempts a slow two-part thrust/slash against nearby opponents; the old passive-target instructions no longer apply.
- Current Witcheer animation resources, unfinished Mephisto companion/move work, and updated stage layouts/previews are included.
- Added nine portable Doge regression runners. Kept the existing test infrastructure, reference fixtures, and collaboration workflow.

## Verification and known issues

- Godot 4.7.2 sanitized-project import and bounded headless startup passed.
- **Existing portable suite: 101 passed, 47 failed (148 runners); project smoke passed.** This is not an all-green release. Some old tests assert replaced move routes or passive Bobo behavior. Other failures remain unresolved, including contact/status interactions, Teknium grab-related checks, GGB behavior, and legacy lifecycle/animation checks. Do not treat every failure as an obsolete test.
- Representative Bobo, Teknium grab, Doge legacy air-uppercut lifecycle, and GGB goo failures reproduced with the same error signatures against the current working game; these are not newly hidden packaging failures. The other failures were not individually reproduced against that game.
- **Focused current Doge suite: 9 passed, 0 failed**, plus its separate project smoke. It covers ground input/routes/contact, Lead-first chaining, moving-punch contact, Tyson follow-up direction, normal Start/raw-input airborne routing and cleanup, and stationary/moving aerial contact fixtures. These are automated tests, not whole-roster or visual approval.
- Windows release export completed. The final ZIP passed its integrity check; a fresh extraction of its actual `NRCU.exe` passed a 180-frame headless startup with exit 0 and no engine errors. No full interactive playthrough or physical gamepad certification is claimed.
- Download: `NRCU-v0.2-Windows.zip` — **284,115,008 bytes**. SHA-256: `080394fc0784173d03ff310a320022c009f1221249722e326ba6dfdf58be91dc`.
- An optional external-script match probe against the exported player timed out without useful logging. It does not establish exported match coverage; source-project Start/input tests are separate evidence.

## Play and report

Extract the entire Windows ZIP and launch `NRCU.exe` beside `NRCU.pck`. Godot is not required to play. The build is unsigned; verify its source and SHA-256 checksum before running it. Do not disable antivirus.

See [TESTING.md](TESTING.md) for a short Doge and Story test pass. Report **v0.2**, mode/stage/fighters, exact buttons and timing, expected versus actual behavior, and a short clip when possible. No online multiplayer is claimed.

## Source and assets

This repository is public. Git LFS is required for the source assets; clone and run `git lfs pull` before importing with Godot 4.7.2. Public availability does not grant a blanket code or asset redistribution license. Preserve attribution and third-party notices; ask before reusing characters, art, music, or models elsewhere. Blender masters, raw animation libraries, credentials, private acquisition notes, and local review evidence are excluded.

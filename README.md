# NRCU Platform Fighter — v0.3-web.4

**Unfinished alpha tester build — not a finished game.** Public frontend by [Arts Bro](https://github.com/realartsbro), with updated gameplay. [Release notes and known issues](RELEASE_NOTES_v0.3-web.4.md).

## Play

**[Play in your browser](https://123mikeyd.github.io/nrcu-platform-fighter/)** — click Play Now and keep the tab open while it loads. This is a large full-game download; use a good connection. Physical-phone memory/GPU viability is not certified.

**[Download the Windows tester](https://github.com/123mikeyd/nrcu-platform-fighter/releases/download/v0.3-web.4/NRCU-v0.3-web.4-Windows.zip)** · [Release and checksums](https://github.com/123mikeyd/nrcu-platform-fighter/releases/tag/v0.3-web.4)

Extract the entire ZIP, open `NRCU-Alpha`, and run `NRCU.exe` beside `NRCU.pck`. Choose **PLAY** for local matches or **STORY MODE** for the Bobo → Normal Ice Mage slice.

P1: **WASD** move/aim, **Space** jump, **F** basic, **G** special. **Escape** pauses. Universal Shield is retired. Teknium stores a neutral charge on a **fresh direction**; Up/Jump also jumps. Release then press Special to resume; normal release fires. See [controls](CONTROLS.md) and in-game How to Play.

## What's new

- No universal Shield; character defensive specials remain.
- Teknium's fresh-direction charge storage and updated help.
- Shared Return to Sender revival platforms after stock loss.
- Two-stage Story progression, current-encounter retries and final Restart Run.
- TurboFit's MoshIdleV004 in passive grounded gameplay.
- Preserved static public menus, browser touch controls/cancellation and rotate pause ownership.

Goo reduced rebound and GGB puddle immunity are **not implemented**. Mephisto size is unchanged; presentation/protection rules, minor HUD issues and balance remain under review. A misdirected Mephisto Up-special can self-KO.

## Testing boundaries

Current-contract tests cover controls, charge edges, defensive specials/Mosh idle, revival and two-stage Story. Story fixtures include forced outcomes, distinct from natural combat playtests. The historical full-suite baseline is **139 passed / 63 failed / 8 timed out**; this update does not claim an all-green legacy suite. Physical controllers/phones, long-session soak and exhaustive matchups are not certified. Desktop touch emulation is not physical-phone certification.

Report the exact tag, fighter/opponent/stage, inputs, expected versus actual behavior and a screenshot or clip. [Tester guidance](TESTING.md).

## Open project / build

Install **Godot 4.7.2**, Git and Git LFS. Clone this repository, run `git lfs pull`, import `project.godot`, let import finish, then F5. Compatibility renderer; no Blender installation is needed for the supplied assets. Preserve `.import`, `.uid` and import hooks. Generated `.godot`, builds and `.verification` are not versioned.

Run `python tools/test_release_contract.py --godot PATH_TO_GODOT` for the bounded current-contract checks. The broader portable legacy runner is `tools/run_all_tests.py`; inspect its help and keep evidence in ignored `.verification/`. Use matching official 4.7.2 export templates and **Windows Playtest** / **Web Browser** presets. [Web build details](WEB_BUILD.md).

Large models, textures, video and binary fixtures use Git LFS. Prefer cloning over GitHub's source ZIP so retrieval is explicit. Do not enable paid overages without agreement.

## Collaborate and sharing boundaries

Use Issues and separate branches/PRs. Avoid simultaneous edits to binary assets or the shared fighter controller. This sanitized collaboration snapshot and the author's working project do not automatically synchronize. [Shared testing workflow](skills/nous-game-dev-testing/SKILL.md).

No blanket open-source or asset redistribution license is granted. Public visibility is not permission to reuse art, characters, music or other assets separately. Ask first and preserve all bundled Godot/font notices. Private source libraries, Blender masters and historical evidence are excluded.

## FX Lab vNEXT (technical candidate; artist approval pending)

The FX Lab vNEXT authoring surface lives in `scenes/nrcu_fx_lab_vnext.tscn`. Its
production output is consumed by the shared resolver/renderer in
`scripts/fx_vnext/` and by the VS presentation adapter; authoring state is
separate from the read-only game consumer. `CLASH_OVERDRIVE` uses semantic
scopes (`ECHO_ONLY` for the vacuum pass and `EXCLUDE_PRIMARY` for impact
speedlines/distortion). The local adapter smoke path is a technical parity
fixture; it is not a substitute for a manual artist review or for testing the
full frontend MatchFlow route.

The live game consumer requires an approved V2 production plan through
`NRCU_FX_DATA_DIR` or the packaged `res://nrcu_fx_data` authority. If that store
is absent or empty, the VS adapter fails closed with
`fx_production_unavailable`; it does not claim a successful no-op FX binding.
The placeholder JSON files under `assets/vs/fx/` are not the live production
authority. The FX Lab has a deliberate external-workspace launcher, not a
normal Home/MatchFlow menu route:

```text
python tools/fx_review.py --engine <path-to-godot> --workspace <external-review-dir> --scenario CLASH_OVERDRIVE
```

For a local technical review, provide the matching Godot executable explicitly
(or set `GODOT_ENGINE` for the suite runner / `GODOT_BIN` for the review
launcher) and keep captures outside the repository. The runner requires each
suite to emit an explicit `done ... checks=N failures=0` marker; it rejects
parser/runtime errors even when Godot exits with code 0. Review workspaces must
also be outside the checkout (the launcher rejects `./review`, `./evidence`,
and other project subdirectories).

```text
python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd

# Windows cmd.exe:
set "FX_FINAL_STATIC_ONLY=1" && python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd --headless

# PowerShell:
$env:FX_FINAL_STATIC_ONLY="1"; python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd --headless

# POSIX shells:
FX_FINAL_STATIC_ONLY=1 python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_final_composite_test.gd --headless

python tools/run_godot_suite.py --engine <path-to-godot-console> --script res://tests/fx_vnext_matchflow_route_test.gd
python tools/fx_review.py --engine <path-to-godot> --workspace <external-review-dir> --scenario CLASH_OVERDRIVE
```

The default final-composite check performs mandatory GPU pixel readback and
therefore runs windowed on the Compatibility renderer. `FX_FINAL_STATIC_ONLY=1`
is an explicit static-contract mode for headless CI; it does not replace the
default readback gate.

Generated captures and logs belong in ignored `.verification/` or an external
review workspace; do not use `git add -A` for this project.

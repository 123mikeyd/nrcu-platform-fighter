# v0.3 compatibility integration

## Scope and ancestry

- Published preview parent: `c5ff8b0aad038be6cbb7a88aa26252f091d1e687`.
- Upstream pin: `d6256dddd01596f7f2b47a38808598dc39f29823`. A recovery-time `git ls-remote origin refs/heads/main` still returned this exact pin; this integration does not chase a moving branch.
- This is a merge, not a rewrite of published experimental history. The default remains `scenes/title.tscn`, with all five upstream autoloads. Upstream gameplay, art, tuning and roster are preserved.
- Optional entry: `scenes/experimental_full_game.tscn`, Teknium and Turbofit only, accepted movement/input, grounded jostle, three stocks and the authored Toy Shelf.
- Source comparison authenticates all 956 upstream paths. Only `.gitattributes`, `export_presets.cfg`, `tools/run_all_tests.py` and `tools/test_run_all_tests.py` differ; the latter two retain the existing stricter experimental test classifier. No upstream runtime source or asset differs.

## Compatibility changes

- Union both `.gitattributes` parents, including authenticated-resource and upstream import/project LF rules.
- Preserve upstream Windows Playtest and Web Browser preset definitions. Retain Web LAN as preset 2, add the current Mephisto raw phase catalog and exclude verification artifacts. A regression locates Web presets by platform/name rather than assuming preset 1 is the optional export.
- Suspend upstream semantic frontend focus while the preview owns native Controls and match input. Hide the upstream hand, retain the native pointer, and restore previous scope/pointer policy on exit. Original Game still returns to the upstream home route.
- Accept both historical home and current title defaults in the disposable full-game and legacy lab export helpers. Preserve hardlink/symlink refusal. The Python packaging test uses a small real-settings fixture instead of copying the entire media tree; it is not an export acceptance claim.
- Install actual generator-produced Mephisto and Witcheer profiles. Only `presenter_sha256` metadata changes; geometry and manual overrides do not. Install the matching seven-profile receipt and check every installed receipt path/hash in the provenance regression. Fresh generation reproduces all seven installed profile bytes. No imported-scene authentication pin is changed.
- Review the upstream fighter delta (tumble, source attribution and paired Mephisto), retain the byte-identical bot oracle, and update the fighter preservation pin. Both behavioral decision oracles still run, including 72,000 stage-bound comparisons. Adapt the Orb expiry test recipient to upstream `receive_hit_from`, asserting source attribution without changing boundary/damage semantics.
- Give the visual-geometry fixture an explicit runtime 16:9 viewport under upstream's expand policy. Add preview input-isolation, original-return and real-input combat/pause regressions.
- Refresh dependency inventories: 2,095 source paths and 29 raw resources. Existing literal resource edges close; explicit computed/raw resources include the new phase catalog. This is not proof of a new cold export.

## Verification recovery and results

The disk-full run was **not complete** despite the process having exited: its persisted report contains 508 of 674 selected tests (467 PASS, 41 FAIL). All retained frozen source hashes matched on recovery except the already-edited viewport fixture. All 67 LFS files matched the indexed SHA-256 and size; apparent status modifications were hydration/stat effects, not corrupt media. No media was rewritten.

- Untouched pinned-upstream baseline: **212 tests, 151 PASS / 61 FAIL**, smoke PASS. Its full source inventory was authenticated before and after a fresh-import, 90-second recheck of `test_teknium_grab_lifecycle`; that recheck completes with exactly the candidate's failure diagnostics rather than the original 30-second timeout.
- Exact-name continuation: **167 tests, 127 PASS / 40 FAIL**, smoke PASS. This includes the original-return test added after the interrupted sweep started.
- Historical partial plus continuation: **675 unique tests, 594 PASS / 81 FAIL**. Do not present this as one uninterrupted sweep or silently replace its failures.
- Explicit changed-scope/timeout rechecks plus the new combat regression: **676 unique current runners, 608 PASS / 68 FAIL**, no missing or duplicate names. Of the remaining failures, **60 match pinned upstream**, **6 match the retained published-preview baseline**, and **2 match a separately authenticated published-source overlay control**. Exact diagnostic/stack, return-code, timeout and completion-marker signatures are compared programmatically. No unmatched failure remains; the suite is nevertheless **not all green**.
- Changed-scope strict batch: 10/10 PASS; final receipt/provenance regression PASS; new real-input combat regression PASS. Ten slow additive tests were rerun with 240-second limits: nine PASS and the existing back-reach failure remains RED.
- Python tooling: **31/31 PASS**. Retained REDs cover title incompatibility in the legacy exporter and the stale Web-preset-index assumption.
- Native Xvfb/software-rendered checks: preview menu/selection/READY, jump, three-stock results/rematch, pause/change-fighters, projectile presentation, synthetic assigned-controller Start routing, Original Game return and stage visual geometry all PASS. A separate genuine parsed-key combat route approaches the opponent, emits Force Push, causes damage (captured HUD: Turbofit 8%), freezes the clock on Escape and resumes through the GUI. Initial neutral-special capture failed because the harness requested grab rather than directional Force Push; the failed evidence is retained and the corrected harness uses D+G. No actor/contact/damage state is injected.

The eight existing additive failures are:

- `test_core_ai_comparison_lab_layout`
- `test_core_combat_lab_layout`
- `test_core_defense_lab_ui`
- `test_core_ledge_lab_ui`
- `test_core_tek_swing_mode_exit`
- `test_core_tek_swing_reach_trace`
- `test_core_tek_swing_back_reach`
- `test_core_turbo_lab_ui`

The final two also fail native rechecks. Their published-source control authenticates all 1,722 HEAD-tracked paths, temporarily replaces only 61 changed text files in the existing integration worktree, runs the exact tests, then restores and verifies every candidate byte. It retains unreferenced v0.3 additions and a warm import cache, so it is **not an independent cold checkout**. Earlier historical PASS reports exist but were not accepted as final-source proof. These failures remain disclosed cumulative lab limitations, not fixed behavior or upstream failures.

## Evidence, review and boundaries

Ignored evidence: `.verification/v03/recovery/` (reconciliation, LFS audit, upstream preservation, scope/native/Python logs, generator output, source-control journal). The untouched earlier reports remain under `.verification/v03/full/`, `preview-baseline/`, and the separate upstream worktree. Native screenshots are under `.verification/core/full-game-stage-acceptance/` and `.verification/v03/original-return.png`.

The recovered independent review in `.verification/v03/review.log` found no blocking issue in the then-current integration delta. Its follow-up was interrupted by disk exhaustion and is not a completed review. Recovery adds tooling/fixture/provenance changes; the final narrow delta and final source hashes are supplied for a new independent parent review. This document is not release approval.

Recovery used only existing worktrees, no clone, new full source stage or export. Disk was checked before heavy operations; the recovery remained below the 3-GiB growth budget and above the 10-GiB free-space reserve. Immutable media remains hardlinked: do not edit it in place. The real export copier's hardlink guard remains intentional.

No fresh Web/PCK export, browser acceptance, physical gamepad, hardware-performance test, LAN publication, remote push or PR update is claimed here. Native acceptance does not substitute for those gates. Redistribution/attribution remains unresolved as previously disclosed. Parent owns final independent review and any remote update of draft PR #2.

## Reproduction

Prerequisites: Git LFS content, Python 3.11+, Godot `4.7.2.stable.official.ed1daf0bf`. Preflight free space and bound evidence before import/export; do not produce a new full project copy merely to run Python unit tests.

```sh
git lfs pull
python3 tools/run_all_tests.py --engine /path/to/godot --import-only --output .verification/v03/import
python3 tools/run_all_tests.py --engine /path/to/godot --output .verification/v03/full --timeout 240
python3 -m unittest discover -s tools -p 'test_*.py'
/path/to/godot --path . res://scenes/experimental_full_game.tscn
/path/to/godot --headless --path . --script res://scripts/tools/generate_character_collisions.gd -- --generate --output=res://.verification/v03/regenerated
```

The strict runner rejects engine errors even with exit zero. Retain named REDs, compare against the exact upstream and published-preview pins, and distinguish unchanged failures from acceptance of the optional native route. Never publish all-green or browser-ready claims from these results.

# NRCU v0.3 — Unfinished Alpha Playtest

## Play now — Windows

[Download NRCU-v0.3-Windows.zip](https://github.com/123mikeyd/nrcu-platform-fighter/releases/download/v0.3/NRCU-v0.3-Windows.zip)

Extract everything, open `NRCU-Alpha`, then run `NRCU.exe` with `NRCU.pck` beside it. Windows 64-bit; this is not a browser build. The executable is unsigned. Keep the bundled Godot and font notices.

P1: WASD move/aim, Space jump, F basic, G special, E shield. P2: arrows move/aim, Enter jump, K basic, L special, O shield. Escape pauses. Choose PLAY for local matches or STORY MODE for Bobo.

## Changes

- Integrates Arts Bro's [PR #1](https://github.com/123mikeyd/nrcu-platform-fighter/pull/1): title/home, secondary screens, character/stage selection, glove cursor, shared BackAction and pause/quit navigation, Story/results flow.
- Preserves the v0.2 gameplay work and adds the captured tumble, Bobo exclusions, collateral/contact routing, native Witcheer DefaultSwim and paired-Mephisto starter updates.
- Fixes character-preview native-pose measurements, perspective framing and live-preview initialization. Bobo's feet and the current Witcheer/Mephisto poses fit their preview windows.
- Corrects the Story briefing: Bobo has 400 HP and attacks with slow two-hit claws.
- Bundles required Godot license/copyright and font notices.

The unfinished VS presentation and VFX Lab are excluded. Later concurrent Mephisto experiments are not included. This release is a specific tested snapshot, not a claim that every ongoing development task is complete.

## Verification actually completed

- Fresh Godot 4.7.2 import and Windows release export succeeded.
- Final focused selection: **35/35 passed**, plus separate startup smoke.
- Preview framing matrix: **48/48 edge-clear rendered samples** across tested sizes/poses.
- Source rendered tests exercised local controls, combat, pause/rematch, input-only Story victory, result/replay/reset and return to menu. The local match result transition was forced for lifecycle testing, not claimed as a natural match win.
- Freshly extracted Windows executable driven through native keyboard/mouse events: title/home, Story briefing, movement/attacks reducing Bobo from 400 to 252 HP, pause and clean exit. Current GGB, Witcheer and Mephisto selection previews inspected separately.
- ZIP CRC, extracted-member hashes and bundled notice equality verified. Release packaging only changes the bundled README relative to that tested executable/PCK.

## Known issues — not an all-green release

The broader inherited 190-test selection returned **142 passed / 48 failed**. After the final live-preview initialization change, the focused 35-test selection was rerun; the entire 190-test selection was not rerun again. The preview repair introduced no new failures in the broad comparison.

Of those 48 failures, 44 reproduce with identical signatures on the incoming PR head; four reproduce against the captured local gameplay baseline. They include old animation/route expectations as well as unresolved contact, status and lifecycle checks. They are retained failures, not all dismissed as obsolete tests. Witcheer's old Run expectation differs from the intentionally installed DefaultSwim; the current electrocution contract passes. Separate legacy Teknium tests still expect older aerial labels; their ground-chain assertions pass.

Character kits and visual polish remain unfinished. Some gameplay views are dark. Physical gamepads, every attack/matchup and online multiplayer are not certified; no online multiplayer is offered. Use Issues for reproducible bugs and include v0.3, fighters, stage and exact inputs.

## Credits and sharing

Frontend contribution by [Arts Bro](https://github.com/realartsbro). Existing character/art attribution and ownership remain in effect. Public availability is not a blanket license to reuse or redistribute individual assets. See the repository's sharing boundaries and bundled notices.

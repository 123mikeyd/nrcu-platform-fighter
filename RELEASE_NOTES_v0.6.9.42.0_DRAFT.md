# NRCU v0.6.9.42.0 — DRAFT / UNPUBLISHED

**Candidate notes for review, not a release announcement.** The features below are present in candidate source. Their inclusion is not a claim of final art approval, completed release gates, or successful playback of an exported package. Publication requires separate authorization.

## What's new

- **Startup and Home:** a logo startup scene and a new Home layout with Local Match, Story Mode, Heavy Bag, and Controls / Moves.
- **Two-step match setup:** choose fighters, costumes and slots, then choose a stage before launching the match. The selected costume is passed into the fighter; selection availability is not a claim that every costume/move combination has been visually certified.
- **Doge Man:** grounded neutral Special now starts Super Doge Punch, with a committed windup rather than a held charge. His finite counter and Air Doge remain separate directional specials.
- **Witcheer:** grounded cane swipe, rising cane and low poke, plus held crouch; grounded side basics remain kicks. Focused source tests verify uninterrupted return to animated cane idle/crouch: the brief pre-cooldown Run/cane-hidden detour is fixed without changing attack timing or art.
- **Bobo:** a dedicated Down+basic aerial, separate from grounded Low Claw. There is no Down-special.
- **Mephisto:** regular ground/air basics and Meteor Heel are connected to the playable routes. Story uses the current fighter factory, not a separate historical demon boss. Installation does not certify final approval of all basics or the separate Boss_Meph carrying presentation.
- **TurboFit:** restored original 33-bone gameplay model with corrected standing arms and guitar grip, plus four selectable costumes: Black Russet, Midnight Indigo, Tangerine Denim and Swamp Moss. Grounded held Sound Orb keeps its existing inputs and timing. The separate legacy results visual and looping clap remain unchanged. Every-stage contact coverage is not claimed.
- **Character selection:** transparent, costume-specific portraits for Teknium, Witcheer and TurboFit, plus a transparent Amber Honey GGB portrait with translucent wings.
- **Teknium:** planted grounded low-sweep/crouch handling and a **provisional** descending-stamp down-air. The stamp still needs art review. Laser Blast remains a fresh-use, no-storage move.
- **Hermes Weaver stage:** the match route uses the revised gap-floor stage with a repair cycle. Stage appearance, collision readability and repeat-match behavior need playtesting together.

## Controls

The full current reference is [CONTROLS.md](CONTROLS.md). The old [v0.2 testing guide](TESTING.md) is retained as history, not current instructions.

| Player / device | Move / aim | Jump | Basic | Special |
|---|---|---|---|---|
| P1 keyboard | WASD | Space or W | F | G |
| P2 keyboard | Arrow keys | Enter or Up | K | L |
| Gamepad | Stick or D-pad | A | X | B |
| Touch | On-screen pad | Up | Attack | Special |

Direction changes the move. There is no universal shield. Esc pauses; R after a winner rematches. Connect controllers before launch; physical-controller acceptance remains separate from source or synthetic input checks.

Important candidate inputs (P1 keys):

- **Teknium neutral G:** Laser Blast. A fresh jump or fresh G press before the white flash cancels. No charge is stored; each use starts fresh. Holding G neither extends the warning line nor cancels.
- **Doge grounded neutral G:** tap for Super Doge Punch; no hold-charge or voluntary early cancel. Being hit or otherwise interrupted can stop it. Grounded S+F is the cape attack, not the historical Tyson route.
- **TurboFit grounded S+G:** hold both Down and Special to sustain Sound Orb and its performance; release either to stop. Interruption or losing the ground also ends the held orb. It pushes opponents and reflects reflectable projectiles, not universal melee invulnerability.
- **Witcheer grounded F / W+F / S+F:** cane swipe / rising cane / low poke. A/D+F stays a kick. Hold Down on solid ground to crouch, release to rise, and use a fresh basic press for the poke. On pass-through platforms, Down drops first before the attack routes. The cane mappings do not replace his aerial kit.
- **Bobo S+F:** Low Claw on the ground, dedicated down-air in the air; S+G is not a move.
- **Mephisto S+F:** low basic on the ground, Meteor Heel in the air.

## Please test and report

This is a **checklist to perform**, not a record of completed tests. Use the candidate's eventual exact build identifier in reports; do not substitute results from an older release.

1. Check startup completion and skipping separately. From Home, enter Local Match; select fighters and costumes, go to stage selection, go back, and then launch. Report clipped labels, incorrect portraits/costumes or stuck loading.
2. Test the inputs above with a passive opponent first, then bots. Try both facings, ground versus air, fresh taps versus holds, landing and interruption. Report exact spacing and input timing for misses.
3. For TurboFit, hold Down+Special through several performance loops, release each required button separately, and check that the orb ends on interruption. Do not use melee immunity as the expected result.
4. For Teknium, cancel before the white flash with a fresh jump and a fresh Special press in separate attempts; start again and check that nothing was stored. Review the provisional down-air's actual motion and planted low sweep.
5. For Witcheer, check idle, movement, jump/fall/landing and return from attacks, plus crouch → fresh poke → held crouch. Check Down+basic on a pass-through platform separately from solid ground. Report any cane or pose sticking; the previously observed pre-cooldown detour is now corrected.
6. Try the selectable stages, especially Hermes Weaver: watch gaps, visible floors versus collision, and rematch behavior. On Weaver, C starts the repair cycle and T toggles repeat.
7. From Home, select Story Mode directly. Check encounter entry, ordinary combat, results and progression. Record how far you naturally played; forced outcomes or isolated routing checks do not prove a full natural clear.
8. Check results and rematch, including TurboFit's clap, and pause/leave behavior. Report whether the problem survives a fresh match.
9. On the exact prospective browser package, test landscape touch on a real phone: loading, menu selection, movement, new attack inputs and sustained orb release. Record device/browser and observed performance. Desktop emulation is not phone evidence.
10. With an actual gamepad, test slot assignment, menus, stage confirm/back, gameplay and rematch. Esc remains the documented keyboard pause control; do not assume a gamepad pause mapping.

Include build identifier, platform, mode, stage, fighters/costumes, assigned devices, exact tapped/held buttons, expected versus observed behavior, and reproduction frequency. Remove private paths and unrelated desktop information from clips or screenshots.

## Known issues and verification limits

- **Unpublished draft:** package creation, exact-package replay and publication are not certified by these notes. No download size or release date is asserted.
- **Witcheer:** the return detour is fixed. A synthetic test that directly sets stocks to zero mid-HighKick still leaves the clip set for three ticks (no ghost hit); it bypasses production stock-loss cleanup. Actual damage, stock-loss/blast-zone and physics-triggered final-KO source probes clear the clip, ledger and presentation owner in both facings. This is not exhaustive KO/matchup certification.
- **Help:** controls now scroll within a reserved area above the key legend; the native overlap regression passes.
- **Weaver initialization:** required model setup now runs outside a debug-only assertion, preserving its existing parameters and art in release builds. Exact-package Story replay remains a separate verification gate.
- **Frontend:** native source regressions reproduced the shutdown leak, isolated dependency-subthread loading, and verified a narrow loading fix. Early-close testing additionally required draining outstanding requests. These local source checks do not certify exported-package shutdown or long-session memory behavior.
- **Presentation:** Teknium's down-air is provisional. Installed moves, costumes and frontend layouts are not blanket art or balance approval; Mephisto's regular basics and the separate Boss_Meph presentation must not be conflated.
- **Coverage:** focused source checks include return continuity, crouch handling, Help layout, and production HighKick interruption/KO cleanup. Source and synthetic checks are not exact exported-package replay, real-phone or physical-controller acceptance. Final package evidence remains a separate local review gate.
- Natural full Story, long sessions and every matchup/stage combination are not claimed verified here.

## Download

**No v0.6.9.42.0 download is announced by this draft.** Download links, measured sizes, package hashes and verified coverage belong here only after the actual artifacts and publication are separately authorized. Existing older release notes describe their own builds, not this candidate.

# NRCU v0.3-web.4 — unfinished tester update

This is a development playtest, not a finished or fully certified game. Both the browser and Windows packages contain the same completed gameplay changes.

## Changes
- Universal Shield is retired: E/O and controller shoulders no longer block or slow movement. Character-specific defensive specials remain.
- Teknium: hold neutral Special to charge. A **fresh direction** stores the charge; Up or dedicated Jump also requests a normal jump. Held Special cannot start a follow-up: release and press again to resume. Normal release still fires. Direction + Special from idle still selects the directional special.
- Shared **Return to Sender** platforms after stock loss, with a bounded arrival/hold and short departure protection. Move/jump to leave; attacking ends departure protection. Final stocks do not revive.
- Story now runs **Bobo → Normal Ice Mage**. First victory leads to a separate next briefing and Start; retries keep the current encounter and hero. Final victory offers Restart Run. R activates the Story result's primary action.
- TurboFit uses the approved **MoshIdleV004** during passive grounded gameplay. His move animations and actor movement are unchanged.
- Tester controls and in-game help updated. Existing public frontend, static menus, touch cancellation, portrait pause ownership and single-threaded browser export are preserved.

## Controls
P1: WASD move/aim, Space jump, F basic, G special. P2: arrows move/aim, Enter jump, K basic, L special. Controller: stick/D-pad aim, A jump, X basic, B special. Down drops through an upper platform. Escape pauses. Touch: left pad + right Attack/Special; Up jumps. No universal shield.

Doge Down+Special is a finite counter. Turbo Down+Special is his sound reflector. Mephisto girl neutral Special is a finite barrier; grounded Down+Special switches lead, Up+Special is paired teleport, side Special is girl ember/demon chain.

## Known issues / verification boundary
- Goo still reflects at full horizontal speed; reduced rebound was **not** implemented. GGB puddle immunity is pending.
- Mephisto presentation and protection rules remain under review; size was not changed. A misdirected Up-special can self-KO.
- Minor HUD/layout issues, unfinished balance and other inherited gameplay issues remain.
- Current-contract controls, charge edges, defensive windows, Mosh idle, revival and two-encounter Story are tested separately from obsolete fixtures. Story outcome tests include forced HP/blast-zone results; those do not prove natural combat victory.
- Historical full-suite baseline: **139 passed / 63 failed / 8 timed out**. This release does not claim to fix or rerun the whole legacy suite. The old E-to-store expectation is intentionally obsolete.
- Physical controllers/phones, long-session soak and exhaustive roster/stage matchups are not certified. Desktop Chrome touch emulation is not physical-phone certification.

Keep the checksum file with your download. Extract the entire Windows ZIP and run `NRCU-Alpha/NRCU.exe` beside its PCK. Preserve bundled Godot/font notices. Public visibility does not grant separate asset-reuse rights.

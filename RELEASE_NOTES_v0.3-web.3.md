# v0.3-web.3 — combined browser alpha

This prerelease combines mobile input and static menu presentation with Doge Man's counter and Teknium's revised special kit. It remains an unfinished alpha; previous Web and Windows releases are preserved.

## Changes
- Indexed multitouch movement, jump, basic, special, shield and pause controls; landscape gameplay with a portrait rotate guard that preserves manual pause ownership.
- Static selection/pause presentation without hidden live character previews; Web viewport clamp correction and desktop/mobile texture support.
- Web DOM touch cancellation aborts Tek's held charge rather than releasing a shot. Ordinary release still fires; stored charge is retained.
- Doge down-special counter and Tek charge/store/release, side kick, aimed delayed recovery and Holy Grenade/detonation. Tek kick and primitive effects remain provisional.

## Verification and limitations
- Six focused runners passed: Doge counter 185 checks, Tek kit 49, Tek safety 22, plus mobile provider, static presentation and touch/pause integration. Four frontend route/postmatch/pause runners passed.
- Local exported Chrome CDP replays covered 61 mobile/navigation actions and 38 combined-kit actions with no captured error events. Tek shots/grenade visibly changed Bobo HP; the generic basic-attack replay did not establish damage. Touch basic damage is covered by the engine integration test.
- This is NOT an all-green suite: unchanged `test_combat_input` reports 10 failures (four baseline basic-direction expectations and six replaced Tek-kit assumptions); `test_turbofit_physics_input` retains two baseline airborne-down-kick/Landing failures.
- All 128 original artwork files were preserved byte-for-byte. Runtime source is hash-verified against the tested candidate; the reviewed export is packaged unchanged, with commit-bound metadata added outside the PCK.
- Download is approximately **657.50 MiB** before transport compression: PCK **649,474,048 bytes**, WASM **39,514,754 bytes**. Memory use exceeds download size; use a strong connection. This is not a lightweight phone build.
- Desktop Chrome touch emulation is NOT Android/iOS, Safari, physical multitouch, notch/browser-toolbar, controller or phone memory/GPU certification. Browser rAF cadence is not engine profiling.
- Charge projectile contact remains a center ray, not a volumetric sweep. Existing alpha issues are not all fixed.

Publication uses a new immutable versioned archive, exact SHA-256/member/size checks and the existing restricted Pages workflow. `build.json` identifies the actual source commit; `manifest.json` lists relative public artifact names and hashes. Final hosted HTTPS verification is a separate post-deployment gate, not implied by local test results.

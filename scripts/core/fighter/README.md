# P2 movement-only seam

Use explicit preload paths; no global class cache, input-module, art or render dependency.

## Actor API

`fighter_actor.gd` extends CharacterBody3D:
- `profile: Resource = MovementProfile.new()` — assign before adding actor, or call reset after tuning.
- `runtime` — current FighterRuntime instance; reset replaces it.
- `simulate(commands: Dictionary) -> void` — call from match physics owner at **60 Hz**. Duplicate calls in the same engine physics frame are ignored. No autonomous process callback exists.
- `can_accept_jump() -> bool` — committed-state legality; external buffer must retain request until true, then consume once. Do not repeatedly manufacture jump edges.
- `reset_at(at: Vector3) -> void` — clears velocity, exceptions, support/drop state, jump/action clocks; resnapshots profile. Starts unsupported; next simulate reconciles actual terrain. Add to tree before calling.
- `telemetry() -> Dictionary` — locomotion, action, status, velocity (Vector3), grounded, air_jumps_left, transition_reason, tick, detached trace.

Commands: move_x float [-1,1], jump bool accepted edge, jump_held bool, jump_released bool, down bool edge, shield bool. Omitted values are neutral/false. Shield is **only a movement lock**, not defense.

Foot origin, z=0, unscaled 1.8-high / 0.4-radius capsule automatically created at y=0.9. Layer 2, mask 1, group `core_fighters`; fighters never support each other. Body owns position only in simulate/reset. Do not add a duplicate collider in the lab.

One-way terrain: CollisionObject3D on layer 1, group `core_pass_through`, metadata `top_y` = **world-space top height**. Ignore while rising/below the top; downward edge on support drops until feet clear top. Accepted jump wins over simultaneous down. Solid floor cannot be dropped. Static horizontal authored platforms are the tested scope; moving/sloped one-way geometry is not supported by this metadata contract.

## Pure runtime API

`FighterRuntime.new(definition: Resource = null)` takes a private deep snapshot. Call `reset(on_ground: bool = false)` before stepping. The shared Resource is never a runtime-state container and tuning edits do not alter active instances; recreate/reset actor to apply.

- `step(commands: Dictionary) -> void` — exactly one fixed 1/60 policy tick; no wall clock, engine tick, scene or input queue.
- `reconcile_contact(on_ground: bool, body_velocity: Vector3) -> void` — commit body collision result after movement. First terrain contact restores air jumps and starts landing lock; repeated support does not restart it. Losing support cancels pending startup/landing lock. Ceiling ends rising on contact tick.
- `can_accept_jump() -> bool`
- Public telemetry: `states`, `velocity`, `grounded`, `tick`, `air_jumps_left`.

Startup of N ticks occupies accepted tick T through T+N-1; launch is T+N. Release during startup is latched even if re-pressed or movement-locked. Rising release caps upward velocity to short speed; falling release does nothing. Air jump is immediate, resets fast fall, consumes separate resource. Walkoff consumes ground opportunity (including unlaunched startup), retains air jump; **no coyote window**. Landing of N ticks locks the next N steps; request is legal on the following step. Air gravity continues under movement lock. Normal/down fall speeds are downward caps; down only engages after rise ends.

Coordinator uses explicit legal locomotion transitions and status > action > locomotion arbitration, bounded 32-transition reason trace, idempotent reset. States: idle/walk/initial_dash/run/brake/turn/jump_startup/rising/falling/fast_fall/landing; action neutral/movement_lock/landing_lock; status normal/disabled. Disabled is an arbitration test seam, not implemented combat status lifecycle.

## Profile fields (units per second, acceleration units per second squared)

run_speed=8; ground_acceleration=60; ground_friction=70; turn_acceleration=90;
initial_dash_ticks=6; initial_dash_acceleration=90; run_threshold=0.7;
jump_startup_ticks=3; full_jump_speed=13; short_jump_speed=8; air_jump_speed=11.5;
air_jumps=1; gravity=32; air_speed=7; air_acceleration=22;
fall_speed=18; fast_fall_speed=26; landing_ticks=4.

Use nonnegative movement/window values, positive gravity, short_jump_speed <= full_jump_speed, fast_fall_speed >= fall_speed. No runtime tuning validation or optional coyote rule is claimed.

## Verification

`godot --headless --path . --script res://tests/test_core_movement*.gd` (one concrete file per command); same for test_core_actor*.gd. RED/GREEN evidence and aggregated results: `.verification/core/movement/`. Replay additionally runs at `--max-fps 30` and `--max-fps 144`, comparing identical same-build physics trace hashes. This is not cross-platform determinism or human feel acceptance. Legacy/input/lab files are owned separately. No combat, ledges, visuals or P3+ claims.

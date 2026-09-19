# Short action edge capture

`PlayerInputSource` is still a RefCounted physical-input adapter, not a simulation owner. The full-game session and combat lab explicitly enable event capture and forward unhandled input. No InputMap actions or global event dispatcher are installed.

## Contract

- Keyboard physical keycodes and assigned gamepad device/button IDs identify input. Echo and duplicate held-down events do not repeat actions.
- Real press/release pairs between physics samples survive until the next `sample(tick)`. At most one press and one release per action are retained for that sample. Multiple pulses of the same action coalesce; the **first press's direction wins**. There is no backlog to replay on subsequent ticks.
- `held` describes the event-authorized current button state, so a completed tap has both edges but is not held. GUI-consumed key downs cannot become action presses or keyboard movement through polling. Releases are also observed before GUI handling, preventing a consumed release from sticking an already accepted hold.
- Movement remains a current snapshot, not the press-time aim. Native analog polling and axial deadzone/magnitude are preserved. Each action can carry its own `InputFrame.pressed_axis`; the buffer falls back to `frame.axis` when this optional metadata is absent.
- The existing five-argument `sample_snapshot` remains polling-only. Its optional sixth `capture_events` argument drains the explicit event feed for deterministic synthetic-device tests. Existing callers need no changes. Owners that do not enable capture retain the old polling behavior.
- `reset()` clears retained edges and detects currently held native controls for release-before-repress suppression. Device, slot, loaded profile, and in-place binding changes invalidate pending old identities. Session/lab ownership boundaries drain already buffered engine events before clearing source state, so paused or pre-reset events cannot arrive after resume as fresh input.
- Lazy in-place rebinding uses the event adapter's prior physical state when the current event triggers identity detection: Godot's global Input state already includes that event. Old pending edges are discarded, genuinely pre-held controls remain release-before-repress suppressed, and a fresh current down is then processed once with its current direction. Unbound unhandled controls are observed for this distinction; synthetic pad prior state is retained without replacing live pad polling. Explicit lifecycle `reset()` still reseeds native held suppression, including previously observed unbound controls; it does not trust stale held values across the boundary.
- READY, pause/focus loss, rematch/full reset, stock lifecycle and disconnect still use the existing owner reset paths. AI-owned P2 is not fed human events. Owner teardown calls `shutdown()` to clear capture and disconnect the hotplug callback.
- Source sampling continues during hitstop; Match continues to own frozen actor clocks and buffer aging. Capture does not bypass landing/attack/status locks, increase the six-tick action buffer, shorten authored recovery, or simulate from rendering callbacks.

## Recording compatibility

`InputFrame` adds optional `pressed_axis` data encoded as action-to-two-number arrays. Empty metadata is omitted, so existing ordinary frame dictionaries and old recordings keep their previous shape. New recordings retain per-action direction through serialization, disk reload, buffer consumption and same-build Match/native actor replay. The recording reader validates optional axes. This is backward-compatible reading, **not** a guarantee that an older executable will interpret the new optional aim metadata correctly.

## Verification and limits

The five `tests/test_core_input_edge_capture*.gd` runners cover source capture, production session/lab routing, UI consumption, lifecycle boundaries, lock expiry, hitstop, synthetic gamepad identity/analog context, and captured-frame replay. See `.verification/core/input-edge-capture-fix/REPORT.md` for the original RED evidence and `.verification/core/input-edge-review-fixes/REPORT.md` for the binding-order fix, dispatched AI/human counterfactuals, final source pins and exact rerun inventory.

Native checks use parsed input events under Xvfb/Mesa software rendering. They are not physical-controller acceptance or browser latency measurements. The parent release workflow must export this exact candidate and verify real browser input before publication. A released neutral shield tap does not invent a held shield; existing defense rules remain authoritative. Capturing a short tap fixes source loss, not every report of combat feel or readability.

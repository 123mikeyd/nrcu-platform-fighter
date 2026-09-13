extends Node
# FrontendClock — the 60 Hz logical frontend tick (Step 0 §16).
#
# Interaction timing, token state machines and deterministic test counters run
# on this clock. Rendering still runs at the display refresh rate; ambient
# shader/render effects that gain nothing from a fixed clock stay off it.

const FPS := 60.0
const FRAME := 1.0 / FPS

signal tick(index: int)

var tick_index := 0
var _acc := 0.0

func _process(delta: float) -> void:
    # Clamp catch-up so a hitch cannot spiral into a burst of ticks.
    _acc = minf(_acc + delta, 0.25)
    while _acc >= FRAME:
        _acc -= FRAME
        tick_index += 1
        tick.emit(tick_index)

static func frames(seconds: float) -> int:
    return int(round(seconds * FPS))

static func seconds(frames_count: int) -> float:
    return float(frames_count) / FPS

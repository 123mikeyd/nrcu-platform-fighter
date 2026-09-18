extends Node
# Perf probe (dev tool): build the Character Select at its scalability worst
# case (30 roster fighters, four player bays) and sample the real frame rate
# for a few seconds. Windowed run only (headless FPS is meaningless).
#
#   godot --path <repo> --resolution 1280x720 res://tools/perf_probe.tscn
#
# Prints one line per second plus a summary; exits on its own.

const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")

const SAMPLE_SECONDS := 8.0
const SYNTH_FIGHTERS := 30

var _samples: Array[float] = []

func _ready() -> void:
    call_deferred("run")

func run() -> void:
    var css = load("res://scenes/character_select.tscn").instantiate()
    css.name = "PerfCSS"
    add_child(css)
    await get_tree().process_frame
    var cards: Array = []
    for i in SYNTH_FIGHTERS:
        var id := str(Roster.ids()[i % Roster.ids().size()])
        cards.append({"id": id, "name": "SYNTH %02d" % i})
    css.build(cards)
    var state = SelectionState.new()
    # Four active players so every bay renders its fighter.
    for i in 4:
        state.slots[i]["character"] = str(cards[i]["id"])
    css.open_with(state)
    for i in 60: await get_tree().process_frame
    var t := 0.0
    var acc := 0.0
    while t < SAMPLE_SECONDS:
        await get_tree().process_frame
        acc += get_process_delta_time()
        if acc >= 1.0:
            acc -= 1.0
            t += 1.0
            var fps := Performance.get_monitor(Performance.TIME_FPS)
            _samples.append(fps)
            print("perf: t=%ds fps=%.1f" % [int(t), fps])
    var mn := 9999.0
    var sum := 0.0
    for s in _samples:
        mn = minf(mn, s)
        sum += s
    print("perf summary: css30 frames=%d min=%.1f avg=%.1f" % [_samples.size(), mn, sum / maxf(1.0, float(_samples.size()))])
    get_tree().quit(0)

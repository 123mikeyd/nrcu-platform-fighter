extends Node
# Evidence shot harness (dev tool, not shipped UI): renders one frontend
# screen to a PNG at an exact resolution, so scalability and resolution QA
# are deterministic instead of click-automated.
#
# Usage (real window, NOT headless — rendering is required):
#   godot --path <repo> --resolution 1280x720 res://tools/evidence_shot.tscn -- \
#     --screen=css --out=C:/evidence/css_720.png
#   screens: title | home | css | sss | results | css30 | sss12
# The canvas_items stretch mode scales the 1280x720 design to the window, so
# 1920x1080 shots exercise the uniform-scaling path.
#
# args (after the bare --):
#   --screen=<name>   which screen to build (default css)
#   --out=<path>      PNG path (required)
#   --hover=<n>       hover/select index for css/sss (default 2 for css, 0 for sss)

const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")

func _ready() -> void:
    call_deferred("run")

func arg_value(key: String, fallback: String) -> String:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--" + key + "="):
            return a.substr(key.length() + 3)
    return fallback

func run() -> void:
    var screen := arg_value("screen", "css")
    var out := arg_value("out", "")
    if out == "":
        push_error("evidence_shot: --out=<path> is required")
        get_tree().quit(1)
        return
    var hover := int(arg_value("hover", "-1"))
    var shot_root: Control
    match screen:
        "title":
            shot_root = load("res://scenes/title.tscn").instantiate()
            add_child(shot_root)
        "home":
            shot_root = load("res://scenes/home.tscn").instantiate()
            add_child(shot_root)
        "css":
            shot_root = await _make_css(_roster_cards(Roster.ids()))
        "css30":
            var ids: Array = []
            for i in 30:
                ids.append("teknium" if i % 7 == 0 else Roster.ids()[i % 7])
            var cards: Array = []
            for i in 30:
                cards.append({"id": str(ids[i]), "name": "SYNTH %02d" % i, "palette": Roster.palette(str(ids[i]), i % 4)})
            shot_root = await _make_css(cards)
        "sss":
            shot_root = await _make_sss(_stage_slots(3))
        "sss12":
            shot_root = await _make_sss(_stage_slots(12))
        "results":
            shot_root = await _make_results()
        _:
            push_error("evidence_shot: unknown screen " + screen)
            get_tree().quit(1)
            return
    # let tweens/entry animations settle into their stable frames
    for i in 90: await get_tree().process_frame
    if hover >= 0:
        if shot_root.has_method("hover_slot"):
            shot_root.hover_slot(hover)
        for i in 30: await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    var err := image.save_png(out)
    if err != OK:
        push_error("evidence_shot: save failed " + str(err))
        get_tree().quit(1)
        return
    print("evidence_shot: %s -> %s (%dx%d)" % [screen, out, image.get_width(), image.get_height()])
    get_tree().quit(0)

func _roster_cards(ids: Array) -> Array:
    var cards: Array = []
    for id in ids:
        cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper(), "palette": Roster.palette(str(id), 0)})
    return cards

func _stage_slots(count: int) -> Array:
    var names := {"debug": "DEBUG ARENA", "toy_room": "TOY SHELF / BEDROOM", "sky": "SKY ISLANDS"}
    var tex := {"debug": "res://assets/menu/stage_debug.png", "toy_room": "res://assets/menu/stage_toy_room.png", "sky": "res://assets/menu/stage_sky.png"}
    var base := ["debug", "toy_room", "sky"]
    var slots: Array = []
    for i in count:
        var id: String = str(base[i % 3])
        var label: String = str(names[id])
        if i >= 3:
            label = "STAGE %02d" % i
        slots.append({"id": id if i < 3 else "synth%d" % i, "name": label, "tex": tex[id]})
    return slots

func _make_css(cards: Array) -> Control:
    var css = load("res://scripts/char_select.gd").new()
    css.name = "EvidenceCSS"
    css.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(css)
    await get_tree().process_frame
    css.build(cards)
    var state = SelectionState.new()
    if cards.size() >= 7:
        state.slots[0]["character"] = str(cards[0]["id"])
    css.open_with(state)
    return css

func _make_sss(slots: Array) -> Control:
    var sss = load("res://scripts/stage_select.gd").new()
    sss.name = "EvidenceSSS"
    sss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(sss)
    await get_tree().process_frame
    sss.build(slots)
    sss.open_with("debug", "toy_room")
    return sss

func _make_results() -> Control:
    var rs = load("res://scripts/result_screen.gd").new()
    rs.name = "EvidenceResults"
    rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(rs)
    await get_tree().process_frame
    var rows: Array = [
        {"index": 1, "name": "TEKNIUM", "stocks": 0, "damage": 132, "id": "teknium"},
        {"index": 2, "name": "DOGE MAN", "stocks": 3, "damage": 84, "id": "doge_man"},
        {"index": 3, "name": "GGB", "stocks": 0, "damage": 156, "id": "ggb"},
        {"index": 4, "name": "TURBOFIT", "stocks": 1, "damage": 118, "id": "turbofit"},
    ]
    rs.show_results(rows, true)
    rs.skip_wait()
    return rs

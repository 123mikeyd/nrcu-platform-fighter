extends Node
# Evidence shot harness (dev tool): renders one frontend screen to a PNG at an
# exact resolution, so scalability, resolution and state QA are deterministic
# instead of click-automated.
#
# Usage (real window, NOT headless — rendering is required):
#   godot --path <repo> --resolution 1280x720 --quit-after 500 res://tools/evidence_shot.tscn -- \
#     --screen=css --out=C:/evidence/css_720.png
#   screens: title | home | css | csscarry | css30 | sss | sss12 | results | resultsteam
# args (after the bare --):
#   --screen=<name>   which screen to build (default css)
#   --out=<path>      PNG path (required)
#   --hover=<n>       hover/select index for css/sss (default: none)

const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")
const MatchResultScript = preload("res://scripts/match_result.gd")

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
            shot_root = await _make_css(_roster_cards(Roster.ids()), hover)
        "csscarry":
            shot_root = await _make_css(_roster_cards(Roster.ids()), 2, true)
        "css30":
            var cards: Array = []
            for i in 30:
                var id := str(Roster.ids()[i % 7])
                cards.append({"id": id, "name": "SYNTH %02d" % i})
            shot_root = await _make_css(cards, -1)
        "sss":
            shot_root = await _make_sss(_stage_slots(3), hover)
        "sss12":
            shot_root = await _make_sss(_stage_slots(12), hover)
        "results":
            shot_root = await _make_results(false)
        "resultsteam":
            shot_root = await _make_results(true)
        _:
            push_error("evidence_shot: unknown screen " + screen)
            get_tree().quit(1)
            return
    for i in 90: await get_tree().process_frame
    if hover >= 0 and shot_root.has_method("hover_slot"):
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
        cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper()})
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

func _make_css(cards: Array, hover: int, carry := false) -> Control:
    var css = load("res://scenes/character_select.tscn").instantiate()
    css.name = "EvidenceCSS"
    add_child(css)
    await get_tree().process_frame
    css.build(cards)
    var state = SelectionState.new()
    if cards.size() >= 7:
        state.slots[0]["character"] = str(cards[0]["id"])
    css.open_with(state)
    if carry and cards.size() > 2:
        var hand = get_node_or_null("/root/Cursor").hand
        if hand != null:
            var motion := InputEventMouseMotion.new()
            motion.position = Vector2(640.0, 200.0)
            motion.relative = Vector2(30.0, 0.0)
            hand._input(motion)
        css._on_tile_entered(hover)
    return css

func _make_sss(slots: Array, hover: int) -> Control:
    var sss = load("res://scripts/stage_select.gd").new()
    sss.name = "EvidenceSSS"
    sss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var frame := Control.new()
    frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(frame)
    frame.add_child(sss)
    await get_tree().process_frame
    sss.build(slots)
    sss.open_with("debug", "toy_room")
    if hover >= 0:
        sss.hover_slot(hover)
    return sss

func _entry(player_index: int, fighter_id: String, placement: int, stocks: int, damage: int, team_id: int, eliminated: bool) -> Dictionary:
    return {
        "player_index": player_index,
        "fighter_id": fighter_id,
        "fighter_name": Roster.display_name(fighter_id).to_upper(),
        "team_id": team_id,
        "placement": placement,
        "stocks_remaining": stocks,
        "damage_percent": damage,
        "eliminated": eliminated,
        "elimination_order": -1 if not eliminated else placement,
        "is_winner": placement == 1,
    }

func _make_results(team_mode: bool) -> Control:
    var rs = load("res://scripts/result_screen.gd").new()
    rs.name = "EvidenceResults"
    rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(rs)
    await get_tree().process_frame
    var result
    if team_mode:
        var entries: Array = [
            _entry(1, "teknium", 1, 2, 41, 0, false),
            _entry(3, "ggb", 1, 1, 88, 0, false),
            _entry(2, "doge_man", 2, 0, 0, 1, true),
            _entry(4, "turbofit", 2, 0, 0, 1, true),
        ]
        result = MatchResultScript.from_entries("WIN", true, 0, entries)
    else:
        var entries: Array = [
            _entry(2, "doge_man", 1, 2, 88, -1, false),
            _entry(1, "teknium", 2, 0, 0, -1, true),
            _entry(3, "ggb", 3, 0, 0, -1, true),
            _entry(4, "turbofit", 4, 0, 0, -1, true),
        ]
        result = MatchResultScript.from_entries("WIN", false, -1, entries)
    rs.show_result(result, true)
    rs.finish_reveal()
    return rs

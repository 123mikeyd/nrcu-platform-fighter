extends Node
# Frozen review capture tool (packaging only — no game code is modified).
# Renders every requested UI state to a PNG at the exact window resolution.
#
#   godot --path <repo> --resolution 1280x720 --quit-after 20000 \
#     res://tools/review_states.tscn -- --out=<dir> [--only=core|all]
#
# Each state gets a fresh screen instance; the naming matches the review
# request. States that need the custom cursor drive it through its public API.

const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")
const MatchResultScript = preload("res://scripts/match_result.gd")

const FRAMES_SETTLE := 55
const FRAMES_SHORT := 26

var out_dir := ""

func _ready() -> void:
    call_deferred("run")

func arg_value(key: String, fallback: String) -> String:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--" + key + "="):
            return a.substr(key.length() + 3)
    return fallback

func hand() -> Control:
    var c = get_node_or_null("/root/Cursor")
    return c.hand if c != null else null

func arm_mouse(pos: Vector2) -> void:
    var h := hand()
    if h == null:
        return
    var m := InputEventMouseMotion.new()
    m.position = pos
    m.relative = Vector2(24.0, 0.0)
    h._input(m)

func focus_mode() -> void:
    var h := hand()
    if h != null:
        h.set_mode(1)

func set_focus(control: Control, anchor: Control) -> void:
    focus_mode()
    if control != null:
        control.grab_focus()
    var h := hand()
    if h != null and anchor != null:
        h.set_focus_target(anchor)

func find_anchor(node: Node, fallback: Node) -> Control:
    if node == null:
        return fallback as Control
    var a := node.find_child("CursorAnchor", true, false)
    if a != null:
        return a as Control
    if node.has_method("anchor"):
        return node.call("anchor") as Control
    return fallback as Control

func settle(frames := FRAMES_SETTLE) -> void:
    for i in frames:
        await get_tree().process_frame

func snap(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png(out_dir + "/" + name + ".png")
        print("review_state: " + name)

# ---------------------------------------------------------------- screens --
func make_home() -> Control:
    var n = load("res://scenes/home.tscn").instantiate()
    add_child(n)
    await settle(30)
    return n

func make_css(state) -> Control:
    var n = load("res://scenes/character_select.tscn").instantiate()
    add_child(n)
    await settle(6)
    var cards: Array = []
    for id in Roster.ids():
        cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper()})
    n.build(cards)
    n.open_with(state)
    await settle()
    return n

func make_sss() -> Control:
    var frame := Control.new()
    frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(frame)
    var sss = load("res://scripts/stage_select.gd").new()
    sss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    frame.add_child(sss)
    await settle(4)
    var slots: Array = [
        {"id": "debug", "name": "DEBUG ARENA", "tex": "res://assets/menu/stage_debug.png"},
        {"id": "toy_room", "name": "TOY SHELF / BEDROOM", "tex": "res://assets/menu/stage_toy_room.png"},
        {"id": "sky", "name": "SKY ISLANDS", "tex": "res://assets/menu/stage_sky.png"},
    ]
    sss.build(slots)
    sss.open_with("debug", "toy_room")
    await settle(80)
    return sss

func make_story() -> Control:
    var n = load("res://scenes/story_briefing.tscn").instantiate()
    add_child(n)
    await settle(4)
    var ids: Array = Roster.ids()
    ids.erase("ice_mage")
    n.build(ids)
    n.open()
    await settle()
    return n

func make_howto() -> Control:
    var n = load("res://scenes/how_to_play.tscn").instantiate()
    add_child(n)
    await settle()
    return n

func make_results(team := false) -> Control:
    var rs = load("res://scripts/result_screen.gd").new()
    rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(rs)
    await settle(6)
    var result
    if team:
        result = MatchResultScript.from_entries("WIN", true, 0, [
            _entry(1, "teknium", 1, 2, 41, 0, false),
            _entry(3, "ggb", 1, 1, 88, 0, false),
            _entry(2, "doge_man", 2, 0, 0, 1, true),
            _entry(4, "turbofit", 2, 0, 0, 1, true),
        ])
    else:
        result = MatchResultScript.from_entries("WIN", false, -1, [
            _entry(2, "doge_man", 1, 2, 88, -1, false),
            _entry(1, "teknium", 2, 0, 0, -1, true),
            _entry(3, "ggb", 3, 0, 0, -1, true),
            _entry(4, "turbofit", 4, 0, 0, -1, true),
        ])
    rs.show_result(result, true)
    rs.finish_reveal()
    await settle()
    return rs

func _entry(pi: int, fid: String, placement: int, stocks: int, dmg: int, team: int, elim: bool) -> Dictionary:
    return {"player_index": pi, "fighter_id": fid, "fighter_name": Roster.display_name(fid).to_upper(),
        "team_id": team, "placement": placement, "stocks_remaining": stocks, "damage_percent": dmg,
        "eliminated": elim, "elimination_order": -1 if not elim else placement, "is_winner": placement == 1}

func state_with(commits: Dictionary, kinds: Dictionary = {}) -> RefCounted:
    var s = SelectionState.new()
    for i in 4:
        if kinds.has(i):
            s.slots[i]["kind"] = kinds[i]
        if commits.has(i):
            s.slots[i]["character"] = commits[i]
    return s

# ------------------------------------------------------------------- main --
func run() -> void:
    out_dir = arg_value("out", "")
    if out_dir == "":
        push_error("review_states: --out=<dir> required")
        get_tree().quit(1)
        return
    DirAccess.make_dir_recursive_absolute(out_dir)
    var only := arg_value("only", "all")
    var core := only == "core"

    # --- Main Menu ---------------------------------------------------------
    for spec in [["main_play_focused", 0], ["main_story_focused", 1], ["main_help_focused", 2], ["main_quit_focused", 3]]:
        var h := await make_home()
        h.select_row(int(spec[1]), true)
        var row: Dictionary = h._rows[int(spec[1])]
        set_focus(row["hit"], find_anchor(row["hit"], row.get("anchor")))
        await settle()
        await snap(str(spec[0]))
        h.queue_free()
        await settle(4)
    var h2 := await make_home()
    var row1: Dictionary = h2._rows[1]
    var hit1: Button = row1["hit"]
    arm_mouse(hit1.get_global_rect().get_center())
    await settle(FRAMES_SHORT)
    await snap("main_mouse_hover")
    h2.queue_free()
    await settle(4)
    var h3 := await make_home()
    h3.select_row(0, true)
    set_focus(h3._rows[0]["hit"], find_anchor(h3._rows[0]["hit"], h3._rows[0].get("anchor")))
    await settle()
    await snap("main_keyboard_focus")
    h3.queue_free()
    await settle(4)
    var h4 := await make_home()
    h4.select_row(3, true)
    (h4._rows[3]["hit"] as Button).pressed.emit()
    await settle()
    await snap("main_quit_modal")
    var qs := h4.find_child("ActionStay", true, false)
    if qs != null:
        set_focus(qs as Control, find_anchor(qs, null))
        await settle(FRAMES_SHORT)
        await snap("main_quit_modal_stay_focused")
    var qq := h4.find_child("ActionQuit", true, false)
    if qq != null:
        set_focus(qq as Control, find_anchor(qq, null))
        await settle(FRAMES_SHORT)
        await snap("main_quit_modal_quit_focused")
    h4.queue_free()
    await settle(4)

    if core:
        # representative set for geometry review at other resolutions
        var rc1 := await make_css(SelectionState.new())
        await snap("css_all_populated_entry")
        rc1.queue_free()
        await settle(4)
        var rs1 := await make_sss()
        await snap("sss_default")
        rs1.queue_free()
        await settle(4)
        var rst := await make_story()
        await snap("story_default_briefing")
        rst.queue_free()
        await settle(4)
        var rhp := await make_howto()
        await snap("howto_default")
        rhp.queue_free()
        await settle(4)
        var rrs := await make_results(false)
        await snap("results_reveal_complete")
        rrs.queue_free()
        await settle(4)

    if not core:
        # --- Character Select ----------------------------------------------
        var c1 := await make_css(state_with({}, {0: "human", 1: "bot", 2: "bot", 3: "bot"}))
        await snap("css_fresh_no_selection")
        c1.queue_free()
        await settle(4)

        var c2 := await make_css(SelectionState.new())
        await snap("css_all_populated_entry")
        for i in 4:
            c2._on_bay_activated(i)
            await settle(FRAMES_SHORT)
            await snap("css_active_p%d" % (i + 1))
        # bay kind cycling on P3 (default CPU -> EMPTY -> HMN)
        c2._on_kind_clicked(2)
        await settle(FRAMES_SHORT)
        await snap("css_kind_empty")
        c2._on_kind_clicked(2)
        await settle(FRAMES_SHORT)
        await snap("css_kind_hmn")
        c2._on_kind_clicked(3)
        await settle(FRAMES_SHORT)
        await snap("css_kind_p4_empty")
        # back / ready focus
        c2._back.grab_focus()
        set_focus(c2._back, find_anchor(c2._back, null))
        await settle(FRAMES_SHORT)
        await snap("css_back_focused")
        var band: Control = c2.get_ready_band()
        band.grab_focus()
        set_focus(band, find_anchor(band, null))
        await settle(FRAMES_SHORT)
        await snap("css_ready_focused")
        # teams mode + team control focus
        c2._set_mode(1)
        await settle(FRAMES_SHORT)
        await snap("css_mode_teams")
        c2._set_mode(0)
        await settle(FRAMES_SHORT)
        c2.queue_free()
        await settle(4)

        var c3 := await make_css(SelectionState.new())
        arm_mouse(Vector2(640.0, 500.0))   # bays area = outside the roster field
        await settle(FRAMES_SHORT)
        await snap("css_hand_outside_roster")
        var tiles: Array = c3.get_tiles()
        arm_mouse(tiles[0].get_global_rect().get_center())
        c3._on_tile_entered(0)
        await settle(FRAMES_SHORT)
        await snap("css_hover_first")
        c3._on_tile_entered(1)
        await settle(FRAMES_SHORT)
        await snap("css_hover_move_2")
        c3._on_tile_entered(2)
        await settle(FRAMES_SHORT)
        await snap("css_token_carried")
        c3._leave_field()
        await settle()
        await snap("css_token_cancelled_return")
        c3._on_tile_entered(1)
        await settle(FRAMES_SHORT)
        c3._on_tile_pressed("doge_man")
        await settle()
        await snap("css_committed_doge")
        c3._on_tile_entered(2)
        await settle(FRAMES_SHORT)
        c3._on_tile_pressed("ggb")
        await settle()
        await snap("css_changed_to_ggb")
        # bay control focus states
        var bays: Array = c3.get_bays()
        bays[1].grab_focus()
        set_focus(bays[1], find_anchor(bays[1], null))
        await settle(FRAMES_SHORT)
        await snap("css_bay2_focused")
        var kind: Node = bays[1].find_child("KindControl", true, false)
        if kind != null:
            set_focus(kind as Control, find_anchor(kind, null))
            await settle(FRAMES_SHORT)
            await snap("css_bay2_kind_focused")
        c3.queue_free()
        await settle(4)

        # --- Stage Select --------------------------------------------------
        var s1 := await make_sss()
        await snap("sss_default")
        s1.hover_slot(1)
        await settle(FRAMES_SHORT)
        await snap("sss_stage_focused")
        var sback := s1.find_child("StageBack", true, false)
        if sback != null:
            set_focus(sback as Control, find_anchor(sback, null))
            await settle(FRAMES_SHORT)
            await snap("sss_back_focused")
        s1.queue_free()
        await settle(4)

        # --- Story ---------------------------------------------------------
        var st := await make_story()
        await snap("story_default_briefing")
        for id in st.roster_ids():
            st.select_fighter(str(id))
            await settle(FRAMES_SHORT)
            await snap("story_select_%s" % str(id))
        set_focus(st.back_button(), find_anchor(st.back_button(), null))
        await settle(FRAMES_SHORT)
        await snap("story_back_focused")
        set_focus(st.action_button(), find_anchor(st.action_button(), null))
        await settle(FRAMES_SHORT)
        await snap("story_start_focused")
        st.show_result(true)
        await settle(FRAMES_SHORT)
        await snap("story_result_win")
        st.show_result(false)
        await settle(FRAMES_SHORT)
        await snap("story_result_loss")
        st.queue_free()
        await settle(4)

        # --- How to Play ---------------------------------------------------
        var hp := await make_howto()
        await snap("howto_default")
        hp._on_tab_pressed("FIGHTERS")
        await settle(FRAMES_SHORT)
        await snap("howto_fighters_section")
        var fighters_tab: Control = hp.find_child("SectionFighters", true, false)
        if fighters_tab != null:
            var tab_hit: Node = fighters_tab.find_child("HitArea", true, false)
            set_focus((tab_hit if tab_hit != null else fighters_tab) as Control, find_anchor(fighters_tab, null))
            await settle(FRAMES_SHORT)
            await snap("howto_tab_focused")
            hp._on_tab_pressed("BASICS")
            await settle(FRAMES_SHORT)
        hp.set_profile("CONTROLLER")
        await settle(FRAMES_SHORT)
        await snap("howto_profile_controller")
        hp.set_profile("P2_KEYBOARD")
        await settle(FRAMES_SHORT)
        await snap("howto_profile_p2")
        var hback := hp.find_child("HelpBack", true, false)
        if hback != null:
            set_focus(hback as Control, find_anchor(hback, null))
            await settle(FRAMES_SHORT)
            await snap("howto_back_focused")
        hp.queue_free()
        await settle(4)

        # --- Results -------------------------------------------------------
        var rs := await make_results(false)
        await snap("results_reveal_complete")
        for akey in rs._actions.keys():
            var spec: Dictionary = rs._actions[akey]
            set_focus(spec["button"], spec["anchor"])
            await settle(FRAMES_SHORT)
            await snap("results_%s_focused" % str(akey))
        rs.queue_free()
        await settle(4)
        var rt := await make_results(true)
        await snap("results_team_win")
        rt.queue_free()
        await settle(4)

    print("review_states: done")
    get_tree().quit(0)

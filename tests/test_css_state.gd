extends SceneTree
# Doc 08 §4 — Character Select STATE MATRICES (WP-2a evidence).
#
# For mouse, keyboard and controller separately the matrix is driven through
# PUBLIC input only (real parsed device events and the engine's own focus
# navigation):
#
#   fresh entry -> candidate A -> candidate B -> leave roster -> re-enter ->
#   commit B -> browse C -> take the commit back (staged cancel) -> commit C ->
#   change active player with a chip in flight -> set the active player Empty
#   mid-browse
#
# and every step asserts: candidate; committed id; carried player; token
# parent; token state; active player; bay preview; Ready validity.
#
# Nothing here calls a private FSM helper (_on_tile_entered / _leave_field /
# _on_tile_pressed / _on_bay_activated). The screen's own mouse/keys/pad paths
# must produce the state.
#
# The locked contracts under test:
#   Doc 01 §2  fresh defaults preselect NO fighter (P1 Human / P2 CPU /
#              P3+P4 Empty) and cannot ready until the player builds a state;
#   Doc 01 §5  the token grammar: clean grab hand + the player's SEPARATE
#              token, carry on hover/focus while the station owns NO committed
#              pick (the ONE lift rule: a committed chip leaves its tile only
#              through A on another tile or the staged B take-back),
#              return home on cancel/leave, placement motion on confirm,
#              active-player switch resolves the previous player's carry first,
#              no sticky token;
#   Doc 01 §4  device ownership and Ready gating (>= 2 active, >= 1 Human);
#   Doc 04 §4  explicit token parents: TokenHomeLayer / CursorCarryLayer /
#              FighterTile token layer.

const UNASSIGNED := 0
const PLACED := 1
const CARRIED := 2
const RETURNING := 3
const PLACING := 4

var failures := 0
var host: Node = null
var css: Control = null
var hand: Control = null
var driver := "mouse"

func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL [%s]: %s" % [driver, message])

func frames(n: int) -> void:
    for i in n:
        await process_frame

func pad_button(index: JoyButton, pressed := true) -> InputEventJoypadButton:
    var event := InputEventJoypadButton.new()
    event.button_index = index
    event.pressed = pressed
    return event

func key_event(code: Key, pressed := true) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed
    return event

func motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.relative = Vector2(24.0, 0.0)
    return event

# --- device drivers (public paths) ------------------------------------------
#
# HARNESS NOTE: a headless run has no OS pointer, so the engine's GUI never
# emits mouse_entered/hover for a parsed motion event (verified: parse_input_event
# and Viewport.push_input both leave the GUI hover untouched). The mouse pass
# therefore drives the controls' OWN public signal entry points — the tile's
# `mouse_entered` / `gui_input` and the hand's engine `_input` callback, the
# exact events the engine itself delivers in a windowed run — and never a
# private screen FSM helper. The keyboard and controller passes drive real
# parsed device events through the tree (the harness supports those fully).

func mouse_move(at: Vector2) -> void:
    # The hand's engine input callback receives the motion exactly as the
    # engine would deliver it (the harness convention used by the frontend
    # input contract suite); it moves the authoritative hotspot without ever
    # warping the pointer.
    hand._input(motion(at))

func hover_enter(index: int) -> void:
    # The public mouse entry the engine emits when the pointer crosses a tile.
    (css.get_tiles()[index] as Control).mouse_entered.emit()

func click(control: Control, at: Vector2) -> void:
    # The engine delivers mouse buttons to a custom Control's `_gui_input`
    # virtual callback (the repo's established harness convention; the
    # `gui_input` *signal* is only connected by handlers that opt in).
    mouse_move(at)
    var down := InputEventMouseButton.new()
    down.button_index = MOUSE_BUTTON_LEFT
    down.position = at
    down.pressed = true
    control._gui_input(down)
    var up := InputEventMouseButton.new()
    up.button_index = MOUSE_BUTTON_LEFT
    up.position = at
    up.pressed = false
    control._gui_input(up)

func tile_center(index: int) -> Vector2:
    return (css.get_tiles()[index] as Control).get_global_rect().get_center()

func bay_center(index: int) -> Vector2:
    return (css.get_bays()[index] as Control).get_global_rect().get_center()

func control_center(control: Control) -> Vector2:
    return control.get_global_rect().get_center()

func ensure_focus_mode() -> void:
    # §2: FOCUS is claimed by meaningful frontend input (a real nav event). The
    # headless harness starts in MOUSE mode because no pointer events arrive.
    if hand.mode == 1:
        return
    if driver == "controller":
        Input.parse_input_event(pad_button(JOY_BUTTON_DPAD_DOWN, true))
        await frames(2)
        Input.parse_input_event(pad_button(JOY_BUTTON_DPAD_DOWN, false))
    else:
        Input.parse_input_event(key_event(KEY_DOWN, true))
        await frames(2)
        Input.parse_input_event(key_event(KEY_DOWN, false))
    await frames(3)

func accept() -> void:
    # The semantic ui_accept path (keyboard Enter / controller A).
    if driver == "controller":
        Input.parse_input_event(pad_button(JOY_BUTTON_A, true))
        await frames(3)
        Input.parse_input_event(pad_button(JOY_BUTTON_A, false))
    else:
        Input.parse_input_event(key_event(KEY_ENTER, true))
        await frames(3)
        Input.parse_input_event(key_event(KEY_ENTER, false))
    await frames(2)

func focus_tile(index: int) -> void:
    (css.get_tiles()[index] as Control).grab_focus()
    await frames(3)

func drive_enter(index: int) -> void:
    # Start candidate + carry on a roster tile: hover (mouse) or focus
    # (keyboard/controller).
    if driver == "mouse":
        mouse_move(tile_center(index))
        hover_enter(index)
        await frames(4)
    else:
        await ensure_focus_mode()
        await focus_tile(index)
        await frames(3)

func drive_commit(index: int) -> void:
    if driver == "mouse":
        click(css.get_tiles()[index] as Control, tile_center(index))
        await frames(4)
    else:
        await focus_tile(index)
        await accept()

func drive_leave() -> void:
    # Leave the roster: the mouse path moves the hotspot out of the populated
    # roster envelope AND fires the field's own GUI mouse exit — the entry the
    # engine emits when the pointer really leaves the field (the deterministic
    # boundary of ledger C-004/C-005); the semantic path moves focus off the
    # roster (to the header Back).
    if driver == "mouse":
        mouse_move(Vector2(640.0, 30.0))
        css.get_node("ReferenceFrame/RosterField").mouse_exited.emit()
        await frames(5)
    else:
        var back: Control = css.get_node("ReferenceFrame/Header/BackAction")
        back.grab_focus()
        await frames(5)
    await frames(2)

func drive_take_back() -> void:
    # The ONE sanctioned lift of a COMMITTED chip: the staged cancel's stage 2,
    # driven by a real parsed device event (pad B for the controller pass, the
    # ui_cancel key Esc for the mouse and keyboard passes). Never a private call.
    if driver == "controller":
        Input.parse_input_event(pad_button(JOY_BUTTON_B, true))
        await frames(3)
        Input.parse_input_event(pad_button(JOY_BUTTON_B, false))
    else:
        Input.parse_input_event(key_event(KEY_ESCAPE, true))
        await frames(3)
        Input.parse_input_event(key_event(KEY_ESCAPE, false))
    await frames(5)

func drive_activate_bay(index: int) -> void:
    if driver == "mouse":
        click(css.get_bays()[index] as Control, bay_center(index))
        await frames(3)
    else:
        (css.get_bays()[index] as Control).grab_focus()
        await frames(2)
        await accept()

func drive_activate_kind(index: int) -> void:
    var bay = css.get_bays()[index]
    if driver == "mouse":
        (bay.state_control("kind") as Button).pressed.emit()
        await frames(3)
    else:
        (bay.state_control("kind") as Control).grab_focus()
        await frames(2)
        await accept()

func tile_index_of(id: String) -> int:
    # Local lookup through the public tile read (no screen internals).
    var tiles: Array = css.get_tiles()
    for i in tiles.size():
        if str((tiles[i] as Control).fighter_id) == id:
            return i
    return -1

# --- assertions -------------------------------------------------------------

func token_parent_name(player: int) -> String:
    var token = css.token_view(player)
    if token == null or token.get_parent() == null:
        return ""
    return str(token.get_parent().name)

func run():
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    hand = root.get_node_or_null("/root/Cursor").hand
    check(hand != null, "cursor service reachable")
    if hand == null:
        quit(1)
        return
    await matrix(vs, "mouse")
    await matrix(vs, "keyboard")
    await matrix(vs, "controller")
    if host != null and is_instance_valid(host):
        host.queue_free()
    await process_frame
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: css state matrices (fresh defaults, device rules, token FSM, no sticky token, carry presentation)")
    quit(0)

func matrix(vs, device: String) -> void:
    driver = device
    host = await vs.enter(self)
    css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "character select mounted and idle")
        return
    var state = host.selection_state
    var tiles: Array = css.get_tiles()
    var bays: Array = css.get_bays()
    var a: int = tile_index_of("doge_man")
    var b: int = tile_index_of("ggb")
    var c: int = tile_index_of("mephisto")
    await frames(4)

    # --- fresh entry --------------------------------------------------------
    check(int(css.get_active()) == 0, "an entry starts on P1")
    for i in 4:
        check(str(state.slots[i]["character"]) == "", "no fighter is preselected (P%d)" % (i + 1))
    check(css.token_state(0) == UNASSIGNED, "P1's token starts UNASSIGNED")
    check(token_parent_name(0) == "TokenHomeLayer", "the unassigned token is owned by TokenHomeLayer")
    check(not css.token_view(0).visible, "an unassigned token is hidden")
    check(not hand.is_carrying(), "the hand carries nothing at entry")
    check(not css.ready_allowed(), "the fresh configuration cannot ready")
    check(bays[0].presented_fighter() == "", "the active bay shows no committed fighter")

    # --- candidate A -> candidate B ----------------------------------------
    await drive_enter(a)
    check(int(css.get_candidate()) == a, "candidate A is the hovered/focused tile")
    check(int(css.get_carried_by()) == 0, "the active player's token is carried (carried_by)")
    check(css.token_state(0) == CARRIED, "P1's token state is CARRIED")
    check(token_parent_name(0) == "CursorCarryLayer", "the carried token is owned by CursorCarryLayer")
    check(hand.is_carrying() and hand.visual == 1, "the clean grab/pinch carry presentation is active")
    check(hand.carried_token() == css.token_view(0), "the hand carries the player's SEPARATE token object")
    check(css.token_view(0).player_color().is_equal_approx(hand.carried_token().player_color()),
        "the carried token keeps its per-player colour")
    check(bays[0].presented_fighter() == "doge_man", "the active bay previews candidate A")
    await drive_enter(b)
    check(int(css.get_candidate()) == b, "candidate B replaces candidate A")
    check(int(css.get_carried_by()) == 0 and css.token_state(0) == CARRIED, "the same player's token stays carried")

    # --- leave roster / re-enter -------------------------------------------
    await drive_leave()
    check(int(css.get_candidate()) == -1, "leaving the roster clears the candidate")
    check(int(css.get_carried_by()) == -1, "leaving the roster cancels the carry")
    check(not hand.is_carrying(), "the hand is free after leaving the roster")
    await frames(12)
    check(css.token_state(0) == UNASSIGNED, "the uncommitted token returns home (state %d)" % css.token_state(0))
    check(token_parent_name(0) == "TokenHomeLayer", "…and is owned by TokenHomeLayer again")
    check(not css.token_view(0).visible, "…and is hidden at home")
    check(bays[0].presented_fighter() == "", "the bay returns to its committed (blank) presentation")
    check(str(state.slots[0]["character"]) == "", "leaving never committed a fighter")
    await drive_enter(b)
    check(css.token_state(0) == CARRIED and hand.is_carrying(), "re-entering lifts the token again")

    # --- commit B -----------------------------------------------------------
    await drive_commit(b)
    check(str(state.slots[0]["character"]) == "ggb", "commit B writes the committed fighter")
    check(css.token_state(0) == PLACING or css.token_state(0) == PLACED,
        "the commit enters the placement motion (state %d)" % css.token_state(0))
    check(not hand.is_carrying(), "the hand is free after the commit")
    await frames(20)
    check(css.token_state(0) == PLACED, "the placement motion settles PLACED")
    check(token_parent_name(0) == "TokenLayer", "the placed token is owned by the tile's token layer")
    check(int(css.get_carried_by()) == -1, "no carry survives the commit")
    check(bays[0].presented_fighter() == "ggb", "the bay presents the committed fighter")
    check(not css.ready_allowed(), "one active fighter is not ready")

    # --- browse C / leave the roster (a COMMITTED chip is never lifted) -----
    await drive_enter(c)
    check(int(css.get_candidate()) == c, "browsing another tile moves the candidate")
    check(css.token_state(0) == PLACED,
        "browsing NEVER lifts the committed token (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "browsing a committed station puts nothing in the hand")
    check(token_parent_name(0) == "TokenLayer", "the committed chip stays on its own tile while browsing")
    check(bays[0].presented_fighter() == "mephisto", "the bay previews candidate C before commit")
    check(str(state.slots[0]["character"]) == "ggb", "browsing never changes the committed fighter")
    await drive_leave()
    await frames(20)
    check(str(state.slots[0]["character"]) == "ggb", "leaving the roster keeps the committed fighter")
    check(css.token_state(0) == PLACED, "the committed token is still PLACED on its tile")
    check(token_parent_name(0) == "TokenLayer", "…owned by the committed tile")
    check(bays[0].presented_fighter() == "ggb", "the bay returns to the committed fighter")
    check(not hand.is_carrying(), "no sticky carry after leaving the roster")

    # --- commit C -----------------------------------------------------------
    await drive_enter(c)
    await drive_commit(c)
    check(str(state.slots[0]["character"]) == "mephisto", "commit C replaces the committed fighter")
    await frames(20)
    check(css.token_state(0) == PLACED, "the token is PLACED on the new tile")
    check(token_parent_name(0) == "TokenLayer", "the token moved to the new tile's token layer")

    # --- change active player with a chip IN FLIGHT -------------------------
    # A carry only exists for a player WITHOUT a committed pick, so the journey
    # takes the committed chip back with the staged cancel (B / Esc) first.
    await drive_take_back()
    check(str(state.slots[0]["character"]) == "", "the staged cancel takes the committed chip back (stage 2)")
    check(int(css.get_carried_by()) == 0, "precondition: P1's token is carried (uncommitted)")
    await drive_activate_bay(1)
    check(int(css.get_active()) == 1, "the station activation changes the active player")
    check(int(css.get_carried_by()) == -1, "changing the active player resolves the previous player's carry")
    check(not hand.is_carrying(), "the hand is free after the switch")
    await frames(20)
    check(css.token_state(0) == UNASSIGNED, "the taken-back (uncommitted) token returns home")
    check(token_parent_name(0) == "TokenHomeLayer", "…owned by TokenHomeLayer")
    # The take-back released P1's station; re-commit it through the SAME public
    # path so the rest of the matrix keeps its two-fighter configuration.
    await drive_activate_bay(0)
    await drive_enter(a)
    await drive_commit(a)
    await frames(20)
    check(str(state.slots[0]["character"]) == "doge_man", "P1 re-commits a fighter through the public path")
    check(css.token_state(0) == PLACED, "…and its chip is PLACED again (state %d)" % css.token_state(0))
    await drive_activate_bay(1)
    check(int(css.get_active()) == 1, "the matrix continues on the second station")

    # --- set the active player Empty mid-browse -----------------------------
    await drive_enter(b)
    check(int(css.get_carried_by()) == 1, "precondition: P2's token is carried")
    await drive_activate_kind(1)
    check(str(state.slots[1]["kind"]) == "empty", "the kind control set the station Empty")
    check(int(css.get_carried_by()) == -1, "Empty cancels the carried token")
    await frames(24)
    check(css.token_state(1) == UNASSIGNED, "an Empty player's token is UNASSIGNED")
    check(token_parent_name(1) == "TokenHomeLayer", "…owned by TokenHomeLayer")
    check(not css.token_view(1).visible, "…and hidden")
    check(bays[1].input_readout() == "" and not bays[1].difficulty_row_visible(),
        "an Empty bay shows neither input nor difficulty")

    # --- Ready validity through the ONE authority ---------------------------
    check(not css.ready_allowed(), "P1 alone (P2 now Empty) cannot ready")
    await drive_activate_kind(1)              # EMPTY -> HUMAN
    check(str(state.slots[1]["kind"]) == "human", "the kind control cycles EMPTY -> HUMAN")
    check(str(state.slots[1]["character"]) == "", "an Empty->Human station preselects NO fighter")
    check(not css.ready_allowed(), "a Human without a fighter cannot ready")
    await drive_enter(b)
    await drive_commit(b)
    await frames(20)
    check(str(state.slots[1]["character"]) == "ggb", "P2 commits its fighter through the same path")
    check(css.ready_allowed(), "two active players with >= 1 Human are ready")
    check(bays[1].input_readout() == "KEYBOARD 2" and bays[1].input_readout_valid(),
        "P2 Human reads a valid INPUT KEYBOARD 2")
    check(css.get_ready_band().is_shown(), "the Ready band appears once the authority passes")

    # device ownership: a Human whose pad is gone cannot ready
    host.selection_state.slots[2]["kind"] = "human"
    host.selection_state.slots[2]["character"] = "ggb"
    css.refresh_devices()
    check(not css.ready_allowed(), "P3 Human without a pad cannot ready (CONNECT CONTROLLER)")
    check(css.get_bays()[2].input_readout() == "CONNECT CONTROLLER", "the bay says CONNECT CONTROLLER")
    css.set_connected_pads([0])
    check(css.ready_allowed(), "connecting a pad makes the slot valid again (hotplug refresh)")
    check(css.get_bays()[2].input_readout() == "PAD 1", "…and the bay reads PAD 1")
    css.set_connected_pads([])
    host.selection_state.slots[2]["kind"] = "empty"
    host.selection_state.slots[2]["character"] = ""
    css.refresh_devices()
    check(css.ready_allowed(), "removing the pad-only station restores the valid configuration")

    vs.free_hosts(self)
    await frames(2)

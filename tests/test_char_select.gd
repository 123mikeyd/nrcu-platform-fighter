extends SceneTree
# Character Select — canonical interaction contract (corrective Doc 04 + Doc 01
# §2/§4/§5). Migrated to the LOCKED fresh-default contract:
#
#   * P1 HUMAN / no fighter / Keyboard 1, P2 CPU / no fighter / NORMAL,
#     P3/P4 EMPTY — NO fighter is preselected anywhere (Doc 01 §2);
#   * kind is changed in the PlayerBay and a fighter commit NEVER silently
#     turns an EMPTY slot into a Human one (Doc 04 §6);
#   * token FSM: UNASSIGNED -> CARRIED -> PLACING -> PLACED, RETURNING -> home,
#     with the carry on the clean grab hand + the separate per-player token;
#   * Ready is decided by the ONE validation authority (>= 2 active, >= 1
#     Human, valid devices, both teams) — never a rule set in the screen.
#
# The owner-directed suites at the END of this file each drive the REAL path the
# finding came from:
#   * real_route_entry_suite   (1) THE ENTRY CHIP in the first visible CSS frame
#                              after the shipped Main PLAY route — a real pad
#                              accept and a real mouse click — asserted before
#                              any input reaches the CSS: the CARRY grip with
#                              the chip in the hand, never the ordinary pointer.
#                              The mouse pass also walks the owner journey
#                              (place -> existing pose rule -> pad-B take-back);
#   * roster_tile_anchor_suite (2) the roster tile's focus-hand anchor: the
#                              fingertip in the tile's lower-right region and
#                              the drawn body clear of the name's font-measured
#                              extent, on EVERY tile;
#   * hover_pose_gate_suite    (3) the pinch belongs to the chip's OWN tile —
#                              hovering any other fighter while a chip is
#                              committed draws the ordinary pointer;
#   * deselect_committed_suite (4) A / left-click on the COMMITTED tile
#                              DE-SELECTS — the pick goes back into the hand
#                              through the same take-back the staged cancel uses
#                              (one end state for A, the pointer and B).
#
# Composition/geometry invariants live in tests/test_css_composition.gd; the
# Doc 08 §4 public-input state matrices live in tests/test_css_state.gd.
const Support = preload("res://tools/acceptance_support.gd")
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

# TokenView.State ordinals (presentation states the screen drives).
const UNASSIGNED := 0
const PLACED := 1
const CARRIED := 2
const RETURNING := 3
const PLACING := 4

func frames(n: int) -> void:
    for i in n:
        await process_frame

func arm_mouse(hand, at: Vector2) -> void:
    # §3: hover is armed by genuine pointer motion; the hotspot must land on
    # the tile for the roster interaction to start.
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.relative = Vector2(30.0, 0.0)
    hand._input(motion)

func run():
    # WP-0 steps 7-8: the frontend route runs in the MatchFlow host (the in-arena
    # char/stage panels are gone); the interaction contract below is unchanged.
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var host = await vs.enter(self)
    var css = host.char_select()
    check(css != null, "character select exists")
    if css == null:
        host.queue_free(); await process_frame; quit(1); return
    var hand = root.get_node_or_null("/root/Cursor").hand
    check(hand != null, "cursor service reachable")
    var state = host.selection_state
    check(state != null and state.slots.size() == 4, "persistent selection state exists with four slots")
    await create_timer(0.6).timeout

    # --- fresh defaults: nothing is preselected anywhere (Doc 01 §2) --------
    for i in 4:
        check(str(state.slots[i]["character"]) == "", "slot %d has NO preselected fighter" % (i + 1))
    check(str(state.slots[0]["kind"]) == "human", "P1 is Human")
    check(str(state.slots[1]["kind"]) == "bot", "P2 is CPU")
    check(str(state.slots[2]["kind"]) == "empty" and str(state.slots[3]["kind"]) == "empty", "P3/P4 are Empty")
    check(str(state.slots[1]["difficulty"]) == "normal", "P2 CPU difficulty starts NORMAL")
    check(int(state.slots[0]["device"]) == -1, "P1 input is seeded as Keyboard 1 (legacy -1 marker)")
    var bays: Array = css.get_bays()
    check(bays[0].input_readout() == "KEYBOARD 1" and bays[0].input_readout_valid(), "P1 bay reads INPUT KEYBOARD 1")
    check(bays[1].input_readout() == "" and bays[1].difficulty_row_visible(), "the CPU bay shows NORMAL and hides the input assignment")
    check(bays[2].input_readout() == "" and not bays[2].difficulty_row_visible(), "an Empty bay shows neither control")
    check(not css.ready_allowed(), "a fresh CSS cannot ready (no fighters yet)")
    check(not css.get_ready_band().is_shown(), "no ready band while the configuration is invalid")

    # --- tokens: one per player, screen-local FSM -------------------------
    check(css.token_view(0) != null and css.token_view(3) != null, "four token views exist")
    # ENTRY CONTRACT (owner requirement): with P1 having NO committed pick the
    # chip RIDES THE CURSOR — the "no character selected" state IS the token in
    # the hand (the CARRY grip with the chip in it, from the first visible
    # frame) — while an UNASSIGNED player (P4, Empty) keeps its token at home.
    check(css.token_state(0) == CARRIED and hand.is_carrying(),
        "the active player's chip rides the cursor at entry (state %d, carried_by %d)"
        % [css.token_state(0), int(css.get_carried_by())])
    check(css.token_view(0).visible and str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "the entry chip is drawn in the cursor carry layer")
    check(hand.visual == 1, "the CARRY grip is what the entry draws (visual %d)" % int(hand.visual))
    check(css.token_state(3) == UNASSIGNED and not css.token_view(3).visible,
        "an UNASSIGNED (Empty) player's token stays hidden at home")
    check(css.token_view(3).get_parent() == css.token_home_layer(), "an unassigned token lives in the explicit home layer")

    # --- candidate vs committed -------------------------------------------
    var tiles: Array = css.get_tiles()
    check(tiles.size() == 7, "seven roster tiles")
    var tile_ggb: int = css._tile_index_of("ggb")
    # mouse motion arms hover; entering a tile starts the carry
    arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
    css._on_tile_entered(tile_ggb)
    check(css.get_candidate() == tile_ggb, "hovering sets the candidate tile")
    check(hand.is_carrying(), "entering the roster carries the active player's token")
    check(hand.visual == 1, "the carry presentation is active while carrying")
    check(css.token_state(0) == CARRIED, "P1 token state is CARRIED")
    check(str(state.slots[0]["character"]) == "", "hovering never writes the committed fighter")
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer", "the carried token lives in the cursor carry layer")
    check(bays[0].presented_fighter() == "ggb", "the active bay large-previews the candidate before commit")
    # leaving the roster returns the token without committing
    css._leave_field()
    check(not hand.is_carrying(), "leaving the roster frees the hand")
    await create_timer(0.25).timeout
    check(css.token_state(0) == UNASSIGNED, "the unassigned token returns home and hides (state %d)" % css.token_state(0))
    check(css.token_view(0).get_parent() == css.token_home_layer(), "the returned token is owned by the home layer again")
    check(str(state.slots[0]["character"]) == "", "leaving the roster never changed the committed fighter")
    check(bays[0].presented_fighter() == "", "the bay returns to its committed (blank) presentation")

    # --- commit: PLACING motion, then PLACED on the tile -------------------
    arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
    css._on_tile_entered(tile_ggb)
    css._on_tile_pressed(str(css._cards[tile_ggb]["id"]))
    check(str(state.slots[0]["character"]) == "ggb", "confirm commits the fighter to the active player")
    check(css.token_state(0) == PLACING, "the token enters the authored PLACING motion (state %d)" % css.token_state(0))
    check(not hand.is_carrying(), "the hand returns to free after committing")
    await create_timer(0.3).timeout
    check(css.token_state(0) == PLACED, "the token settles PLACED after the placement motion")
    var token_node = css.token_view(0)
    var tile_node = tiles[tile_ggb]
    check(token_node.get_parent() == tile_node.token_layer(), "the placed token lives on the committed tile")
    var name_band: Rect2 = tile_node.name_band_rect()
    var token_rect := Rect2(token_node.position, token_node.size)
    check(not token_rect.intersects(name_band) or token_rect.get_area() == 0.0, "the token does not cover the name band")
    check(bays[0].presented_fighter() == "ggb", "the bay presents the committed fighter")

    # --- a committed chip is never lifted by browsing (Doc 01 §5 lift rule) -
    # Hovering another tile only moves the candidate: a committed chip stays
    # PLACED on its own tile (owner report: the hover used to put it back into
    # the hand, with no A pressed).
    arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
    css._on_tile_entered(css._tile_index_of("doge_man"))
    check(not hand.is_carrying() and css.get_carried_by() == -1,
        "browsing never lifts a committed player's token (carried_by %d)" % css.get_carried_by())
    check(css.token_state(0) == PLACED,
        "the committed token stays PLACED while browsing (state %d)" % css.token_state(0))
    check(css.token_view(0).get_parent() == tile_node.token_layer(),
        "the committed token stays owned by its own tile")
    css._leave_field()
    await create_timer(0.25).timeout
    check(not hand.is_carrying() and css.token_state(0) == PLACED, "leaving the roster keeps the chip on its tile")
    check(str(state.slots[0]["character"]) == "ggb", "cancelling never changed the committed fighter")
    check(css.get_carried_by() == -1, "no carry survives the cancel (carried_by %d)" % css.get_carried_by())
    check(css.token_view(0).get_parent() == tile_node.token_layer(), "the token is owned by the committed tile")
    # leave / re-enter repeatedly: the FSM never sticks
    for i in 3:
        arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
        css._on_tile_entered(tile_ggb)
        css._leave_field()
    await create_timer(0.25).timeout
    check(not hand.is_carrying() and css.token_state(0) == PLACED and css.get_carried_by() == -1,
        "the leave/re-enter loop never leaves a sticky token")

    # --- active-player switch resolves the previous player's carry ---------
    # A carry only ever exists for a player WITHOUT a committed pick, so the
    # journey takes the committed chip back with B first (the ONE sanctioned
    # take-back, stage 2 of the staged cancel) and then switches the station.
    css._on_bay_activated(0)
    await press_pad_b()
    check(str(state.slots[0]["character"]) == "", "precondition: B took P1's commit back")
    check(css.get_carried_by() == 0, "precondition: P1's token is carried (uncommitted)")
    css._on_bay_activated(1)
    check(css.get_carried_by() == -1, "switching the active player resolves the previous player's carry first")
    check(css.get_active() == 1, "bay activation changes the active player explicitly")
    await create_timer(0.3).timeout
    check(css.token_state(0) == UNASSIGNED, "the taken-back (uncommitted) token returns home")
    check(css.token_view(0).get_parent() == css.token_home_layer(), "…and is owned by the home layer")
    # committing for P2 (already a CPU) keeps that slot's own token intact
    css._on_tile_pressed("ggb")
    await create_timer(0.3).timeout
    check(str(state.slots[1]["character"]) == "ggb", "P2 committed the pick")
    check(css.token_state(1) == PLACED, "the CPU's committed chip is PLACED on its tile")
    check(css.token_view(1).get_parent() == tile_node.token_layer(), "…owned by that tile")
    # the chip P1 took back is still UNCOMMITTED: nothing re-commits it on its own
    check(str(state.slots[0]["character"]) == "" and not hand.is_carrying(),
        "taking a chip back never re-commits it on its own")
    # two players can commit the same fighter: the chips share the tile without
    # ever overlapping exactly (deterministic slot ordinals, Doc 04 §16).
    css._on_bay_activated(0)
    css._on_tile_pressed("ggb")
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and str(state.slots[1]["character"]) == "ggb",
        "two players can commit the same fighter")
    check(css.token_state(0) == PLACED and css.token_state(1) == PLACED, "both chips rest PLACED on the shared tile")
    var t0 = css.token_view(0)
    var t1 = css.token_view(1)
    var r0 := Rect2(t0.position, t0.size)
    var r1 := Rect2(t1.position, t1.size)
    check(not r0.intersects(r1), "placed tokens on one tile never overlap exactly")
    check(css.get_active() == 0, "committing does not advance the active player")

    # --- kind transitions never silently create a fighter ------------------
    # Setting a slot EMPTY cancels its interaction, clears the fighter and
    # leaves the token UNASSIGNED (Doc 04 §6, ledger C-039).
    css._on_bay_activated(1)
    await press_pad_b()              # stage 2: the CPU's committed chip back into the hand
    check(str(state.slots[1]["character"]) == "" and css.get_carried_by() == 1,
        "precondition: P2's committed chip is carried (carried_by %d)" % css.get_carried_by())
    css._on_kind_clicked(1)          # bot -> empty while its token is carried
    check(str(state.slots[1]["kind"]) == "empty", "kind control cycles to EMPTY")
    check(str(state.slots[1]["character"]) == "", "EMPTY clears the committed fighter")
    check(css.get_carried_by() == -1 and not hand.is_carrying(), "EMPTY cancels the carried token")
    await create_timer(0.3).timeout
    check(css.token_state(1) == UNASSIGNED, "an EMPTY player's token is UNASSIGNED")
    check(not css.token_view(1).visible, "…and not visible")
    check(css.token_view(1).get_parent() == css.token_home_layer(), "…and owned by the home layer")
    # a fighter commit on an EMPTY slot must NOT turn it into a Human (Doc 04 §6)
    css._on_tile_pressed("ggb")
    check(str(state.slots[1]["kind"]) == "empty" and str(state.slots[1]["character"]) == "",
        "fighter selection never silently changes EMPTY -> HUMAN")
    # cycling back to Human seeds a valid input assignment and no fighter
    css._on_kind_clicked(1)
    check(str(state.slots[1]["kind"]) == "human", "kind cycles back to HUMAN")
    check(str(state.slots[1]["character"]) == "", "returning to Human does not preselect a fighter")
    check(bays[1].input_readout() == "KEYBOARD 2", "P2 Human reads INPUT KEYBOARD 2")

    # --- keyboard parity: focus graph + activation ------------------------
    var kb_tiles: Array = css.get_tiles()
    kb_tiles[0].grab_focus()
    check(root.gui_get_focus_owner() == kb_tiles[0], "tiles can take keyboard focus")
    var tab := InputEventKey.new()
    tab.keycode = KEY_TAB
    tab.pressed = true
    root.push_input(tab)
    await process_frame
    check(root.gui_get_focus_owner() == kb_tiles[1], "Tab moves focus to the next tile")
    var kb_enter := InputEventKey.new()
    kb_enter.keycode = KEY_ENTER
    kb_enter.pressed = true
    root.push_input(kb_enter)
    await process_frame
    await create_timer(0.3).timeout
    check(str(state.slots[css.get_active()].character) == str(kb_tiles[1].fighter_id), "Enter commits the keyboard-focused tile")
    check(css.get_carried_by() == -1, "no carry after the keyboard commit (carried_by %d)" % css.get_carried_by())
    check(not hand.is_carrying(), "no carried token after the keyboard commit")

    # --- device ownership (Doc 01 §4) -------------------------------------
    check(css.ready_allowed(), "P1 Human + P2 Human with fighters can ready")
    state.slots[2]["kind"] = "human"          # P3 Human without a pad
    state.slots[2]["character"] = "ggb"
    css.refresh_devices()
    check(bays[2].input_readout() == "CONNECT CONTROLLER", "a pad-less P3 Human reads CONNECT CONTROLLER")
    check(not bays[2].input_readout_valid(), "…and its assignment is invalid")
    check(not css.ready_allowed(), "no invalid Human device state reaches Ready")
    var exits := [0]
    css.ready_requested.connect(func(): exits[0] += 1)
    css._on_ready_pressed()
    await process_frame
    check(exits[0] == 0, "READY is inert while the device state is invalid")
    css.set_connected_pads([0])
    check(bays[2].input_readout() == "PAD 1" and bays[2].input_readout_valid(), "a connected pad is claimed and reads PAD 1")
    check(css.ready_allowed(), "the slot becomes valid once a pad is connected (hotplug refresh)")
    css.set_connected_pads([])
    check(not css.ready_allowed(), "disconnecting the pad invalidates the slot again")
    # P1 cannot duplicate a pad another Human owns (no duplicate pad)
    var p1_choices: Array = css.device_choices(0)
    check(p1_choices.has(-1), "P1 always keeps Keyboard 1 available")
    state.slots[2]["kind"] = "empty"
    state.slots[2]["character"] = ""
    css.refresh_devices()
    check(css.ready_allowed(), "returning P3 to Empty restores a valid configuration")

    # --- ready gating through the ONE authority ---------------------------
    check(css.get_ready_band().is_shown(), "the ready band shows when the configuration is valid")
    check(css.ready_allowed(), "ready_allowed mirrors the validation authority")
    css._on_kind_clicked(1)              # HUMAN -> CPU
    check(str(state.slots[1]["kind"]) == "bot", "the kind control cycles HMN -> CPU")
    check(css.ready_allowed(), "a CPU slot still counts as an active fighter")
    css._on_kind_clicked(1)              # CPU -> EMPTY (1 active left)
    check(str(state.slots[1]["kind"]) == "empty", "the kind control cycles CPU -> EMPTY")
    check(not css.ready_allowed(), "one active player cannot ready")
    check(not css.get_ready_band().is_shown(), "no ready band while the configuration is invalid")
    css._on_kind_clicked(1)              # EMPTY -> HUMAN
    check(str(state.slots[1]["kind"]) == "human", "the kind control cycles EMPTY -> HUMAN")
    check(str(state.slots[1]["character"]) == "", "the emptied slot kept NO fighter (EMPTY never owns one)")
    check(not css.ready_allowed(), "a fresh Human still needs a fighter")
    css._on_tile_pressed("ggb")          # re-commit for the restored Human slot
    await create_timer(0.3).timeout
    check(str(state.slots[1]["character"]) == "ggb", "the restored Human slot commits its fighter")
    check(css.ready_allowed(), "config valid again (>= 2 active, >= 1 Human, valid devices)")
    check(css.get_ready_band().is_shown(), "ready band returns when valid")
    css._on_ready_pressed()
    await process_frame
    check(exits[0] == 1, "READY fires exactly once when valid (fired %d)" % exits[0])

    # --- production route: CSS -> SSS -> match (via the MatchFlow host) ----
    var opened: bool = await vs.wait_for(self, func() -> bool: return host.is_surface_presented("sss"), 240)
    check(opened, "ready exits the CSS and opens the stage page")
    var stage = host.stage_select()
    await create_timer(0.8).timeout
    stage.confirm()
    # The router constructs the destination synchronously from the confirm, so
    # the arena is captured right after it (before the released host frees).
    var arena: Node = host.gameplay_node()
    var launched := false
    for i in 300:
        await process_frame
        if arena != null and is_instance_valid(arena) and not arena.fighters.is_empty() and not is_instance_valid(host):
            launched = true
            break
    check(launched, "the stage confirm LAUNCHes gameplay and releases the frontend")
    if not (arena != null and is_instance_valid(arena)):
        quit(1)
        return
    if arena.fighters.is_empty():
        quit(1)
        return
    check(arena.fighters.size() == 2, "the match starts with the selected fighters")
    check(str(arena.fighters[0].character_id) == "ggb", "committed fighters reach the match")
    # --- state preservation: Results -> Change Fighters -> CSS (WP-0 step 5:
    # the frontend owns Results; this direct arena start hands the immutable
    # payload to the MatchFlow host) --------------------------------------
    for f in arena.fighters:
        f.set_physics_process(false)
    arena.fighters[1].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[1])
    var post = await vs.wait_for_post_match(self)
    check(post != null and post.post_match_result() != null,
        "the resolved match hands its payload to the MatchFlow PostMatch surface")
    if post != null:
        var change = post.post_match().result_screen.find_child("ChangeFighters", true, false)
        check(change != null and change.visible, "Results offers Change Fighters")
        if change != null:
            change.pressed.emit()
        var restored: bool = await vs.wait_for(self, func() -> bool: return post.active_surface() == "css", 180)
        check(restored, "Change Fighters returns to the CSS")
        check(str(post.selection_state.slots[0]["character"]) == "ggb", "fighters preserved through the results round trip")
        check(not hand.is_carrying(), "no token state survives the results round trip (carried_by %d, token %s)" % [post.char_select().get_carried_by(), str(hand.carried_token())])
        post.queue_free()
        await process_frame
    if is_instance_valid(arena):
        # The router-owned arena is torn down by the RETURN scene change; a
        # leftover handle is only freed if it survived (test hygiene).
        arena.queue_free()
    await process_frame

    # --- staged cancel (Doc 04): pad-B / ui_cancel peels ONE stage per press,
    # and the Back route follows the CSS's ENTRY ORIGIN, never a hardcoded Main.
    await staged_cancel_suite(vs, hand)
    # --- (A) a committed pick survives browsing the UI; (B) the hand's pose
    # follows the CSS state on entry / target change, not the next input event;
    # (C) a COMMITTED chip is never lifted by HOVER (the owner-reported bug).
    await browse_survival_suite(vs, hand)
    await committed_chip_hover_suite(vs, hand)
    await entry_pose_suite(vs, hand)
    # --- the OWNER-directed suites (findings 1-3), each on its own real path:
    # the pinch belongs to the chip's own tile, the roster anchor sits in the
    # tile's lower-right region with the name clear, and the pose is already
    # right in the first visible frame of the shipped Main PLAY route.
    await hover_pose_gate_suite(vs, hand)
    await roster_tile_anchor_suite(vs, hand)
    await real_route_entry_suite(vs, hand)
    # --- (4) the OWNER requirement: A / left-click on the committed tile
    # DE-SELECTS through the SAME implementation as the staged cancel's
    # take-back (one end state for A, the pointer and B).
    await deselect_committed_suite(vs, hand)

    # --- Back cancels a carried token (fresh host: the route itself is a scene
    # change owned by the flow, so only the local contract is asserted)
    var host3 = await vs.enter(self)
    var css3 = host3.char_select()
    await create_timer(0.6).timeout
    arm_mouse(hand, Vector2(640.0, 200.0))
    var idx3: int = css3._tile_index_of("mephisto")
    check(idx3 >= 0, "tail: mephisto is in the roster (idx %d)" % idx3)
    check(hand.is_mouse_active(), "tail: mouse modality armed (mode %d)" % hand.mode)
    check(css3.get_phase() == 1, "tail: css idle (phase %d)" % css3.get_phase())
    css3._on_tile_entered(idx3)
    check(hand.is_carrying(), "token carried before back (carried_by %d)" % css3.get_carried_by())
    css3._on_back_pressed()
    check(not hand.is_carrying(), "back cancels the carried token before the route")
    if is_instance_valid(host3):
        host3.queue_free()
    await process_frame
    if failures == 0: print("PASS: character select interaction (fresh defaults, device ownership, token FSM, ready gating, route, preservation)")
    quit(1 if failures else 0)

# --- staged cancel: one press = one stage; the BACK route follows the ORIGIN --
#
# The staged grammar (Doc 04 Character Select): an uncommitted CARRIED chip is
# cancelled first, then the ACTIVE player's COMMITTED pick is taken back into
# the hand, then the pending CANDIDATE is cleared — only a press that finds
# nothing pending follows the BACK route, and that route must resolve to the
# screen's ENTRY ORIGIN (Main for a fresh CSS, Results when the CSS was PUSHed
# from Results by CHANGE FIGHTERS).
#
# Every press below is a REAL device event delivered through the engine's own
# input dispatch (Input.parse_input_event) — never a direct call to the screen
# handler — and a counter proves one physical press reaches the screen exactly
# once (no double handling through the semantic signal and the ui_cancel action).

func press_pad_b() -> void:
    var down := InputEventJoypadButton.new()
    down.button_index = JOY_BUTTON_B
    down.pressed = true
    Input.parse_input_event(down)
    await process_frame
    await process_frame
    var up := InputEventJoypadButton.new()
    up.button_index = JOY_BUTTON_B
    up.pressed = false
    Input.parse_input_event(up)
    await process_frame
    await process_frame

func press_escape() -> void:
    var down := InputEventKey.new()
    down.keycode = KEY_ESCAPE
    down.pressed = true
    Input.parse_input_event(down)
    await process_frame
    await process_frame
    var up := InputEventKey.new()
    up.keycode = KEY_ESCAPE
    up.pressed = false
    Input.parse_input_event(up)
    await process_frame
    await process_frame

func connect_cancel_counter(sink: Array) -> void:
    # The semantic cancel signal, resolved through the autoload NODE (the global
    # identifier is not available inside a --script SceneTree run).
    var service = root.get_node_or_null("FrontendInput")
    if service != null:
        service.cancel_pressed.connect(func() -> void: sink[0] += 1)

func staged_cancel_suite(vs, hand) -> void:
    await staged_cancel_fresh(vs, hand)
    await staged_cancel_from_results(vs, hand)

func pad_nav(button: JoyButton) -> void:
    var down := InputEventJoypadButton.new()
    down.button_index = button
    down.pressed = true
    Input.parse_input_event(down)
    await process_frame
    await process_frame
    var up := InputEventJoypadButton.new()
    up.button_index = button
    up.pressed = false
    Input.parse_input_event(up)
    await process_frame
    await process_frame

func texture_path_of(tex: Texture2D) -> String:
    return "" if tex == null else str(tex.resource_path)

# --- (A) a COMMITTED pick survives browsing ---------------------------------
#
# The CSS destinations a player moves through: other roster tiles, the stations,
# the Ready band, the mode control (FFA / Teams) and the Back area. `browses`
# marks the roster tiles, where the bay is SUPPOSED to large-preview the
# candidate (Doc 04 §12) while the commit itself stays untouched.

func browse_destinations(css) -> Array:
    var out: Array = []
    var tiles: Array = css.get_tiles()
    for i in tiles.size():
        if i == 0:
            continue
        out.append({"name": "roster tile %d" % i, "control": tiles[i], "browses": true})
    var bays: Array = css.get_bays()
    for i in bays.size():
        if i == 0:
            continue
        out.append({"name": "station %d" % (i + 1), "control": bays[i], "browses": false})
    out.append({"name": "ready band", "control": css.get_ready_band(), "browses": false})
    var mode = css.get_mode_control()
    if mode != null and mode.segment_count() > 1:
        out.append({"name": "mode (teams)", "control": mode.segment(1), "browses": false})
    out.append({"name": "header Back", "control": css.get_node("ReferenceFrame/Header/BackAction"), "browses": false})
    return out

func browse_survival_suite(vs, hand) -> void:
    # (A) SELECTION MUST SURVIVE BROWSING. Moving the focus/pointer across the CSS
    # UI may only cancel an IN-FLIGHT carry: it must never take a committed chip
    # back (that is the exclusive job of an explicit ui_cancel, proven above).
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "browse survival: a CSS is mounted and idle")
        return
    var state = host.selection_state
    var bays: Array = css.get_bays()
    var tiles: Array = css.get_tiles()
    css._on_bay_activated(0)
    css._on_tile_pressed("ggb")
    css._on_bay_activated(1)
    css._on_tile_pressed("ggb")
    # Back to P1: the browsing journey below is the ACTIVE player's.
    css._on_bay_activated(0)
    await create_timer(0.4).timeout
    check(int(css.get_active()) == 0, "browse survival: P1 is the active player for the journey")
    check(str(state.slots[0]["character"]) == "ggb" and str(state.slots[1]["character"]) == "ggb",
        "browse survival: both stations committed a fighter")
    check(bays[0].presented_fighter() == "ggb", "browse survival: the active bay presents the committed fighter")
    check(css.ready_allowed() and css.get_ready_band().is_shown(), "browse survival: the configuration is valid (Ready band up)")
    check(css.token_state(0) == PLACED, "browse survival: the committed chip rests PLACED on its tile")

    # POINTER: hover another tile — only the CANDIDATE/preview moves (the
    # committed chip may not be lifted by a hover), then move across every other
    # destination. Leaving the populated roster field is driven the way the
    # runtime does it: the pointer really is outside the field, so the field's
    # own GUI mouse exit fires and the CSS consumes it as "leave the roster".
    var other: int = css._tile_index_of("mephisto")
    var ggb_tile: int = css._tile_index_of("ggb")
    arm_mouse(hand, tiles[other].get_global_rect().get_center())
    tiles[other].mouse_entered.emit()
    check(int(css.get_candidate()) == other, "browse survival: hovering another tile moves the candidate")
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "browse survival: hovering another tile lifts NOTHING into the hand (carried_by %d)" % css.get_carried_by())
    check(css.token_state(0) == PLACED and css.token_view(0).get_parent() == tiles[ggb_tile].token_layer(),
        "browse survival: the committed chip stays PLACED on its own tile while hovering")
    check(str(state.slots[0]["character"]) == "ggb", "browse survival: …without touching the commit")
    for spot in browse_destinations(css):
        arm_mouse(hand, (spot["control"] as Control).get_global_rect().get_center())
        if not bool(spot["browses"]):
            css.get_node("ReferenceFrame/RosterField").mouse_exited.emit()
        await create_timer(0.08).timeout
        check(str(state.slots[0]["character"]) == "ggb",
            "browse survival (pointer over the %s): the active player's commit survives" % str(spot["name"]))
        check(str(state.slots[1]["character"]) == "ggb",
            "browse survival (pointer over the %s): the other commit survives" % str(spot["name"]))
        if not bool(spot["browses"]):
            check(bays[0].presented_fighter() == "ggb",
                "browse survival (pointer over the %s): the active bay presents the COMMITTED fighter" % str(spot["name"]))
    await create_timer(0.4).timeout
    check(css.get_carried_by() == -1, "browse survival: no carry is left in flight when the pointer leaves the roster")
    check(css.token_state(0) == PLACED, "browse survival: the chip is still PLACED on its committed tile (state %d)" % css.token_state(0))
    check(css.token_view(0).get_parent() == tiles[ggb_tile].token_layer(),
        "browse survival: the chip is still owned by its committed tile after the pointer journey")
    check(bays[0].presented_fighter() == "ggb", "browse survival: the active bay is back on the committed fighter")

    # PAD/FOCUS: the same journey through the engine's own focus navigation.
    await pad_nav(JOY_BUTTON_DPAD_DOWN)
    for pass_index in 2:
        for spot in browse_destinations(css):
            (spot["control"] as Control).grab_focus()
            await create_timer(0.12).timeout
            check(str(state.slots[0]["character"]) == "ggb",
                "browse survival (focus on the %s, pass %d): the active player's commit survives" % [str(spot["name"]), pass_index + 1])
            check(str(state.slots[1]["character"]) == "ggb",
                "browse survival (focus on the %s, pass %d): the other commit survives" % [str(spot["name"]), pass_index + 1])
            if not bool(spot["browses"]):
                check(bays[0].presented_fighter() == "ggb",
                    "browse survival (focus on the %s, pass %d): the active bay presents the COMMITTED fighter" % [str(spot["name"]), pass_index + 1])
    check(css.ready_allowed(), "browse survival: the configuration is still valid after the focus journey")
    check(css.token_state(0) == PLACED, "browse survival: the committed chip is still placed (state %d)" % css.token_state(0))
    # …and the station is still usable: it can pick a DIFFERENT fighter afterwards.
    css._on_bay_activated(0)
    css._on_tile_pressed("mephisto")
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "mephisto", "browse survival: the station can still re-pick a different fighter afterwards")
    if is_instance_valid(host):
        host.queue_free()
    await process_frame

# --- (C) a COMMITTED chip is never lifted by HOVER ---------------------------
#
# OWNER REPORT (live pad + mouse, current build): after a station COMMITTED a
# fighter, merely HOVERING another fighter tile put the committed chip back into
# the hand — with no A pressed. The rule (single-sourced in char_select: the
# _has_committed_pick gate inside _begin_carry, the ONE place a chip can leave a
# tile for the hand): a committed chip leaves its tile ONLY through the owner's
# explicit actions —
#   (a) A / left-click on its own tile -> DE-SELECT (the take-back, the SAME
#       implementation as the staged cancel's stage 2; owner requirement, which
#       supersedes the former explicit no-op on this path);
#   (b) A / left-click on a DIFFERENT tile -> the commit MOVES (re-pick,
#       _on_tile_pressed);
#   (c) B / ui_cancel          -> the staged take-back (_take_back_committed,
#                                 which clears the commit BEFORE asking to lift).
# Hover, the candidate preview, focus browsing, the modality switch and the
# roster-envelope rule may only cancel an IN-FLIGHT carry of an UNCOMMITTED chip.
#
# WHY THIS SUITE EXISTS: the browse-survival cases assert the PERSISTENT commit
# survives browsing, but never that the CHIP is still on its tile — so a lift on
# hover passed them.
#
# Every case below drives the REAL MOUSE-HOVER path: a genuine
# InputEventMouseMotion into the engine's own dispatch (the viewport push, which
# reaches the cursor service's `_input` callback) plus the tile's own
# `mouse_entered` entry, the GUI entry a windowed run emits when the pointer
# crosses the tile — never the focus path. The focus/adopt path is covered at
# chip level by the browse-survival journey above (the committed chip is
# asserted PLACED across the whole focus traversal), because both paths ask the
# SAME gate for the lift.

func pointer_motion(hand, at: Vector2) -> void:
    # The engine's pointer-motion delivery: the viewport dispatch plus the
    # callback that dispatch reaches (the frontend input contract convention).
    # It also re-claims the MOUSE modality, exactly as a real mouse does.
    var event := InputEventMouseMotion.new()
    event.position = at
    event.relative = Vector2(28.0, 0.0)
    root.push_input(event, true)
    hand._input(event)
    # Two idle frames: SceneTree.process_frame is emitted BEFORE the nodes'
    # _process callbacks, so the cursor service refreshes its authoritative
    # hotspot on the frame after the one the first await returns on.
    await process_frame
    await process_frame

func hover_tile_mouse(hand, css, index: int) -> void:
    # Enter another fighter tile the way the runtime does it: move the pointer
    # over the tile (guarded: the hotspot must really be on it), then fire the
    # tile's own mouse entry. Never the focus path, never a private helper.
    var tile: Control = css.get_tiles()[index]
    var at: Vector2 = tile.get_global_rect().get_center()
    await pointer_motion(hand, at)
    check(tile.get_global_rect().has_point(hand.hotspot),
        "hover lift: the pointer hotspot really sits on tile %d (%s)" % [index, str(hand.hotspot)])
    tile.mouse_entered.emit()
    await create_timer(0.12).timeout

func pointer_click(hand, control: Control, at: Vector2) -> void:
    # A real left click on a custom Control: the engine delivers the button to
    # the control's own `_gui_input` (the screen's public mouse path).
    await pointer_motion(hand, at)
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
    await process_frame

func committed_chip_hover_suite(vs, hand) -> void:
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "hover lift: a CSS is mounted and idle")
        return
    var state = host.selection_state
    var tiles: Array = css.get_tiles()
    var bays: Array = css.get_bays()
    var ggb: int = css._tile_index_of("ggb")
    var other: int = css._tile_index_of("mephisto")
    var third: int = css._tile_index_of("turbofit")
    check(ggb >= 0 and other >= 0 and third >= 0 and other != ggb and third != ggb and third != other,
        "hover lift: three distinct roster tiles are available (%d/%d/%d)" % [ggb, other, third])
    await create_timer(0.5).timeout

    # --- the ACTIVE station commits through the real pointer path -----------
    await hover_tile_mouse(hand, css, ggb)
    await pointer_click(hand, tiles[ggb], tiles[ggb].get_global_rect().get_center())
    await create_timer(0.4).timeout
    check(hand.is_mouse_active(), "hover lift: the pointer modality is armed (mode %d, armed %s)"
        % [int(hand.mode), str(hand.is_pointer_hover_armed())])
    check(str(state.slots[0]["character"]) == "ggb", "hover lift: P1 committed ggb through the pointer")
    check(css.token_state(0) == PLACED, "hover lift: the committed chip rests PLACED (state %d)" % css.token_state(0))
    check(css.token_view(0).get_parent() == tiles[ggb].token_layer(), "hover lift: the chip is owned by the committed tile")
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(), "hover lift: nothing is in the hand after the commit")

    # --- HOVERING other fighter tiles must lift NOTHING ---------------------
    for index in [other, third]:
        await hover_tile_mouse(hand, css, index)
        check(int(css.get_candidate()) == index,
            "hover lift (tile %d): the hover still moves the CANDIDATE/preview" % index)
        check(str(state.slots[0]["character"]) == "ggb",
            "hover lift (tile %d): the committed pick is unchanged" % index)
        check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
            "hover lift (tile %d): hovering cannot lift the committed chip (carried_by %d)"
            % [index, int(css.get_carried_by())])
        check(css.token_state(0) == PLACED,
            "hover lift (tile %d): the chip is still PLACED (state %d)" % [index, css.token_state(0)])
        check(css.token_view(0).get_parent() == tiles[ggb].token_layer(),
            "hover lift (tile %d): the chip is still owned by its committed tile" % index)
        check(css.token_view(0).visible, "hover lift (tile %d): the chip is still drawn on its tile" % index)

    # --- hovering the chip's OWN tile is not a lift either ------------------
    await hover_tile_mouse(hand, css, ggb)
    check(int(css.get_candidate()) == ggb and str(state.slots[0]["character"]) == "ggb",
        "hover lift (own tile): the committed tile is the candidate and the pick is unchanged")
    check(int(css.get_carried_by()) == -1 and css.token_state(0) == PLACED,
        "hover lift (own tile): the chip stays on its tile (carried_by %d, state %d)"
        % [int(css.get_carried_by()), css.token_state(0)])
    check(bays[0].presented_fighter() == "ggb", "hover lift (own tile): the active bay still shows the committed fighter")

    # --- (a) A / left-click on the chip's OWN tile DE-SELECTS (owner
    # requirement): the pick is taken back into the hand through the SAME
    # implementation as the staged cancel's stage 2 — this supersedes the former
    # explicit no-op on this path. ---
    await pointer_click(hand, tiles[ggb], tiles[ggb].get_global_rect().get_center())
    await create_timer(0.3).timeout
    check(str(state.slots[0]["character"]) == "",
        "hover lift (A on its own tile): the commit is TAKEN BACK (no character selected)")
    check(int(css.get_carried_by()) == 0 and css.token_state(0) == CARRIED and hand.is_carrying(),
        "hover lift (A on its own tile): the chip is back IN THE HAND (carried_by %d, state %d)"
        % [int(css.get_carried_by()), css.token_state(0)])
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "hover lift (A on its own tile): the taken-back chip rides the carry layer")
    # …and the same tile re-commits the fighter through the same pointer path
    # (the chip is in the hand, so the press PLACES it): the journey below starts
    # from a committed chip again.
    await hover_tile_mouse(hand, css, ggb)
    await pointer_click(hand, tiles[ggb], tiles[ggb].get_global_rect().get_center())
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "hover lift (re-pick): the same tile commits the fighter again (state %d)" % css.token_state(0))

    # --- the pointer leaving the roster keeps the commit --------------------
    await pointer_motion(hand, Vector2(640.0, 30.0))
    css.get_node("ReferenceFrame/RosterField").mouse_exited.emit()
    await create_timer(0.25).timeout
    check(int(css.get_candidate()) == -1, "hover lift (off roster): leaving the roster clears only the candidate")
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "hover lift (off roster): the committed chip is untouched")
    check(int(css.get_carried_by()) == -1 and bays[0].presented_fighter() == "ggb",
        "hover lift (off roster): the bay returns to the COMMITTED fighter")

    # --- a CPU station's committed chip survives the active player's hover ---
    css._on_bay_activated(1)                      # P2 is the fresh-default CPU
    css._on_tile_pressed("doge_man")
    await create_timer(0.4).timeout
    check(str(state.slots[1]["character"]) == "doge_man", "hover lift (CPU): the CPU station committed doge_man")
    var cpu_tile: int = css._tile_index_of("doge_man")
    css._on_bay_activated(0)                      # back to the hovering (ACTIVE) player
    await create_timer(0.3).timeout
    check(int(css.get_active()) == 0, "hover lift (CPU): P1 is the active player again")
    for index in [other, cpu_tile, ggb]:
        await hover_tile_mouse(hand, css, index)
        check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
            "hover lift (CPU, over tile %d): hovering lifts nothing into the hand (carried_by %d)"
            % [index, int(css.get_carried_by())])
        check(str(state.slots[1]["character"]) == "doge_man" and css.token_state(1) == PLACED,
            "hover lift (CPU, over tile %d): the CPU's committed chip is untouched (state %d)"
            % [index, css.token_state(1)])
        check(css.token_view(1).get_parent() == tiles[cpu_tile].token_layer(),
            "hover lift (CPU, over tile %d): the CPU's chip is still on its own tile" % index)
        check(css.token_view(1).visible, "hover lift (CPU, over tile %d): the CPU's chip is still drawn" % index)
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "hover lift (CPU): the active player's own commit survived the journey too")

    # --- (b) A on ANOTHER tile still MOVES the committed chip --------------
    await hover_tile_mouse(hand, css, other)
    await pointer_click(hand, tiles[other], tiles[other].get_global_rect().get_center())
    await create_timer(0.5).timeout
    check(str(state.slots[0]["character"]) == "mephisto",
        "hover lift (A on another tile): the commit MOVES to the hovered fighter")
    check(css.token_state(0) == PLACED and css.token_view(0).get_parent() == tiles[other].token_layer(),
        "hover lift (A on another tile): the chip moved onto the new tile (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "hover lift (A on another tile): the move is a direct re-place, never through the hand")

    # --- (c) B still takes the committed chip back (the ONLY take-back) ----
    var cancels := [0]
    connect_cancel_counter(cancels)
    await press_pad_b()
    check(cancels[0] >= 1, "hover lift (B): a real pad-B press reaches the screen")
    check(str(state.slots[0]["character"]) == "", "hover lift (B): the staged take-back UNDOES the commit")
    check(int(css.get_carried_by()) == 0 and css.token_state(0) == CARRIED and hand.is_carrying(),
        "hover lift (B): the committed chip is back IN THE HAND (carried_by %d, state %d)"
        % [int(css.get_carried_by()), css.token_state(0)])
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "hover lift (B): the taken-back chip is owned by the carry layer")

    # --- ...and with that chip IN the hand, hovering must not disturb it ----
    await hover_tile_mouse(hand, css, cpu_tile)
    check(int(css.get_carried_by()) == 0 and css.token_state(0) == CARRIED and hand.is_carrying(),
        "hover lift (carry in flight): the UNCOMMITTED carry survives the hover (carried_by %d)"
        % int(css.get_carried_by()))
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "hover lift (carry in flight): the carried chip stays in the hand's own layer")
    check(str(state.slots[1]["character"]) == "doge_man" and css.token_state(1) == PLACED
        and css.token_view(1).get_parent() == tiles[cpu_tile].token_layer(),
        "hover lift (carry in flight): the CPU's committed chip is still on its own tile")
    check(int(css.get_candidate()) == cpu_tile,
        "hover lift (carry in flight): the hover only moved the candidate (%d)" % int(css.get_candidate()))

    # --- ...and the staged cancel still peels that carry (stage 1) ----------
    # The suite ends with NOTHING in flight: a chip left in the hand across a
    # screen teardown would be a cursor-owned leftover (Doc 04 §4).
    await press_pad_b()
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "hover lift (end): the uncommitted carry is cancelled back out of the hand (carried_by %d)"
        % int(css.get_carried_by()))
    check(str(state.slots[1]["character"]) == "doge_man" and css.token_state(1) == PLACED,
        "hover lift (end): the CPU's committed chip is still committed and PLACED")

    if is_instance_valid(host):
        host.queue_free()
    await process_frame

# --- (B) no stale hand pose on CSS entry ------------------------------------

const HOVER_SPRITE := "res://assets/ui/hand_hover.png"
const POINT_SPRITE := "res://assets/ui/hand_point.png"
const CARRY_SPRITE := "res://assets/ui/hand_hold.png"

func entry_pose_suite(vs, hand) -> void:
    # (B) NO STALE HAND POSE ON CSS ENTRY: the hand's pose must follow the state
    # at the moment the screen becomes visible / its target changes — never one
    # input event later. The FOCUS path is proven with NO input event delivered
    # to the CSS at all, and the entry state it must answer to is the OWNER's
    # entry chip: no committed pick -> the token rides the cursor -> the CARRY
    # grip with the chip in it (never the ordinary pointer, never the pinch).
    hand.claim_focus()
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "entry pose: a CSS is mounted and idle")
        return
    await create_timer(0.4).timeout
    var tiles: Array = css.get_tiles()
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "entry pose: the entry chip rides the cursor (carried_by %d)" % int(css.get_carried_by()))
    check(hand._focus_anchor == tiles[0].anchor(), "entry pose: the hand's focus target IS the first roster tile")
    check(css._cursor_in_roster(), "entry pose: the hand's hotspot sits in the roster envelope, on the first tile")
    check(int(hand.visual) == 1, "entry pose: the hand's pose is the CARRY grip on entry (visual %d, no input event delivered)" % int(hand.visual))
    check(texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "entry pose: the hand draws the carry grip sprite (got %s)" % texture_path_of(hand.active_texture()))
    check(hand.active_tip().is_equal_approx(hand.TIP_CARRY),
        "entry pose: the carry grip keeps its measured anchor %s" % str(hand.TIP_CARRY))
    check(texture_path_of(hand.active_texture()) != POINT_SPRITE, "entry pose: the ordinary pointer pose is NOT what the hand draws")
    check(texture_path_of(hand.active_texture()) != HOVER_SPRITE, "entry pose: the empty pinch is NOT what the entry draws either")

    # The pose follows a TARGET change too: focus the Back area (off the roster),
    # with no further input — and the CARRY grip STAYS, because the chip is in
    # the hand: the pose answers the chip's state, never the focus geometry.
    var back: Control = css.get_node("ReferenceFrame/Header/BackAction")
    back.grab_focus()
    await create_timer(0.6).timeout
    check(int(css.get_carried_by()) == 0 and int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "entry pose: focus off the roster keeps the CARRY grip while the chip is in the hand (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])

    # The pointer path: a pointer coming to REST on a roster tile finds the
    # entry chip already in the hand — the CARRY grip, no hover/enter event and
    # no further input needed.
    arm_mouse(hand, tiles[0].get_global_rect().get_center())
    await create_timer(0.25).timeout
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "entry pose: a resting pointer finds the entry chip in the hand (carried_by %d, Doc 03 §3 hover arming)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "entry pose: a resting pointer on a roster tile draws the CARRY grip, with no further input (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    # …and the APPROVED CARRY grip is the very same grip once the carry is live.
    tiles[0].mouse_entered.emit()
    await create_timer(0.1).timeout
    check(hand.is_carrying() and int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "entry pose: the real carry still draws the approved grip (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    check(css.get_carried_by() == 0 and css.token_state(0) == CARRIED, "entry pose: …and the chip is in the hand")
    # The entry chip leaves the hand through the roster envelope once the
    # player's own roster interaction has taken over (the pre-existing rule —
    # here the pointer really is off the populated roster).
    css._leave_field()
    await create_timer(0.4).timeout
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "entry pose: after the roster interaction the field exit frees the hand (carried_by %d)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 2 or int(hand.visual) == 0, "entry pose: the pose settles after the leave (visual %d)" % int(hand.visual))
    if is_instance_valid(host):
        host.queue_free()
    await process_frame

func staged_cancel_fresh(vs, hand) -> void:
    # Stages 1/3/4 on a FRESH CSS (origin MAIN, nothing committed anywhere).
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "staged cancel: a fresh CSS is mounted and idle")
        return
    var cancels := [0]
    var backs := [0]
    connect_cancel_counter(cancels)
    css.back_requested.connect(func() -> void: backs[0] += 1)
    var origin: String = host.route_origin()
    check(origin == "main", "staged cancel: a fresh CSS reports the MAIN entry origin (got '%s')" % origin)
    check(str(host.selection_state.slots[0]["character"]) == "", "staged cancel: the fresh CSS has no committed pick")

    # STAGE 1 — a carried (uncommitted) chip returns home; the screen stays.
    var idx: int = css._tile_index_of("mephisto")
    check(idx >= 0, "stage 1: precondition — mephisto is in the roster")
    arm_mouse(hand, css.get_tiles()[idx].get_global_rect().get_center())
    css._on_tile_entered(idx)
    check(css.get_carried_by() == 0 and hand.is_carrying(), "stage 1: precondition — P1's chip is carried")
    var before: int = cancels[0]
    await press_escape()
    check(cancels[0] == before + 1, "stage 1: ONE ui_cancel press reaches the screen exactly once (no double handling)")
    check(backs[0] == 0, "stage 1: a consumed stage never requests the BACK route")
    check(css.get_carried_by() == -1 and not hand.is_carrying(), "stage 1: the carried chip leaves the hand")
    await create_timer(0.3).timeout
    check(css.token_state(0) == UNASSIGNED, "stage 1: the uncommitted chip returns home (state %d)" % css.token_state(0))
    check(css.token_view(0).get_parent() == css.token_home_layer(), "stage 1: …and is owned by the home layer")
    check(host.is_surface_presented("css") and css.is_visible_in_tree(), "stage 1: the screen is STILL the Character Select")
    check(str(host.selection_state.slots[0]["character"]) == "", "stage 1: cancelling a carry never commits a fighter")

    # STAGE 3 — the pending candidate clears; the screen still stays.
    check(css.get_candidate() >= 0, "stage 3: precondition — a candidate is still pending (%d)" % css.get_candidate())
    await press_escape()
    check(css.get_candidate() == -1, "stage 3: the pending candidate/preview is cleared")
    check(backs[0] == 0, "stage 3: clearing the candidate never requests the BACK route")
    check(host.is_surface_presented("css") and css.is_visible_in_tree(), "stage 3: the screen is STILL the Character Select")

    # STAGE 4 — nothing carried/committed/pending -> the BACK route, to ORIGIN.
    await press_escape()
    check(backs[0] == 1, "stage 4: the BACK route is requested exactly once")
    var home = await vs.wait_for_scene(self, "home.tscn")
    check(home != null, "stage 4: a fresh CSS (origin MAIN) back route leaves to Main")
    if css != null and is_instance_valid(css):
        check(str(host.selection_state.slots[0]["character"]) == "", "stage 4: the route never invented a commit")
    if is_instance_valid(host):
        host.queue_free()
    if home != null:
        home.queue_free()
    await process_frame

func staged_cancel_from_results(vs, hand) -> void:
    # Stage 2 + the origin-correct BACK route: a CSS PUSHed from Results
    # (CHANGE FIGHTERS) records the RESULTS origin, so its back route must
    # restore the Results host mounted beneath it — never Main.
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "sky")
    check(arena != null, "staged cancel/results: a match launches on the production route")
    if arena == null:
        return
    await vs.resolve(self, arena, [1])
    var post = await vs.wait_for_flow(self, host_id)
    check(post != null, "staged cancel/results: the completed match RETURNs to the frontend")
    if post == null:
        return
    var change = post.post_match().result_screen.find_child("ChangeFighters", true, false)
    check(change != null, "staged cancel/results: Results offers CHANGE FIGHTERS")
    if change == null:
        return
    change.pressed.emit()
    var pushed: bool = await vs.wait_for(self, func() -> bool: return post.is_surface_presented("css"), 240)
    check(pushed, "staged cancel/results: CHANGE FIGHTERS PUSHes the Character Select")
    if not pushed:
        return
    var css = post.char_select()
    var idle: bool = await vs.wait_for(self, func() -> bool: return css.get_phase() == 1 and css._guard <= 0.0, 240)
    check(idle, "staged cancel/results: the pushed CSS leaves its entry guard")
    var origin: String = post.route_origin()
    check(origin == "results", "the CSS entered from Results records the RESULTS origin (got '%s')" % origin)
    check(str(post.selection_state.slots[0]["character"]) == "ggb", "the pushed CSS keeps the committed fighter")
    # Normalise the transient roster interaction through the screen's own
    # cancellation transition so the staged sequence starts from a known state.
    css._leave_field()
    await create_timer(0.1).timeout
    check(css.get_carried_by() == -1 and css.get_candidate() == -1,
        "the staged sequence starts with nothing carried or pending (carry %d, candidate %d)" % [css.get_carried_by(), css.get_candidate()])
    # The pointer stays inside the populated roster envelope for the whole
    # sequence: a carried chip must survive the mouse envelope rule.
    var ggb_index: int = css._tile_index_of("ggb")
    check(ggb_index >= 0, "the committed fighter owns a roster tile (idx %d)" % ggb_index)
    arm_mouse(hand, css.get_tiles()[ggb_index].get_global_rect().get_center())
    check(hand.mode == 0, "the pointer modality owns the hand for the staged sequence")

    var cancels := [0]
    var backs := [0]
    connect_cancel_counter(cancels)
    css.back_requested.connect(func() -> void: backs[0] += 1)

    # STAGE 2 — a real pad B takes the committed chip back into the hand.
    var before: int = cancels[0]
    await press_pad_b()
    check(cancels[0] == before + 1, "stage 2: ONE pad-B press reaches the screen exactly once (no double handling)")
    check(backs[0] == 0, "stage 2: a consumed stage never requests the BACK route")
    check(str(post.selection_state.slots[0]["character"]) == "", "stage 2: the commit is UNDONE (chip taken back)")
    check(css.get_carried_by() == 0, "stage 2: the chip is back in the hand (carried_by %d)" % css.get_carried_by())
    check(css.token_state(0) == CARRIED, "stage 2: the token FSM reads CARRIED (state %d)" % css.token_state(0))
    check(hand.is_carrying() and hand.visual == 1, "stage 2: the carry presentation is active")
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer", "stage 2: the taken-back chip is owned by the carry layer")
    check(post.is_surface_presented("css") and post.active_surface() == "css", "stage 2: the screen NEVER left the Character Select")
    check(css.get_candidate() >= 0, "stage 2: the taken-back fighter stays the candidate (%d)" % css.get_candidate())
    # The commit is gone for the ACTIVE player only: the other station keeps its
    # pick (only the active player's staged cancel is peeled).
    check(str(post.selection_state.slots[1]["character"]) == "ggb", "stage 2: the other station keeps its committed pick")

    # STAGE 1 — the taken-back chip is cancelled back home.
    await press_pad_b()
    check(backs[0] == 0, "stage 1 (results origin): the carry cancel never requests the BACK route")
    check(css.get_carried_by() == -1 and not hand.is_carrying(), "stage 1 (results origin): the carried chip is cancelled")
    check(post.is_surface_presented("css"), "stage 1 (results origin): the screen is STILL the Character Select")

    # STAGE 3 — the pending candidate clears (asserted immediately: the deferred
    # semantic-focus settle may clear a candidate on its own later).
    check(css.get_candidate() >= 0, "stage 3 (results origin): precondition — the taken-back fighter is the candidate (%d)" % css.get_candidate())
    await press_pad_b()
    check(css.get_candidate() == -1, "stage 3 (results origin): the pending candidate is cleared")
    check(post.is_surface_presented("css") and post.active_surface() == "css", "stage 3 (results origin): still the Character Select")
    await create_timer(0.3).timeout
    check(css.token_state(0) == UNASSIGNED, "stage 1 settle (results origin): the uncommitted chip went home (state %d)" % css.token_state(0))
    check(str(post.selection_state.slots[0]["character"]) == "", "the active player's pick stays taken back (nothing re-commits on its own)")

    # STAGE 4 — nothing pending: the BACK route resolves the RECORDED origin.
    check(backs[0] == 0, "no earlier stage requested the route (backs %d)" % backs[0])
    var scene_before = self.current_scene
    await press_pad_b()
    check(backs[0] == 1, "stage 4: the BACK route is requested exactly once")
    var back_to_results: bool = await vs.wait_for(self, func() -> bool: return post.is_surface_presented("postmatch"), 240)
    check(back_to_results, "stage 4: the CSS Back route from the RESULTS origin RESTORES Results")
    check(post.active_surface() == "postmatch", "stage 4: Results is the active surface again (not Main)")
    check(self.current_scene == scene_before, "stage 4: the route did NOT switch scene to Main")
    post.queue_free()
    await process_frame

# --- (3) THE POSE RULE: the pinch belongs to the chip's OWN tile -------------
#
# OWNER REPORT (live pad + mouse, current build): while a chip was COMMITTED,
# hovering a DIFFERENT fighter also drew the empty pinch, so the hand read as
# "about to pick something up" over every tile. The rule — single-sourced in
# char_select._cursor_pose_visual(), the ONE place that writes the hand's visual
# mode (CARRY while a chip is in the hand; HOVER only on the hold the hand
# ADDRESSES: the tile that HOLDS the active player's committed chip, or any
# browsed hold while that player has no committed pick; the ordinary pointer
# everywhere else) — is asserted here. Every hover below is a REAL pointer
# motion through the engine's dispatch (the hover-survival helper convention)
# plus the tile's own `mouse_entered` entry, never a private call.

func hover_pose_gate_suite(vs, hand) -> void:
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "pose gate: a CSS is mounted and idle")
        return
    var state = host.selection_state
    var tiles: Array = css.get_tiles()
    var ggb: int = css._tile_index_of("ggb")
    var other: int = css._tile_index_of("mephisto")
    var third: int = css._tile_index_of("turbofit")
    check(ggb >= 0 and other >= 0 and third >= 0 and other != ggb and third != ggb and third != other,
        "pose gate: three distinct roster tiles are available (%d/%d/%d)" % [ggb, other, third])
    await create_timer(0.4).timeout

    # --- the ACTIVE station commits through the real pointer path -----------
    await hover_tile_mouse(hand, css, ggb)
    await pointer_click(hand, tiles[ggb], tiles[ggb].get_global_rect().get_center())
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "pose gate: P1's chip is COMMITTED and PLACED (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "pose gate: nothing is in the hand after the commit (carried_by %d)" % int(css.get_carried_by()))

    # --- the chip's OWN tile: the empty pinch -------------------------------
    await hover_tile_mouse(hand, css, ggb)
    check(int(hand.visual) == 2 and texture_path_of(hand.active_texture()) == HOVER_SPRITE,
        "pose gate: hovering the tile that HOLDS the player's chip draws the empty pinch (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])

    # --- every OTHER tile: the ordinary pointer -----------------------------
    for index in [other, third]:
        await hover_tile_mouse(hand, css, index)
        check(int(hand.visual) == 0 and texture_path_of(hand.active_texture()) == POINT_SPRITE,
            "pose gate: hovering a fighter WITHOUT the player's chip draws the ordinary pointer (tile %d, visual %d, %s)"
            % [index, int(hand.visual), texture_path_of(hand.active_texture())])
        check(int(css.get_candidate()) == index,
            "pose gate (tile %d): the hover still browses (candidate %d)" % [index, int(css.get_candidate())])
        check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
            "pose gate (tile %d): the committed pick is untouched by the hover" % index)

    # --- with the chip IN the hand the grip is drawn over ANY tile ----------
    await press_pad_b()
    check(int(css.get_carried_by()) == 0 and hand.is_carrying() and css.token_state(0) == CARRIED,
        "pose gate: pad-B takes the committed chip into the hand (carried_by %d)" % int(css.get_carried_by()))
    await hover_tile_mouse(hand, css, third)
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "pose gate: carrying keeps the approved grip whatever the pointer is over (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "pose gate: the carried chip rides the cursor carry layer")

    # --- and the pinch returns once nothing is committed --------------------
    await press_pad_b()
    await create_timer(0.2).timeout
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "pose gate: the carry cancels (carried_by %d)" % int(css.get_carried_by()))
    check(str(state.slots[0]["character"]) == "", "pose gate: the take-back left the pick uncommitted")
    check(int(hand.visual) == 2 and texture_path_of(hand.active_texture()) == HOVER_SPRITE,
        "pose gate: nothing is committed and the hand rests on a hold, so the pinch returns (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    if is_instance_valid(host):
        host.queue_free()
    await process_frame

# --- (2) the roster tile's focus-hand anchor (owner direction) ---------------
#
# The owner's direction supersedes the old centre-top calibration: the hand
# belongs LOWER-RIGHT on the addressed tile — the fingertip in the tile's
# lower-right region — and the drawn body must never cover the fighter's name
# (the Main rail rows' own clearance discipline). The name is measured as its
# FONT-MEASURED extent (the shaped text), which is also what the optical
# manifest's label rect now is, so the meter and the assertion read one box.

func name_glyph_box(tile: Control) -> Rect2:
    # The fighter name's shaped box, measured from the font (independent of the
    # widget's own rect), centred in the tile's name band the way the label
    # draws it.
    var label: Label = tile.get_node("NameBand/FighterName")
    var font := label.get_theme_font("font")
    var fs: int = label.get_theme_font_size("font_size")
    var shaped := font.get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
    var glyph_h := font.get_height(fs)
    var band: Rect2 = tile.name_band_rect()
    return Rect2(tile.get_global_rect().position + Vector2(
        (band.size.x - shaped.x) * 0.5, band.position.y + (band.size.y - glyph_h) * 0.5),
        Vector2(shaped.x, glyph_h))

func roster_tile_anchor_suite(vs, hand) -> void:
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "roster anchor: a CSS is mounted and idle")
        return
    var tiles: Array = css.get_tiles()
    check(tiles.size() == 7, "roster anchor: seven roster tiles (%d)" % tiles.size())
    await create_timer(0.4).timeout
    # A committed pick keeps focus browsing from lifting a chip, so the hand can
    # be authored onto every tile's own anchor without a carry in flight.
    css._on_tile_pressed("ggb")
    await create_timer(0.4).timeout
    hand.claim_focus()
    var anchored := 0
    for i in tiles.size():
        var tile: Control = tiles[i]
        tile.grab_focus()
        await Support.settle_hand(self)
        var rect: Rect2 = tile.get_global_rect()
        var tip: Vector2 = tile.anchor().get_global_rect().position
        var rel: Vector2 = tip - rect.position
        check(rect.has_point(tip),
            "roster anchor (%s): the fingertip is ON the tile (%s)" % [str(tile.fighter_id), str(tip)])
        check(rel.x >= rect.size.x * 0.75 and rel.y >= rect.size.y * 0.75,
            "roster anchor (%s): the fingertip sits in the tile's LOWER-RIGHT region (rel %.2f / %.2f of %s)"
            % [str(tile.fighter_id), rel.x / rect.size.x, rel.y / rect.size.y, str(rect.size)])
        check(hand.hotspot.distance_to(tip) <= Support.REACH_TOLERANCE_PX + 1.0,
            "roster anchor (%s): the hand settles on the authored anchor (%.3f px)"
            % [str(tile.fighter_id), hand.hotspot.distance_to(tip)])
        var glyph := name_glyph_box(tile)
        var authored := Support.hand_body_rect(hand, "authored")
        check(Support.intersect_area(authored, glyph) == 0.0,
            "roster anchor (%s): the drawn hand body never crosses the name's font-measured extent %s (overlap %.2f px^2)"
            % [str(tile.fighter_id), str(glyph), Support.intersect_area(authored, glyph)])
        var observed := Support.hand_body_rect(hand, "observed")
        check(Support.intersect_area(observed, glyph) == 0.0,
            "roster anchor (%s): the pose actually drawn at the anchor clears the name too (overlap %.2f px^2)"
            % [str(tile.fighter_id), Support.intersect_area(observed, glyph)])
        var label_rect: Rect2 = (tile.get_node("NameBand/FighterName") as Label).get_global_rect()
        check(absf(label_rect.size.x - glyph.size.x) < 0.51,
            "roster anchor (%s): the measurable label rect IS the shaped name (%s vs %.1f px)"
            % [str(tile.fighter_id), str(label_rect.size), glyph.size.x])
        var optical := Support.measure_placement(hand, tile)
        check(bool(optical["placement_pass"]),
            "roster anchor (%s): the manifest's own optical verdict stays green (%s, %.2f px from the surface)"
            % [str(tile.fighter_id), str(optical["placement"]), optical["distance_to_action_surface_px"]])
        check(not bool(optical["label_obscured"]),
            "roster anchor (%s): the manifest's label_obscured stays 0 (%.2f px^2)"
            % [str(tile.fighter_id), optical["label_obscured_px2"]])
        anchored += 1
    check(anchored == tiles.size(), "roster anchor: every roster tile was measured at its own anchor (%d)" % anchored)
    if is_instance_valid(host):
        host.queue_free()
    await process_frame

    # --- the DRAWN entry chip at the entry anchor (nothing committed) ------
    # The owner's entry state IS the chip in the hand, so what the anchor draws
    # at entry is the CARRY GRIP — not the empty pinch anymore. Its drawn body is
    # wider than the point pose's, so the pose-dependent overlap with the first
    # tile's name is MEASURED and recorded here (the authored point pose's own
    # overlap stays 0.00 px^2 and is enforced by the focus manifest's own split);
    # the by-eye verdict comes from the fixed-60 Hz entry captures.
    hand.claim_focus()
    var fresh_host = await vs.enter(self)
    var fresh = fresh_host.char_select()
    if fresh == null or not await vs.wait_css_ready(fresh_host, self):
        check(false, "roster anchor: a fresh CSS is mounted and idle")
        return
    await create_timer(0.4).timeout
    check(int(fresh.get_carried_by()) == 0 and hand.is_carrying(),
        "roster anchor: the entry chip rides the cursor (carried_by %d)" % int(fresh.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "roster anchor: the entry draws the CARRY grip at the anchor (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    await Support.settle_hand(self)
    var first: Control = fresh.get_tiles()[0]
    var entry_body := Support.hand_body_rect(hand, "observed")
    var entry_glyph := name_glyph_box(first)
    var entry_overlap := Support.intersect_area(entry_body, entry_glyph)
    check(entry_overlap <= 45.0,
        "roster anchor: the entry CARRY grip's drawn body over the first tile's name stays the recorded pose-dependent overlap (%.2f px^2, 39.50 px^2 measured — the authored point pose stays 0.00)"
        % entry_overlap)
    if is_instance_valid(fresh_host):
        fresh_host.queue_free()
    await process_frame

# --- (1) THE ENTRY CHIP ON THE REAL PLAY ROUTE --------------------------------
#
# OWNER FINDING (live mouse + pad, current build): opening the Character Select
# from Main PLAY with NO committed pick drew the ORDINARY POINTER — the owner's
# screenshot shows the pointing hand with NO CHIP in it right after Play — and
# on the pad it drew the empty pinch. The owner's model is the screen's own
# state: with no character selected the chip RIDES THE CURSOR, so the CARRY grip
# with the chip in it is what the FIRST VISIBLE FRAME must draw, on BOTH entry
# devices.
#
# The old entry-pose suite passed straight through the live bug: it asserted the
# ENTRY CONDITION THE CODE PRODUCED (nothing carried: carried_by == -1, the pad
# drawing the empty pinch, the mouse the ordinary pointer off the roster) rather
# than the owner's state, so its assertions could never fail while the owner
# looked at exactly the same wrong pose on screen.
#
# Both passes below press the shipped Main PLAY row through the REAL route (the
# runtime's scene change mounts the MatchFlow host) and assert in that first
# visible frame, while the CSS entry guard is still running and NO input event
# has been delivered to the Character Select. The mouse pass also proves the
# chip SURVIVES the frames that follow with the pointer resting off the roster
# (the owner's case: the pointer stays where PLAY was clicked) and then walks
# the whole owner journey — a real motion onto a hold, a real left click that
# PLACES the chip (the pose then answers the existing rule), and a real pad-B
# take-back that puts the chip back in the hand (the CARRY grip again).

func mount_main() -> Control:
    # The shipped Main Menu as the current scene, exactly like the runtime: the
    # PLAY route replaces it with the MatchFlow host.
    var home = (load("res://scenes/home.tscn") as PackedScene).instantiate()
    root.add_child(home)
    if current_scene == null:
        current_scene = home
    await frames(14)
    return home

func await_css_entry(previous: Array) -> Array:
    # The FIRST frame a NEW MatchFlow host shows its Character Select — the frame
    # the runtime's PLAY route lands. No input is delivered after the press.
    for i in 600:
        await process_frame
        for child in root.get_children():
            if not child.has_method("char_select"):
                continue
            if child.get_instance_id() in previous:
                continue
            var css = child.char_select()
            if css != null and css.is_visible_in_tree():
                return [child, css]
    return [null, null]

func cleanup_real_route(host, home) -> void:
    # Test hygiene: the route's own scene change made the flow the current
    # scene, so the pointer is cleared first (never a dangling current_scene)
    # before this suite hands the tree back.
    if home != null and is_instance_valid(home):
        home.queue_free()
    if host != null and is_instance_valid(host):
        host.hide()
        if current_scene == host:
            current_scene = null
        host.queue_free()
    await process_frame
    await process_frame

func real_route_entry_suite(vs, hand) -> void:
    await real_route_entry_pad(vs, hand)
    await real_route_entry_mouse(vs, hand)

func real_route_entry_pad(vs, hand) -> void:
    var previous: Array = vs.host_ids(self)
    var home = await mount_main()
    var play: Button = home.menu_rows()[0].get_node("HitArea")
    play.grab_focus()
    await frames(3)
    await pad_nav(JOY_BUTTON_A)          # a REAL pad accept on the shipped PLAY row
    check(hand.mode == 1, "real route (pad): the pad accept claims FOCUS for the route (mode %d)" % int(hand.mode))
    var entry := await await_css_entry(previous)
    var host = entry[0]
    var css = entry[1]
    check(css != null, "real route (pad): the shipped PLAY row opens the Character Select through MatchFlow")
    if css == null:
        await cleanup_real_route(host, home)
        return
    # THE ASSERTION WINDOW: visible, still entering, nothing delivered to it.
    check(int(css.get_phase()) == 0 and css.get_input_guard() > 0.0,
        "real route (pad): the pose is asserted DURING the entry choreography (phase %d, guard %.2f)"
        % [int(css.get_phase()), css.get_input_guard()])
    check(hand.mode == 1, "real route (pad): the hand is in FOCUS modality (mode %d)" % int(hand.mode))
    var tiles: Array = css.get_tiles()
    check(hand._focus_anchor == tiles[0].anchor(),
        "real route (pad): the hand is authored onto the FIRST roster tile")
    # THE ENTRY CHIP, pad-A: no committed pick -> the chip rides the cursor.
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "real route (pad): the entry chip rides the cursor in the first visible frame (carried_by %d)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "real route (pad): the first visible frame draws the CARRY grip with the chip in it, no input event delivered (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    check(texture_path_of(hand.active_texture()) != POINT_SPRITE,
        "real route (pad): the ordinary pointer pose is NOT what the entry draws")
    check(texture_path_of(hand.active_texture()) != HOVER_SPRITE,
        "real route (pad): the empty pinch is NOT what the entry draws either")
    check(css.token_view(0).visible and str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "real route (pad): the carried chip is DRAWN in the cursor carry layer")
    check(hand.carried_token() == css.token_view(0),
        "real route (pad): the hand carries the player's SEPARATE token object")
    var chip_centre: Vector2 = css.token_view(0).global_position + css.token_view(0).size * 0.5
    check(chip_centre.distance_to(hand.carry_pinch_point()) <= 1.0,
        "real route (pad): the chip's centre lands on the carry anchor (%.2f px off)"
        % chip_centre.distance_to(hand.carry_pinch_point()))
    var tip: Vector2 = tiles[0].anchor().get_global_rect().position
    check(hand.hotspot.distance_to(tip) > 1.0,
        "real route (pad): the carry is already drawn while the fingertip is still %.1f px from the tile — the pose never waited for the sprite"
        % hand.hotspot.distance_to(tip))
    # …and the first CONTROLLER input then does what it always did: browse. The
    # entry chip is already in the hand, so the browse never drops it.
    var idle: bool = await vs.wait_css_ready(host, self)
    check(idle, "real route (pad): the CSS leaves its entry guard")
    await pad_nav(JOY_BUTTON_DPAD_RIGHT)
    await create_timer(0.2).timeout
    var moved = Support.focus_owner(self)
    check(moved == tiles[1],
        "real route (pad): a real D-pad press walks the roster (%s)" % str(moved.get_path() if moved != null else "-"))
    check(int(css.get_carried_by()) == 0 and hand.is_carrying() and int(hand.visual) == 1,
        "real route (pad): the browse keeps the entry chip in the hand and the CARRY grip drawn (carried_by %d, visual %d)"
        % [int(css.get_carried_by()), int(hand.visual)])
    # (c) PLACING the chip: the same real pad-A commits it and the pose answers
    # the EXISTING rule — the empty pinch on the hold that HOLDS the committed
    # chip (the focused tile).
    await pad_nav(JOY_BUTTON_A)
    await create_timer(0.5).timeout
    check(str(host.selection_state.slots[0]["character"]) == str(tiles[1].fighter_id),
        "real route (pad): a real pad-A places the chip on the focused tile (%s)"
        % str(host.selection_state.slots[0]["character"]))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "real route (pad): the placed chip left the hand (carried_by %d)" % int(css.get_carried_by()))
    check(int(hand.visual) == 2 and texture_path_of(hand.active_texture()) == HOVER_SPRITE,
        "real route (pad): on the chip's OWN tile the pose is the empty pinch (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    # (d) TAKING IT BACK: a real pad-B takes the committed chip into the hand and
    # the CARRY grip is drawn again.
    await press_pad_b()
    await create_timer(0.2).timeout
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "real route (pad): B takes the committed chip back into the hand (carried_by %d)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "real route (pad): the taken-back chip draws the CARRY grip again (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    # The pass ends with NOTHING in flight: a chip left in the hand across a
    # screen teardown would be a cursor-owned leftover (Doc 04 §4).
    await pad_nav(JOY_BUTTON_B)
    await create_timer(0.2).timeout
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "real route (pad): the take-back carry is cancelled back out of the hand before the teardown")
    await cleanup_real_route(host, home)

func real_route_entry_mouse(vs, hand) -> void:
    var previous: Array = vs.host_ids(self)
    var home = await mount_main()
    var play: Button = home.menu_rows()[0].get_node("HitArea")
    var at: Vector2 = play.get_global_rect().get_center()
    # A real pointer moving onto the row (engages hover, records the physical
    # spot) and a real left click on it — the pointer path into PLAY.
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.relative = Vector2(26.0, 0.0)
    root.push_input(motion, true)
    hand._input(motion)
    await frames(2)
    root.push_input(Support.mouse_button_event(at, true), true)
    root.push_input(Support.mouse_button_event(at, false), true)
    await frames(2)
    check(hand.mode == 0, "real route (mouse): the pointer owns the hand (mode %d)" % int(hand.mode))
    var entry := await await_css_entry(previous)
    var host = entry[0]
    var css = entry[1]
    check(css != null, "real route (mouse): the shipped PLAY row opens the Character Select")
    if css == null:
        await cleanup_real_route(host, home)
        return
    check(int(css.get_phase()) == 0 and css.get_input_guard() > 0.0,
        "real route (mouse): the pose is asserted DURING the entry choreography (phase %d, guard %.2f)"
        % [int(css.get_phase()), css.get_input_guard()])
    check(hand.mode == 0, "real route (mouse): the pointer still owns the hand (mode %d)" % int(hand.mode))
    # THE OWNER'S CASE: the pointer stays where PLAY was clicked — OFF the
    # populated roster — and the entry chip is in the hand all the same.
    check(not css._cursor_in_roster(), "real route (mouse): the pointer rests OFF the populated roster")
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "real route (mouse): the entry chip rides the cursor with the pointer off the roster (carried_by %d)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "real route (mouse): the first visible frame draws the CARRY grip, not the ordinary pointer (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    check(texture_path_of(hand.active_texture()) != POINT_SPRITE,
        "real route (mouse): the ordinary pointer pose is NOT what the entry draws")
    check(css.token_view(0).visible and str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "real route (mouse): the carried chip is DRAWN in the cursor carry layer")
    # The frames the owner actually looks at: the pointer never enters the
    # roster, and the chip must still be in the hand (the entry chip has no
    # roster interaction to end — the envelope exemption in char_select).
    await frames(20)
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "real route (mouse): the entry chip survives the frames after the transition (carried_by %d)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "real route (mouse): …and the CARRY grip is still what is drawn (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    check(bool(css._entry_carry),
        "real route (mouse): the entry chip is still the un-interacted entry state")
    # THE OWNER JOURNEY, on the same real route: a real pointer motion onto a
    # hold (the hover-survival helper convention) — the chip stays in the hand
    # and the CARRY grip stays drawn.
    var idle: bool = await vs.wait_css_ready(host, self)
    check(idle, "real route (mouse): the CSS leaves its entry guard")
    var tiles: Array = css.get_tiles()
    var target: int = 0
    await pointer_motion(hand, tiles[target].get_global_rect().get_center())
    tiles[target].mouse_entered.emit()
    await create_timer(0.15).timeout
    check(int(css.get_candidate()) == target,
        "real route (mouse): the pointer entering a hold moves the candidate (%d)" % int(css.get_candidate()))
    check(int(css.get_carried_by()) == 0 and hand.is_carrying() and int(hand.visual) == 1,
        "real route (mouse): the chip in the hand keeps drawing the CARRY grip over the hold (carried_by %d, visual %d)"
        % [int(css.get_carried_by()), int(hand.visual)])
    # (c) a real left click PLACES it: the pose then answers the EXISTING rule —
    # the empty pinch on the hold that HOLDS the active player's committed chip.
    await pointer_click(hand, tiles[target], tiles[target].get_global_rect().get_center())
    await create_timer(0.5).timeout
    check(str(host.selection_state.slots[0]["character"]) == str(tiles[target].fighter_id),
        "real route (mouse): the real left click places the chip (%s)"
        % str(host.selection_state.slots[0]["character"]))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "real route (mouse): the placed chip left the hand (carried_by %d)" % int(css.get_carried_by()))
    check(int(hand.visual) == 2 and texture_path_of(hand.active_texture()) == HOVER_SPRITE,
        "real route (mouse): over the chip's OWN tile the pose is the empty pinch (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    # (d) a real pad-B takes the committed chip back into the hand: the CARRY
    # grip is back in the very first frame of the taken-back state.
    await press_pad_b()
    check(int(css.get_carried_by()) == 0 and hand.is_carrying(),
        "real route (mouse): B takes the committed chip back into the hand (carried_by %d)"
        % int(css.get_carried_by()))
    check(int(hand.visual) == 1 and texture_path_of(hand.active_texture()) == CARRY_SPRITE,
        "real route (mouse): the taken-back chip draws the CARRY grip again (visual %d, %s)"
        % [int(hand.visual), texture_path_of(hand.active_texture())])
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "real route (mouse): the taken-back chip rides the cursor carry layer")
    await cleanup_real_route(host, home)

# --- (4) A / LEFT-CLICK on the committed tile DE-SELECTS (owner requirement) --
#
# THE REQUIREMENT: with a character COMMITTED for the active player, pressing A
# (controller) or LEFT-CLICKING (mouse) on that SAME tile takes the pick back —
# the chip goes back into the hand, the player ends in the "no character
# selected" state, stays in the Character Select and may pick again. It
# deliberately overrides the former explicit no-op (cf26ba1) and routes BOTH
# input paths through the SAME implementation as the staged cancel's stage 2
# (char_select._take_back_committed), so the three ways to unselect — A on the
# own tile, the left-click on the own tile and B — end in EXACTLY one end state
# (asserted equal below). A on a DIFFERENT tile still MOVES the chip; hovering
# still never lifts anything.
#
# Every pad press below is a REAL device event delivered through the engine's
# own dispatch (Input.parse_input_event) with the tile holding the engine's own
# focus — the D-pad walk between tiles is real focus navigation; every click is
# a REAL left click pushed into the viewport's GUI hit test at the tile's own
# rect (never control._gui_input directly).

func deselect_signature(css, hand, state) -> Array:
    # The end state EVERY de-select path must produce identically (A on the own
    # tile / left-click on the own tile / B): no character selected, the chip in
    # the hand's carry layer, the taken-back tile still the candidate, the
    # active player unchanged and the screen still up.
    var token = css.token_view(0)
    return [
        str(state.slots[0]["character"]),
        int(css.get_carried_by()),
        int(css.token_state(0)),
        str(token.get_parent().name) if token != null and token.get_parent() != null else "",
        int(css.get_active()),
        int(css.get_candidate()),
        bool(hand.is_carrying()),
    ]

func real_left_click(hand, control: Control) -> void:
    # A REAL left click on a roster tile: genuine pointer motion onto the tile
    # (arms the MOUSE modality, re-records the authoritative hotspot), then a
    # press + release pushed into the viewport's GUI hit test at the tile's own
    # rect — the dispatch a windowed run performs, never a private call.
    var at: Vector2 = control.get_global_rect().get_center()
    await pointer_motion(hand, at)
    check(control.get_global_rect().has_point(hand.hotspot),
        "de-select: the pointer hotspot really sits on the clicked tile (%s)" % str(hand.hotspot))
    root.push_input(Support.mouse_button_event(at, true), true)
    root.push_input(Support.mouse_button_event(at, false), true)
    await process_frame
    await process_frame

func deselect_committed_suite(vs, hand) -> void:
    arm_mouse(hand, Vector2(640.0, 20.0))
    var host = await vs.enter(self)
    var css = host.char_select()
    if css == null or not await vs.wait_css_ready(host, self):
        check(false, "de-select: a CSS is mounted and idle")
        return
    var state = host.selection_state
    var tiles: Array = css.get_tiles()
    var bays: Array = css.get_bays()
    var ggb: int = css._tile_index_of("ggb")
    var third: int = css._tile_index_of("turbofit")
    var other: int = css._tile_index_of("mephisto")
    check(ggb >= 0 and third >= 0 and other >= 0 and third != ggb and other != ggb and other != third,
        "de-select: three distinct roster tiles are available (%d/%d/%d)" % [ggb, third, other])
    await create_timer(0.4).timeout

    # --- the ACTIVE station commits through the REAL pointer path -----------
    await hover_tile_mouse(hand, css, ggb)
    await real_left_click(hand, tiles[ggb])
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "de-select (precondition): P1's chip is COMMITTED and PLACED (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "de-select (precondition): nothing is in the hand after the commit")

    # --- (d) HOVER on the committed tile still does NOTHING -----------------
    await hover_tile_mouse(hand, css, ggb)
    check(int(css.get_candidate()) == ggb and str(state.slots[0]["character"]) == "ggb",
        "de-select (d): hovering the committed tile keeps the commit and the candidate")
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying() and css.token_state(0) == PLACED,
        "de-select (d): hover NEVER lifts the committed chip (carried_by %d, state %d)"
        % [int(css.get_carried_by()), css.token_state(0)])
    check(css.token_view(0).get_parent() == tiles[ggb].token_layer(),
        "de-select (d): the chip is still owned by its committed tile after the hover")

    # --- (b) a REAL left click on the committed tile DE-SELECTS -------------
    var cancels := [0]
    connect_cancel_counter(cancels)
    await real_left_click(hand, tiles[ggb])
    await create_timer(0.3).timeout
    var click_sig := deselect_signature(css, hand, state)
    check(str(state.slots[0]["character"]) == "",
        "de-select (click): the commit is TAKEN BACK — no character selected")
    check(int(css.get_carried_by()) == 0 and css.token_state(0) == CARRIED and hand.is_carrying(),
        "de-select (click): the chip is back IN THE HAND (carried_by %d, state %d)"
        % [int(css.get_carried_by()), css.token_state(0)])
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "de-select (click): the taken-back chip rides the cursor carry layer")
    check(int(css.get_active()) == 0 and int(css.get_phase()) != 2,
        "de-select (click): the active player is unchanged (%d) and the screen is not exiting (phase %d)"
        % [int(css.get_active()), int(css.get_phase())])
    check(host.is_surface_presented("css") and css.is_visible_in_tree(),
        "de-select (click): the screen STILL IS the Character Select")
    check(int(css.get_candidate()) == ggb,
        "de-select (click): the taken-back fighter stays the candidate (%d)" % int(css.get_candidate()))
    check(cancels[0] == 0, "de-select (click): a pointer de-select never reaches the cancel signal")

    # …and the player really is in the "no character selected" state: when the
    # pointer leaves the roster the carry cancels home and the bay is BLANK —
    # nothing committed is left to present.
    await pointer_motion(hand, Vector2(640.0, 30.0))
    css.get_node("ReferenceFrame/RosterField").mouse_exited.emit()
    await create_timer(0.35).timeout
    check(int(css.get_carried_by()) == -1 and int(css.get_candidate()) == -1,
        "de-select (state): leaving the roster cancels the taken-back carry and the candidate")
    check(css.token_state(0) == UNASSIGNED and css.token_view(0).get_parent() == css.token_home_layer(),
        "de-select (state): the uncommitted chip went home (state %d)" % css.token_state(0))
    check(str(state.slots[0]["character"]) == "" and bays[0].presented_fighter() == "",
        "de-select (state): nothing is committed and the active bay is BLANK (unselected)")

    # --- (e) de-select then RE-PICK the SAME fighter (real pointer path) ----
    await hover_tile_mouse(hand, css, ggb)
    await real_left_click(hand, tiles[ggb])
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED
        and css.token_view(0).get_parent() == tiles[ggb].token_layer(),
        "de-select (re-pick): the SAME fighter can be picked again (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "de-select (re-pick): the re-pick places the chip instead of keeping it in the hand")

    # --- (a) REAL pad A on the committed tile DE-SELECTS -------------------
    # FOCUS is claimed the way §2 prescribes, the focused tile is reached by the
    # engine's own D-pad navigation from the row start, and the A press itself
    # is a real parsed pad event.
    var backs := [0]
    css.back_requested.connect(func() -> void: backs[0] += 1)
    hand.claim_focus()
    await process_frame
    tiles[0].grab_focus()
    await create_timer(0.08).timeout
    for step in ggb:
        await pad_nav(JOY_BUTTON_DPAD_RIGHT)
    await create_timer(0.08).timeout
    check(Support.focus_owner(self) == tiles[ggb],
        "de-select (pad): the D-pad walk lands the focus on the committed tile")
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "de-select (pad): browsing to the committed tile did not lift the chip (state %d)" % css.token_state(0))
    await pad_nav(JOY_BUTTON_A)
    await create_timer(0.3).timeout
    var pad_sig := deselect_signature(css, hand, state)
    check(str(state.slots[0]["character"]) == "",
        "de-select (pad A): the commit is TAKEN BACK — no character selected")
    check(int(css.get_carried_by()) == 0 and css.token_state(0) == CARRIED and hand.is_carrying(),
        "de-select (pad A): the chip is back IN THE HAND (carried_by %d, state %d)"
        % [int(css.get_carried_by()), css.token_state(0)])
    check(str(css.token_view(0).get_parent().name) == "CursorCarryLayer",
        "de-select (pad A): the taken-back chip rides the cursor carry layer")
    check(int(css.get_active()) == 0 and host.is_surface_presented("css") and css.is_visible_in_tree(),
        "de-select (pad A): the active player is unchanged (%d) and the screen is STILL the Character Select"
        % int(css.get_active()))
    check(backs[0] == 0, "de-select (pad A): the de-select never requests the BACK route")
    check(pad_sig == click_sig,
        "de-select (equivalence): the pad-A take-back ends in EXACTLY the left-click end state (%s vs %s)"
        % [str(pad_sig), str(click_sig)])

    # --- pad A with the chip IN the hand PLACES it (the same tile) ----------
    await pad_nav(JOY_BUTTON_A)
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "de-select (pad A re-pick): A on the same tile with the chip in the hand places it again (state %d)"
        % css.token_state(0))

    # --- (equivalence) B takes the same chip back through the same end state -
    await press_pad_b()
    await create_timer(0.2).timeout
    var b_sig := deselect_signature(css, hand, state)
    check(str(state.slots[0]["character"]) == "" and int(css.get_carried_by()) == 0,
        "de-select (equivalence B): the staged take-back leaves the same unselected state")
    check(b_sig == click_sig,
        "de-select (equivalence): A, the pointer and B end in ONE end state (%s vs %s)"
        % [str(b_sig), str(click_sig)])

    # --- (c) A on a DIFFERENT tile still MOVES the chip --------------------
    await pad_nav(JOY_BUTTON_A)          # the chip is in the hand: A places it again
    await create_timer(0.4).timeout
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED,
        "de-select (move precondition): the chip is committed to its own tile again")
    for step in (other - ggb):
        await pad_nav(JOY_BUTTON_DPAD_RIGHT)
    check(Support.focus_owner(self) == tiles[other],
        "de-select (move): the D-pad walk focuses another fighter's tile (%s)"
        % str(Support.focus_owner(self).get_path() if Support.focus_owner(self) != null else "-"))
    check(str(state.slots[0]["character"]) == "ggb" and css.token_state(0) == PLACED
        and css.token_view(0).get_parent() == tiles[ggb].token_layer(),
        "de-select (move): browsing another tile never lifts or moves the committed chip")
    await pad_nav(JOY_BUTTON_A)
    await create_timer(0.5).timeout
    check(str(state.slots[0]["character"]) == "mephisto",
        "de-select (move): A on a DIFFERENT tile still MOVES the commit (got '%s')"
        % str(state.slots[0]["character"]))
    check(css.token_state(0) == PLACED and css.token_view(0).get_parent() == tiles[other].token_layer(),
        "de-select (move): the chip moved onto the new tile (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "de-select (move): the move is a direct re-place, never through the hand")

    # --- (e) de-select then re-pick ANOTHER fighter (real pointer path) ----
    await pad_nav(JOY_BUTTON_A)          # the focused tile owns the committed chip: de-select
    await create_timer(0.3).timeout
    check(str(state.slots[0]["character"]) == "" and int(css.get_carried_by()) == 0
        and css.token_state(0) == CARRIED,
        "de-select (pad A, other fighter): the second take-back ends in the same unselected state")
    await hover_tile_mouse(hand, css, third)
    await real_left_click(hand, tiles[third])
    await create_timer(0.5).timeout
    check(str(state.slots[0]["character"]) == "turbofit",
        "de-select (re-pick): a DIFFERENT fighter can be picked after the de-select (got '%s')"
        % str(state.slots[0]["character"]))
    check(css.token_state(0) == PLACED and css.token_view(0).get_parent() == tiles[third].token_layer(),
        "de-select (re-pick): the new chip is PLACED on the new tile (state %d)" % css.token_state(0))
    check(int(css.get_carried_by()) == -1 and not hand.is_carrying(),
        "de-select (end): nothing is left in flight after the journey")

    if is_instance_valid(host):
        host.queue_free()
    await process_frame

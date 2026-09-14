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
# Composition/geometry invariants live in tests/test_css_composition.gd; the
# Doc 08 §4 public-input state matrices live in tests/test_css_state.gd.
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
    check(css.token_state(0) == UNASSIGNED and css.token_state(3) == UNASSIGNED, "no token is assigned at entry")
    check(not css.token_view(0).visible, "an unassigned token is not visible")
    check(css.token_view(0).get_parent() == css.token_home_layer(), "an unassigned token lives in the explicit home layer")
    check(not hand.is_carrying(), "the hand is free until the roster interaction starts")
    check(hand.visual == 0, "carry presentation is not active on entry")

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

    # --- no sticky token: leave / re-enter / release -----------------------
    # A committed player's token stays placed, and browsing lifts it without
    # ever leaving a residue behind.
    arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
    css._on_tile_entered(css._tile_index_of("doge_man"))
    check(hand.is_carrying() and css.token_state(0) == CARRIED, "browsing lifts the committed player's token again")
    check(css.token_view(0).get_parent().name == "CursorCarryLayer", "the lifted token is owned by the carry layer")
    css._leave_field()
    await create_timer(0.25).timeout
    check(not hand.is_carrying() and css.token_state(0) == PLACED, "cancelling returns the token to its committed tile")
    check(str(state.slots[0]["character"]) == "ggb", "cancelling never changed the committed fighter")
    check(css.get_carried_by() == -1, "no carry survives the cancel (carried_by %d)" % css.get_carried_by())
    check(css.token_view(0).get_parent() == tile_node.token_layer(), "the returned token is owned by the committed tile again")
    # leave / re-enter repeatedly: the FSM never sticks
    for i in 3:
        arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
        css._on_tile_entered(tile_ggb)
        css._leave_field()
    await create_timer(0.25).timeout
    check(not hand.is_carrying() and css.token_state(0) == PLACED and css.get_carried_by() == -1,
        "the leave/re-enter loop never leaves a sticky token")

    # --- active-player switch resolves the previous player's carry ---------
    arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
    css._on_tile_entered(css._tile_index_of("doge_man"))
    check(css.get_carried_by() == 0, "precondition: P1's token is carried")
    css._on_bay_activated(1)
    check(css.get_carried_by() == -1, "switching the active player resolves the previous player's carry first")
    check(css.get_active() == 1, "bay activation changes the active player explicitly")
    await create_timer(0.3).timeout
    check(css.token_state(0) == PLACED, "the old player's token returns to its committed tile")
    check(css.token_view(0).get_parent() == tile_node.token_layer(), "…and is owned by the committed tile again")
    # committing for P2 (already a CPU) keeps P1's token intact
    css._on_tile_pressed("ggb")
    await create_timer(0.3).timeout
    check(str(state.slots[1]["character"]) == "ggb", "P2 committed the duplicate pick")
    check(css.token_state(1) == PLACED and css.token_state(0) == PLACED, "two players can commit the same fighter")
    var t0 = css.token_view(0)
    var t1 = css.token_view(1)
    var r0 := Rect2(t0.position, t0.size)
    var r1 := Rect2(t1.position, t1.size)
    check(not r0.intersects(r1), "placed tokens on one tile never overlap exactly")
    check(css.get_active() == 1, "committing does not advance the active player")

    # --- kind transitions never silently create a fighter ------------------
    # Setting a slot EMPTY cancels its interaction, clears the fighter and
    # leaves the token UNASSIGNED (Doc 04 §6, ledger C-039).
    css._on_bay_activated(1)
    arm_mouse(hand, tiles[tile_ggb].get_global_rect().get_center())
    css._on_tile_entered(css._tile_index_of("mephisto"))
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

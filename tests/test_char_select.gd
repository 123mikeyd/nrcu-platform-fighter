extends SceneTree
# Character Select — canonical interaction contract (Doc 04 §30).
#
# Composition/geometry invariants live in tests/test_css_composition.gd;
# this suite drives the INTERACTION: token FSM, candidate vs committed,
# ready gating, the production route and the backtracking contract.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

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
    # --- tokens: one per player, screen-local FSM -------------------------
    check(css.token_view(0) != null and css.token_view(3) != null, "four token views exist")
    # Defaults commit P1 = TEKNIUM, so P1's token rests PLACED from the start.
    check(css.token_state(0) == 1, "a committed player's token rests PLACED on its tile")
    check(css.token_state(2) == 1, "every committed player owns a token")
    check(not hand.is_carrying(), "the hand is free until the roster interaction starts")
    check(hand.visual == 0, "carry presentation is not active on entry")
    # --- candidate vs committed -------------------------------------------
    var tiles: Array = css.get_tiles()
    check(tiles.size() == 7, "seven roster tiles")
    var tile_ggb: int = css._tile_index_of("ggb")
    var committed_before := str(state.slots[0].character)
    # mouse motion arms hover; entering a tile starts the carry
    var motion := InputEventMouseMotion.new()
    motion.position = tiles[tile_ggb].get_global_rect().get_center()
    motion.relative = Vector2(30.0, 0.0)
    hand._input(motion)
    css._on_tile_entered(tile_ggb)
    check(css.get_candidate() == tile_ggb, "hovering sets the candidate tile")
    check(hand.is_carrying(), "entering the roster carries the active player's token")
    check(css.token_state(0) == 2, "P1 token state is CARRIED")
    check(str(state.slots[0].character) == committed_before, "hovering never writes the committed fighter")
    # leaving the roster returns the token without committing
    css._leave_field()
    check(not hand.is_carrying(), "leaving the roster frees the hand")
    check(css.token_state(0) == 1, "the token returns PLACED to its committed tile")
    check(str(state.slots[0].character) == "teknium", "leaving the roster never changed the committed fighter")
    # --- commit -----------------------------------------------------------
    css._on_tile_entered(tile_ggb)
    css._on_tile_pressed(str(css._cards[tile_ggb]["id"]))
    check(str(state.slots[0].character) == "ggb", "confirm commits the fighter to the active player")
    check(css.token_state(0) == 1, "the token settles PLACED on the committed tile")
    check(not hand.is_carrying(), "the hand returns to free after committing")
    var token_node = css.token_view(0)
    var tile_node = tiles[tile_ggb]
    check(token_node.get_parent() == tile_node.token_layer(), "the placed token lives on the committed tile")
    var name_band: Rect2 = tile_node.name_band_rect()
    var token_rect := Rect2(token_node.position, token_node.size)
    check(not token_rect.intersects(name_band) or token_rect.get_area() == 0.0, "the token does not cover the name band")
    # --- duplicate picks: deterministic, non-overlapping -------------------
    css._on_bay_activated(1)
    check(css.get_active() == 1, "bay activation changes the active player explicitly")
    css._on_tile_pressed("ggb")
    check(css.token_state(1) == 1 and css.token_state(0) == 1, "two players can commit the same fighter")
    var t0 = css.token_view(0)
    var t1 = css.token_view(1)
    var r0 := Rect2(t0.position, t0.size)
    var r1 := Rect2(t1.position, t1.size)
    check(not r0.intersects(r1), "placed tokens on one tile never overlap exactly")
    check(str(state.slots[1].character) == "ggb", "P2 committed the duplicate pick")
    # active player persists after commit (never auto-advances)
    check(css.get_active() == 1, "committing does not advance the active player")
    # --- carry clears when leaving the roster for another control ---------
    css._on_tile_entered(css._tile_index_of("doge_man"))
    check(hand.is_carrying(), "re-entering the roster lifts the active player's token again")
    # Moving toward Back/Mode/Ready/bays crosses out of the roster interaction
    # field, which returns the token (mouse path).
    css._leave_field()
    check(not hand.is_carrying(), "moving out of the roster clears the carry")
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
    check(str(state.slots[css.get_active()].character) == str(kb_tiles[1].fighter_id), "Enter commits the keyboard-focused tile")
    css._on_tile_pressed("ggb")  # restore the scenario state for the route below
    check(css.get_carried_by() == -1, "no carry after the restore commit (carried_by %d)" % css.get_carried_by())
    check(not hand.is_carrying(), "no carried token after the restore commit")

    # --- ready gating -----------------------------------------------------
    # P1 ggb (human) + P2 committed ggb + P3/P4 CPUs: four active players.
    check(state.can_ready(), "four active players can ready")
    check(css.get_ready_band().is_shown(), "the ready band shows when the configuration is valid")
    check(css.ready_allowed(), "ready_allowed mirrors the persistent validation")
    css._on_kind_clicked(3)
    check(str(state.slots[3].kind) == "empty", "kind control cycles to EMPTY")
    check(css.get_ready_band().is_shown(), "three active players still ready")
    css._on_kind_clicked(2)
    check(state.active_count() == 2 and state.can_ready(), "the free-for-all minimum is two fighters")
    check(css.get_ready_band().is_shown(), "two active players still ready")
    css._on_kind_clicked(1)
    check(state.active_count() == 1 and not state.can_ready(), "one active player cannot ready")
    check(not css.get_ready_band().is_shown(), "no ready band while the configuration is invalid")
    var exits := [0]
    css.ready_requested.connect(func(): exits[0] += 1)
    css._on_ready_pressed()
    await process_frame
    check(exits[0] == 0, "READY is inert while invalid")
    css._on_kind_clicked(1)
    check(state.active_count() == 2 and state.can_ready(), "config valid again")
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
    check(arena.fighters.size() == 2, "the match starts with the selected fighters")
    check(str(arena.fighters[0].character_id) == "ggb" and str(arena.fighters[1].character_id) == "ggb", "committed fighters reach the match")
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
    var motion3 := InputEventMouseMotion.new()
    motion3.position = Vector2(640.0, 200.0)
    motion3.relative = Vector2(25.0, 0.0)
    hand._input(motion3)
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
    if failures == 0: print("PASS: character select interaction (tokens, candidate/committed, ready gating, route, preservation)")
    quit(1 if failures else 0)

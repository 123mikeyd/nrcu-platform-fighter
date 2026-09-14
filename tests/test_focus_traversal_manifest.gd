extends SceneTree
# Doc 08 §5 — machine-readable focus traversal manifest (WP-1 gate proof).
#
# For EVERY focusable control on every frontend screen this suite drives the
# PUBLIC input path (a real semantic navigation event that claims FOCUS, then a
# focus-enter on the control, the way the engine's own focus navigation does),
# waits for the focus hand to settle, and records:
#
#   screen / control / public input reached / expected CursorAnchor
#   / actual hand target hotspot / distance px / tolerance / PASS / FAIL
#
# The manifest is written as JSON to .verification/focus_traversal_manifest.json
# and a compact summary is printed. Nothing here calls a screen's private input
# handler: activation states are entered through the shipped surfaces (the
# MatchFlow route, the Main menu's own pages) and the traversal is driven by
# semantic events on the tree.
#
# The §6 REAR contract is covered by the recovery rows at the end: when a
# focused control disappears or becomes disabled, the logical focus must move to
# the correct surviving semantic neighbour, the hand must retarget, and no
# hidden control may keep the focus.

const Manifest = preload("res://scripts/frontend/focus_graph.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

const MANIFEST_PATH := "res://.verification/focus_traversal_manifest.json"
# The hand settles exactly on an authored anchor. 0.5 px is the spring's own
# convergence floor (critically damped, closed form); the anchored rows are
# expected at ~0.0 px and the tolerance only exists so a 1-2 frame settling
# difference can never produce a false failure.
const TOLERANCE_PX := 0.5

var failures := 0
var checks_run := 0
var rows: Array = []
var service: Node = null
var hand: Control = null
var home: Control = null
var host: Node = null
var css: Control = null
var sss: Control = null
var story: Control = null
var howto: Control = null
var results: Control = null
var post: Node = null

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
    checks_run += 1
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func settle(count := 6) -> void:
    for i in count:
        await process_frame

# --- semantic input helpers (public path) -----------------------------------

func key_event(code: Key, pressed := true) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed
    return event

func claim_focus_mode() -> void:
    # §2: FOCUS is claimed by MEANINGFUL frontend input. A real ui_down key
    # event through the tree is that input; it never warps the pointer.
    Input.parse_input_event(key_event(KEY_DOWN, true))
    await frames(3)
    Input.parse_input_event(key_event(KEY_DOWN, false))
    await frames(2)

# --- public-input configuration helpers (CSS) --------------------------------
# The locked fresh defaults preselect NO fighter and start below the two-active
# minimum, so a route needs a configuration built the way a player builds it:
# semantic accept on a station (activates it) and on a roster tile (commits).

func semantic_activate(control: Control) -> void:
    control.grab_focus()
    await frames(2)
    Input.parse_input_event(key_event(KEY_ENTER, true))
    await frames(3)
    Input.parse_input_event(key_event(KEY_ENTER, false))
    await frames(2)

func css_set_kind(css: Control, player_index: int, kind: String) -> bool:
    # The station kind cycles through the bay's own kind control (its public
    # button path), never a private screen helper.
    var bay: Control = css.get_bays()[player_index - 1]
    for _press in 3:
        if str(bay.kind) == kind:
            return true
        (bay.state_control("kind") as Button).pressed.emit()
        await frames(2)
    return str(bay.kind) == kind

func css_commit(css: Control, player_index: int, fighter_id: String) -> bool:
    await semantic_activate(css.get_bays()[player_index - 1])
    if css.get_active() != player_index - 1:
        return false
    var tile: Control = null
    for t in css.get_tiles():
        if str(t.fighter_id) == fighter_id:
            tile = t
            break
    if tile == null:
        return false
    await semantic_activate(tile)
    await frames(6)
    return str(css._state.slots[player_index - 1].get("character", "")) == fighter_id

func css_configure_route(css: Control) -> bool:
    # P1 Human (doge_man) + P2 CPU (ggb): the fresh-default station kinds with
    # fighters committed — >= 2 active and >= 1 Human.
    if not await css_commit(css, 1, "doge_man"):
        return false
    if not await css_commit(css, 2, "ggb"):
        return false
    return css.ready_allowed()

func css_ensure_valid(css: Control) -> bool:
    # Rebuilds the valid configuration after the invalidating recovery rows —
    # station kinds first, then the missing fighters, all through public input.
    var kinds := ["human", "bot", "empty", "empty"]
    for i in 4:
        if not await css_set_kind(css, i + 1, kinds[i]):
            return false
    for i in 2:
        if str(css._state.slots[i].get("character", "")) == "":
            var id := "doge_man" if i == 0 else "ggb"
            if not await css_commit(css, i + 1, id):
                return false
    return css.ready_allowed()

func enter_focus(control: Control) -> void:
    # Focus-enter as the engine's focus navigation performs it. The screens'
    # own focus_entered handlers must then establish logical focus, control
    # emphasis and the hand target atomically (§6).
    control.grab_focus()
    await frames(2)

func settle_hand(limit := 48) -> void:
    # Runs the real spring until it has settled (or the budget runs out).
    for i in limit:
        await process_frame
        if hand != null and hand.mode == 1 and hand._focus_anchor != null:
            var target: Vector2 = hand._focus_anchor.get_global_rect().position
            if hand.hotspot.distance_to(target) <= TOLERANCE_PX:
                return

# --- enumeration -------------------------------------------------------------

func focusable_controls(root_node: Node) -> Array:
    # Every control that can own focus in the CURRENT configuration, in tree
    # order so the manifest is reproducible.
    var out: Array = []
    _collect(root_node, out)
    return out

func _collect(node: Node, out: Array) -> void:
    for child in node.get_children():
        if child is Control:
            var control := child as Control
            if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
                if not (control is BaseButton and (control as BaseButton).disabled):
                    out.append(control)
        _collect(child, out)

func label_of(control: Control) -> String:
    var path := str(control.get_path())
    if control is BaseButton and str((control as BaseButton).text) != "":
        return "%s [%s]" % [path, str((control as BaseButton).text)]
    return path

# --- topology assertions (Doc 03 §13: authored graphs, never tree order) ----

func authored_path(control: Control, direction: StringName) -> Control:
    return Manifest.neighbour(control, direction)

func check_edge(screen: String, control: Control, direction: StringName, expected: Control, note: String) -> void:
    var actual := authored_path(control, direction)
    var ok := (expected == null and actual == null) or (expected != null and actual == expected)
    check(ok, "%s: %s [%s] (expected %s, got %s)" % [
        note if screen == "" else screen + ": " + note, str(control.get_path()), str(direction),
        str(expected.get_path()) if expected != null else "<none>",
        str(actual.get_path()) if actual != null else "<none>"])

func check_nav(screen: String, control: Control, key: Key, expected: Control, note: String) -> void:
    # Drives the real engine focus navigation (the authored neighbours decide
    # the result) — nothing here re-implements the search.
    await enter_focus(control)
    Input.parse_input_event(key_event(key, true))
    await frames(3)
    Input.parse_input_event(key_event(key, false))
    await frames(2)
    var owner := service.focus_owner() as Control
    check(owner == expected, "%s: %s (expected %s, got %s)" % [
        screen, note,
        str(expected.get_path()) if expected != null else "<none>",
        str(owner.get_path()) if owner != null else "<none>"])

# --- manifest rows -----------------------------------------------------------

func anchor_for(screen: String, control: Control) -> Control:
    # The screen's authored declaration of the hand target for this control.
    match screen:
        "main", "main_modal":
            return home.focus_anchor_for(control)
        "css":
            return css.focus_anchor_for(control)
        "sss":
            return sss.focus_anchor_for(control)
        "story":
            return story.focus_anchor_for(control)
        "how_to_play":
            return howto.focus_anchor_for(control)
        "results":
            return results.focus_anchor_for(control)
    return null

func record(screen: String, control: Control, method: String, note := "") -> void:
    var expected := anchor_for(screen, control)
    var row := {
        "screen": screen,
        "control": label_of(control),
        "control_path": str(control.get_path()),
        "input_method": method,
        "expected_anchor": str(expected.get_path()) if expected != null else "",
        "hand_target": "",
        "hand_hotspot": [0.0, 0.0],
        "distance_px": -1.0,
        "tolerance_px": TOLERANCE_PX,
        "pass": false,
        "note": note,
    }
    if expected == null:
        row["note"] = "no authored CursorAnchor for a focusable control"
        rows.append(row)
        check(false, "%s: focusable control without an authored anchor: %s" % [screen, row["control"]])
        return
    if not expected.has_method("anchor_position"):
        row["note"] = "hand target is not an authored CursorAnchor"
        rows.append(row)
        check(false, "%s: hand target is not an authored CursorAnchor: %s" % [screen, row["control"]])
        return
    var target: Vector2 = expected.get_global_rect().position
    var hotspot: Vector2 = hand.hotspot if hand != null else Vector2.ZERO
    var distance := hotspot.distance_to(target)
    if hand != null and hand._focus_anchor != null and is_instance_valid(hand._focus_anchor):
        row["hand_target"] = str(hand._focus_anchor.get_path())
    row["hand_hotspot"] = [snappedf(hotspot.x, 0.001), snappedf(hotspot.y, 0.001)]
    row["distance_px"] = snappedf(distance, 0.001)
    row["pass"] = distance <= TOLERANCE_PX
    rows.append(row)
    check(row["pass"], "%s: hand settled %.3f px away from %s (control %s, hand %s)" % [
        screen, distance, row["expected_anchor"], row["control"], str(row["hand_target"])])

func wait_visible(node: Control, limit := 240) -> bool:
    for i in limit:
        if node != null and is_instance_valid(node) and node.is_visible_in_tree():
            return true
        await process_frame
    return false

func visit(screen: String, root_node: Node, method: String) -> int:
    # Focus-enter every focusable control of a screen through the public path
    # and record the hand result. Returns the number of controls covered.
    var controls := focusable_controls(root_node)
    for control in controls:
        await enter_focus(control)
        await settle_hand()
        record(screen, control, method)
    return controls.size()

# --- recovery rows (§6 rear contract) ---------------------------------------

func record_recovery(screen: String, control: Control, action: Callable, note: String, expect_within: Node = null) -> void:
    await enter_focus(control)
    await settle_hand()
    var before_anchor := anchor_for(screen, control)
    action.call()
    await frames(4)
    var owner := service.focus_owner() as Control
    var row := {
        "screen": screen,
        "control": label_of(control),
        "control_path": str(control.get_path()),
        "input_method": "recovery",
        "expected_anchor": str(before_anchor.get_path()) if before_anchor != null else "",
        "hand_target": "",
        "hand_hotspot": [0.0, 0.0],
        "distance_px": -1.0,
        "tolerance_px": TOLERANCE_PX,
        "pass": false,
        "note": note,
    }
    var hidden := control
    if owner != null and owner == hidden:
        row["note"] = note + " | the hidden/disabled control kept the focus"
        rows.append(row)
        check(false, "%s: the hidden control kept the focus (%s)" % [screen, str(hidden.get_path())])
        return
    if owner == null:
        row["note"] = note + " | focus released with no survivor (the control has no neighbour in this state)"
        row["pass"] = true
        rows.append(row)
        return
    var anchor := anchor_for(screen, owner)
    if anchor == null:
        anchor = Manifest.anchor_of(owner)
    if anchor == null:
        row["note"] = note + " | survivor has no authored anchor: " + str(owner.get_path())
        rows.append(row)
        check(false, "%s: recovery survivor has no authored anchor: %s" % [screen, str(owner.get_path())])
        return
    if expect_within != null:
        # §13: a bay's nested controls keep the focus inside their bay (the bay
        # control itself is that bay's own exit target, so it counts as inside).
        check(owner == expect_within or expect_within.is_ancestor_of(owner),
            "%s: recovery stayed inside its own zone (owner %s, zone %s)" % [
                screen, str(owner.get_path()), str(expect_within.get_path())])
    await settle_hand()
    var target: Vector2 = anchor.get_global_rect().position
    var hotspot: Vector2 = hand.hotspot
    var distance := hotspot.distance_to(target)
    row["hand_target"] = str(hand._focus_anchor.get_path()) if hand._focus_anchor != null else ""
    row["expected_anchor"] = str(anchor.get_path())
    row["hand_hotspot"] = [snappedf(hotspot.x, 0.001), snappedf(hotspot.y, 0.001)]
    row["distance_px"] = snappedf(distance, 0.001)
    row["pass"] = distance <= TOLERANCE_PX
    row["note"] = note + " | focus moved to " + str(owner.get_path())
    rows.append(row)
    check(row["pass"], "%s: recovery hand settled %.3f px away from %s (owner %s)" % [
        screen, distance, row["expected_anchor"], str(owner.get_path())])

# --- run ---------------------------------------------------------------------

func run():
    var cursor = root.get_node_or_null("Cursor")
    check(cursor != null and cursor.hand != null, "cursor service reachable")
    if cursor == null or cursor.hand == null:
        quit(1)
        return
    hand = cursor.hand
    service = root.get_node_or_null("FrontendInput")
    check(service != null, "semantic input service reachable")
    if service == null:
        quit(1)
        return

    # --- Main (rows) --------------------------------------------------------
    home = (load("res://scenes/home.tscn") as PackedScene).instantiate()
    root.add_child(home)
    await settle(12)
    await claim_focus_mode()
    var main_count := await visit("main", home, "semantic-nav + focus-enter")
    check(main_count == 4, "Main exposes exactly the four authored destinations (%d)" % main_count)
    var rows_hit: Array = []
    for row in home.menu_rows():
        rows_hit.append(row.get_node("HitArea"))
    check_edge("main", rows_hit[0], &"bottom", rows_hit[1], "the rail is authored in order (PLAY -> STORY MODE)")
    check_edge("main", rows_hit[0], &"top", rows_hit[3], "the rail closes at the top")
    await check_nav("main", rows_hit[0], KEY_DOWN, rows_hit[1], "ui_down walks the authored rail")
    await check_nav("main", rows_hit[3], KEY_DOWN, rows_hit[0], "ui_down continues at the last destination")

    # --- Main + Quit modal --------------------------------------------------
    home.show_page("quit")
    await settle(12)
    await claim_focus_mode()
    var modal_count := await visit("main_modal", home, "modal open + focus-enter")
    check(modal_count == 2, "the Quit modal exposes exactly Stay and Quit (%d)" % modal_count)
    var action_stay: Button = home.find_child("ActionStay", true, false)
    var action_quit: Button = home.find_child("ActionQuit", true, false)
    check_edge("main_modal", action_stay, &"right", action_quit, "the modal's two actions are an authored pair")
    check_edge("main_modal", action_quit, &"left", action_stay, "and back")
    await check_nav("main_modal", action_stay, KEY_RIGHT, action_quit, "ui_right moves to QUIT")
    home.show_page("home")
    await settle(8)

    # --- Character Select (FFA defaults) ------------------------------------
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    host = await vs.enter(self)
    css = host.char_select()
    check(css != null, "Character Select mounted by the production route")
    await vs.wait_css_ready(host, self)
    await settle(6)
    await claim_focus_mode()
    var css_count := await visit("css", css, "semantic-nav + focus-enter")
    check(css_count >= 7 + 4 + 4, "CSS covers the roster, the bays and the header (%d)" % css_count)

    # --- CSS topology (Doc 03 §13, authored — not tree order) ---------------
    var tiles: Array = css.get_tiles()
    var bays: Array = css.get_bays()
    var css_back: Button = css.get_node("ReferenceFrame/Header/BackAction")
    var mode_free: Label = css.get_node("ReferenceFrame/Header/ModeControl/ModeFree")
    var mode_teams: Label = css.get_node("ReferenceFrame/Header/ModeControl/ModeTeams")
    var bay_kind: Button = bays[0].state_control("kind")
    check_edge("css", tiles[0], &"right", tiles[1], "the roster runs nearest-in-row to the right")
    check_edge("css", tiles[1], &"left", tiles[0], "and back to the left")
    check_edge("css", tiles[tiles.size() - 1], &"right", null, "the row ends at the last tile (no wrap)")
    check_edge("css", tiles[0], &"top", css_back, "the roster's top row reaches the header Back")
    check_edge("css", bays[0], &"top", tiles[0], "a station returns to the nearest roster tile")
    check_edge("css", bays[0], &"right", bays[1], "stations are adjacent in x")
    check_edge("css", bays[3], &"right", bays[0], "the station row closes")
    check_edge("css", mode_free, &"right", mode_teams, "header destinations follow x")
    check_edge("css", mode_teams, &"right", css_back, "header destinations follow x (Back last)")
    check_edge("css", bays[0], &"bottom", bay_kind, "down enters the station's own controls")
    check_edge("css", bay_kind, &"top", bays[0], "the first control's up exits into the bay")
    check_edge("css", bay_kind, &"left", bays[0], "horizontal stays inside the bay (exit into the bay)")
    check_edge("css", bay_kind, &"right", bays[0], "horizontal stays inside the bay (exit into the bay)")
    await check_nav("css", tiles[0], KEY_RIGHT, tiles[1], "ui_right walks the roster")
    await check_nav("css", bays[0], KEY_DOWN, bay_kind, "ui_down enters the station's state controls")
    await check_nav("css", bay_kind, KEY_LEFT, bays[0], "the horizontal exit leaves the state controls for the bay")

    # --- public-input configuration (locked fresh defaults are NOT ready) ---
    # Doc 01 §2: nothing is preselected, so the fresh screen cannot ready yet.
    # The route below needs a valid configuration, and it is built exactly the
    # way the player builds it: semantic accept on the stations and the tiles.
    check(not css.ready_allowed(), "the fresh CSS is not ready (no fighter is preselected)")
    var p1_committed: bool = await css_commit(css, 1, "doge_man")
    var p2_committed: bool = await css_commit(css, 2, "ggb")
    check(p1_committed and p2_committed, "fighters commit through the public semantic path")
    check(css.ready_allowed(), "P1 Human + P2 CPU with fighters passes the ONE authority")
    check_edge("css", tiles[0], &"bottom", css.get_ready_band(),
        "the bottom roster row reaches the Ready band while it is shown")

    # --- §6 rear contract on CSS: a focused control that disappears ---------
    # The CPU difficulty row belongs to CPU stations only. Focusing it and
    # switching that station away from CPU hides it under the focus.
    var difficulty: Button = null
    var cpu_bay = null
    for bay in css.get_bays():
        if bay.difficulty_row_visible():
            cpu_bay = bay
            difficulty = bay.state_control("difficulty")
            break
    if difficulty != null and cpu_bay != null:
        var drop_cpu := func() -> void:
            (cpu_bay.state_control("kind") as Button).pressed.emit()
        await record_recovery("css", difficulty, drop_cpu,
            "the station stops being a CPU: the difficulty row disappears", cpu_bay)

    # The Ready band disappears when the configuration becomes invalid.
    var band = css.get_ready_band()
    if band.is_shown():
        var invalidate := func() -> void:
            for bay in css.get_bays():
                for _press in 3:
                    if not css.ready_allowed():
                        return
                    if str(bay.kind) == "empty":
                        break
                    (bay.state_control("kind") as Button).pressed.emit()
        await record_recovery("css", band, invalidate,
            "the configuration becomes invalid: the Ready band disappears")
    check(not css.ready_allowed(), "the configuration is invalid after the recovery row")
    check_edge("css", tiles[0], &"bottom", bays[0],
        "the bottom roster row reaches the nearest station when the band is not shown")
    # Restore a valid configuration for the stage route below, through the same
    # public input path the recovery rows used.
    check(await css_ensure_valid(css), "the CSS configuration is restored for the stage route")

    # --- Character Select (teams mode exposes the team controls) ------------
    var teams_label: Label = css.get_node("ReferenceFrame/Header/ModeControl/ModeTeams")
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    teams_label.gui_input.emit(click)
    await settle(6)
    await claim_focus_mode()
    var team_count := await visit("css", css, "teams configuration + focus-enter")
    check(team_count >= 7 + 4 + 4, "the teams configuration covers its extra state controls (%d)" % team_count)
    # Back to the default free-for-all before the stage route (the same public
    # mouse path a player uses on the header destination).
    var free_label: Label = css.get_node("ReferenceFrame/Header/ModeControl/ModeFree")
    free_label.gui_input.emit(click)
    await settle(6)
    check(int(css._state.mode) == 0, "the mode control returns to free-for-all")

    # --- Stage Select -------------------------------------------------------
    var ready_ok: bool = await vs.ready(host, self)
    check(ready_ok, "READY opens the stage page")
    sss = host.stage_select()
    check(sss != null, "Stage Select mounted by the production route")
    var sss_visible: bool = await wait_visible(sss)
    check(sss_visible, "Stage Select is presented (visible) for the traversal")
    for i in 240:
        await process_frame
        if sss._phase == 1 and sss._lock <= 0.0 and sss.get_tiles().size() > 0:
            break
    await settle(6)
    await claim_focus_mode()
    var sss_count := await visit("sss", sss, "semantic-nav + focus-enter")
    check(sss_count == 3 + 1, "Stage Select covers the 3x3 field tiles plus Back (%d)" % sss_count)
    var sss_tiles: Array = sss.get_tiles()
    var sss_back: Button = sss.get_back_button()
    check_edge("sss", sss_tiles[0], &"right", sss_tiles[1], "the field graph follows the grid row")
    check_edge("sss", sss_tiles[1], &"left", sss_tiles[0], "and back")
    check_edge("sss", sss_tiles[0], &"top", sss_back, "the top row reaches Back")
    check_edge("sss", sss_back, &"bottom", sss_tiles[0], "Back returns into the field")
    check_edge("sss", sss_tiles[sss_tiles.size() - 1], &"right", null, "the grid row does not wrap")
    await check_nav("sss", sss_tiles[0], KEY_RIGHT, sss_tiles[1], "ui_right moves along the field")
    await check_nav("sss", sss_tiles[1], KEY_UP, sss_back, "ui_up reaches Back")
    await enter_focus(sss_tiles[2])
    await frames(4)
    check(sss.get_hovered_id() == str(sss._slots[2]["id"]),
        "a focus move previews the focused stage exactly like mouse hover")
    check(sss.get_name_text().to_upper() == str(sss._slots[2]["name"]).to_upper(),
        "the focused stage's name is the authored preview name")
    vs.free_hosts(self)

    # --- Story briefing -----------------------------------------------------
    host = await vs.enter(self, "story")
    story = host.story_briefing()
    check(story != null, "Story briefing mounted by the production route")
    await settle(12)
    await claim_focus_mode()
    var story_count := await visit("story", story, "semantic-nav + focus-enter")
    check(story_count == 6 + 2, "Story covers the playable roster plus Back and the action (%d)" % story_count)

    # §6 rear contract: the encounter resolves — the ready body (and the whole
    # roster inside it) disappears while a tile owns the focus.
    var story_tiles: Array = story.roster_tiles()
    check_edge("story", story_tiles[0], &"right", story_tiles[1], "the roster strip is authored in sequence")
    check_edge("story", story_tiles[0], &"top", story.back_button(), "the roster reaches Back")
    check_edge("story", story.back_button(), &"bottom", story.action_button(), "Back and the action are adjacent")
    # The CSV gap: Enter/Space must ACTIVATE the focused tile through the
    # semantic accept path (focus alone already previews the selection).
    if story_tiles.size() >= 3:
        await enter_focus(story_tiles[1])
        story.select_fighter(str(story.roster_ids()[0]))
        await frames(2)
        Input.parse_input_event(key_event(KEY_ENTER, true))
        await frames(3)
        Input.parse_input_event(key_event(KEY_ENTER, false))
        await frames(2)
        check(story.selected_fighter_id() == str(story.roster_ids()[1]),
            "Enter activates the focused story tile through the semantic accept path")
        story.select_fighter(str(story.roster_ids()[0]))
        await frames(2)
        Input.parse_input_event(key_event(KEY_SPACE, true))
        await frames(3)
        Input.parse_input_event(key_event(KEY_SPACE, false))
        await frames(2)
        check(story.selected_fighter_id() == str(story.roster_ids()[1]),
            "Space activates the focused story tile through the semantic accept path")
    if not story_tiles.is_empty():
        var resolve_encounter := func() -> void:
            story.show_result(true)
        await record_recovery("story", story_tiles[0], resolve_encounter,
            "the encounter resolves: the ready body and its roster disappear")
    vs.free_hosts(self)

    # --- How to Play (the production help page inside Main) -----------------
    home.show_page("help")
    await settle(12)
    howto = home.find_child("HowToPlay", true, false)
    check(howto != null, "How to Play mounted as the Main menu's own page")
    await claim_focus_mode()
    var help_basics := await visit("how_to_play", howto, "semantic-nav + focus-enter")
    check(help_basics == 2 + 3 + 1, "How to Play BASICS covers both tabs, the profile segments and Back (%d)" % help_basics)
    howto.show_section("FIGHTERS")
    await settle(8)
    await claim_focus_mode()
    var help_fighters := await visit("how_to_play", howto, "semantic-nav + focus-enter (FIGHTERS)")
    check(help_fighters == 2 + 7 + 1, "How to Play FIGHTERS covers both tabs, the roster and Back (%d)" % help_fighters)
    var basics_tab: Button = howto.get_node("ReferenceFrame/TabBand/SectionBasics/HitArea")
    var fighters_tab: Button = howto.get_node("ReferenceFrame/TabBand/SectionFighters/HitArea")
    check_edge("how_to_play", basics_tab, &"right", fighters_tab, "the section tabs are one authored pair")
    check_edge("how_to_play", fighters_tab, &"left", basics_tab, "and back")
    check(howto.tab_anchor("FIGHTERS") != null, "the tabs resolve their authored anchors")
    check(howto.profile_anchor("P1_KEYBOARD") != null and howto.profile_anchor("CONTROLLER") != null,
        "the input-profile segments resolve their authored anchors")
    await check_nav("how_to_play", fighters_tab, KEY_RIGHT, howto.roster_tiles()[0],
        "the FIGHTERS tab reaches the roster through the authored chain")
    home.show_page("home")
    await settle(8)

    # --- Results (the PostMatch surface of the production route) ------------
    host = await vs.enter(self)
    css = host.char_select()
    await vs.wait_css_ready(host, self)
    var host_id: int = host.get_instance_id()
    var arena = await vs.launch(self, host, ["teknium", "doge_man", "ggb", "turbofit"], "debug")
    check(arena != null, "the FFA launches for the Results traversal")
    if arena != null:
        await vs.resolve(self, arena, [1])
        host = await vs.wait_for_flow(self, host_id)
        post = host.post_match() if host != null else null
        check(post != null, "the resolved match RETURNs to the PostMatch surface")
        if post != null:
            results = post.result_screen
            results.finish_reveal()
            await settle(10)
            await claim_focus_mode()
            var results_count := await visit("results", results, "semantic-nav + focus-enter")
            check(results_count == 4, "Results exposes exactly the four actions (%d)" % results_count)
            # Doc 03 §13: REMATCH <-> CHANGE FIGHTERS <-> CHANGE STAGE <->
            # MAIN MENU, explicitly authored, NO wrap.
            var chain: Array = results.action_chain()
            check_edge("results", chain[0], &"right", chain[1], "REMATCH <-> CHANGE FIGHTERS")
            check_edge("results", chain[1], &"right", chain[2], "CHANGE FIGHTERS <-> CHANGE STAGE")
            check_edge("results", chain[2], &"right", chain[3], "CHANGE STAGE <-> MAIN MENU")
            check_edge("results", chain[1], &"left", chain[0], "and back down the chain")
            check_edge("results", chain[0], &"left", null, "the chain does not wrap (REMATCH has no left)")
            check_edge("results", chain[3], &"right", null, "the chain does not wrap (MAIN MENU has no right)")
            await check_nav("results", chain[0], KEY_RIGHT, chain[1], "ui_right walks the action chain")
            await check_nav("results", chain[0], KEY_LEFT, chain[0], "ui_left on the first action does not wrap")
            await check_nav("results", chain[3], KEY_RIGHT, chain[3], "ui_right on the last action does not wrap")
            # §6 rear contract: CHANGE STAGE disappears when the match does not
            # allow a stage change (the shipped show_result API).
            var stage_button: Button = chain[2] if chain.size() == 4 else null
            if stage_button != null:
                var drop_stage := func() -> void:
                    results.show_result(results.get_result(), false)
                    results.finish_reveal()
                await record_recovery("results", stage_button, drop_stage,
                    "CHANGE STAGE is not supported by this match: the action disappears")

    # --- manifest ----------------------------------------------------------
    var passed := 0
    var covered := 0
    for row in rows:
        covered += 1
        if bool(row["pass"]):
            passed += 1
    var manifest := {
        "contract": "Doc 08 §5 focus coverage traversal manifest (WP-1 gate)",
        "generated_by": "tests/test_focus_traversal_manifest.gd",
        "tolerance_px": TOLERANCE_PX,
        "rows": rows,
        "summary": {
            "focusables": covered,
            "passed": passed,
            "failed": covered - passed,
            "tolerance_px": TOLERANCE_PX,
            "screens": ["main", "main_modal", "css", "sss", "story", "how_to_play", "results"],
        },
    }
    var absolute := ProjectSettings.globalize_path(MANIFEST_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
    if file == null:
        check(false, "manifest could not be written to %s" % MANIFEST_PATH)
    else:
        file.store_string(JSON.stringify(manifest, "  "))
        file.close()
        print("MANIFEST %s" % absolute)
    print("MANIFEST SUMMARY focusables=%d pass=%d fail=%d tolerance=%.2f px checks=%d" % [
        covered, passed, covered - passed, TOLERANCE_PX, checks_run])
    check(covered >= 60, "the manifest covers the full focusable surface (%d controls)" % covered)

    if is_instance_valid(home):
        home.queue_free()
    await process_frame
    if is_instance_valid(host):
        host.queue_free()
    await process_frame
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: focus traversal manifest (every focusable control has an authored hand target)")
    quit(0)

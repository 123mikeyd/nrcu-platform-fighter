extends SceneTree
# WP-F focused check: the canonical secondary surfaces (Doc 07 §3-§21).
#
# How to Play: BASICS/FIGHTERS sections exist, the input-profile switch swaps
# the DISPLAYED binding labels without changing the section or the instruction
# text, Back is visible in the top-right, instruction rows are typography and
# never enter the focus chain, and the legacy demo_style CONTROLS/MOVES
# wall-of-text page is not mounted anywhere.
#
# Quit: the home.gd in-place modal is asserted as-is (Main stays mounted, one
# modal state, default focus STAY, Esc dismisses) — WP-F does not rebuild it.
#
# Story: the briefing scene replaces the inline story panel, presents the
# enemy + objective + fighter-selection state with stable fighter ids, only
# arms START for a valid fighter, routes Back to the Main menu, and no
# player-facing string carries MATCH SETUP vocabulary.
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func settle(frames: int) -> void:
    for i in frames:
        await process_frame

func key_event(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event

func visible_strings(node: Node) -> Array:
    var out: Array = []
    for child in node.find_children("*", "", true, false):
        if child is Label:
            out.append(str((child as Label).text))
        elif child is Button:
            out.append(str((child as Button).text))
    return out

func run() -> void:
    root.size = Vector2i(1280, 720)
    await _how_to_play_surface()
    await _help_route_and_quit_modal()
    await _story_briefing_surface()
    await _story_result_surface()
    await _story_route()
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS secondary surfaces (Doc 07): structured How to Play manual, in-place Quit modal, Story encounter briefing")
    quit(0)

# --- A. How to Play (Doc 07 §3-§8) -----------------------------------------
func _how_to_play_surface() -> void:
    var htp = load("res://scenes/how_to_play.tscn").instantiate()
    root.add_child(htp)
    await settle(8)
    check(htp is Control, "How to Play mounts as a screen")
    check(htp.section_ids() == ["BASICS", "FIGHTERS"], "two top-level sections BASICS and FIGHTERS")
    check(htp.section() == "BASICS", "BASICS is the active section on entry")
    var basics_tab: Control = htp.find_child("SectionBasics", true, false)
    var fighters_tab: Control = htp.find_child("SectionFighters", true, false)
    check(basics_tab != null and fighters_tab != null, "both section tabs exist as controls")
    check((basics_tab.get_node("Rail") as Panel).visible and not (fighters_tab.get_node("Rail") as Panel).visible,
        "exactly one tab owns the active rail")

    # BASICS subsections and their structured rows.
    check(htp.subsection_titles().size() == 4, "exactly the four locked BASICS subsections")
    for title in ["MOVEMENT", "ATTACK", "DEFENSE", "PLATFORMS"]:
        check(htp.subsection_titles().has(title), "BASICS shows the %s subsection" % title)
    var basics_rows: Array = htp.basics_rows()
    check(basics_rows.size() == 8, "BASICS exposes the locked action rows")
    for row in basics_rows:
        check(row.focus_mode == Control.FOCUS_NONE, "instruction rows are never focusable")
        check(row.get_node_or_null("ActionName") != null and row.get_node_or_null("Input") != null and row.get_node_or_null("Note") != null,
            "each row carries action name + input + one sentence")
        var boxed := false
        for child in row.get_children():
            if child is Panel:
                boxed = true
        check(not boxed, "instruction rows are typography, never boxed")
    var focusable_content := 0
    for column_name in ["BasicsLeft", "BasicsRight"]:
        for node in htp.find_child(column_name, true, false).find_children("*", "", true, false):
            if node is Control and (node as Control).focus_mode != Control.FOCUS_NONE:
                focusable_content += 1
    check(focusable_content == 0, "non-interactive instruction content is not in the focus chain")

    # Input-profile selector swaps displayed bindings only.
    var note_label: Label = basics_rows[0].get_node("Note")
    var note_before := note_label.text
    check(htp.profile() == "P1_KEYBOARD", "P1 keyboard is the default input profile")
    check(htp.binding_for("basic") == "F" and htp.binding_for("move") == "WASD",
        "the P1 keyboard profile shows the P1 bindings")
    htp.set_profile("P2_KEYBOARD")
    await settle(2)
    check(htp.binding_for("basic") == "K" and htp.binding_for("move") == "ARROWS" and htp.binding_for("shield") == "O",
        "the input-profile switch changes the displayed binding data")
    check(htp.section() == "BASICS", "the input-profile switch does not change the section")
    check(note_label.text == note_before, "the input-profile switch never changes the instructional content")
    htp.set_profile("CONTROLLER")
    await settle(2)
    check(htp.binding_for("basic") == "X" and htp.binding_for("shield") == "SHOULDER" and htp.binding_for("jump") == "A",
        "the CONTROLLER profile shows the pad bindings")
    check(htp.profile_ids() == ["P1_KEYBOARD", "P2_KEYBOARD", "CONTROLLER"], "the three locked profiles exist")
    htp.set_profile("P1_KEYBOARD")

    # Back is visible top-right; interactive controls expose authored anchors.
    var back: Button = htp.back_button()
    check(back != null and str(back.name) == "HelpBack", "Back keeps the HelpBack route node")
    check(back.visible, "Back is visible on How to Play")
    var back_rect := back.get_global_rect()
    check(back_rect.position.x >= 1000.0 and back_rect.position.x <= 1100.0 and back_rect.position.y <= 96.0,
        "Back sits in the top-right of the reference frame")
    check(back.get_node_or_null("CursorAnchor") != null and back.get_node("CursorAnchor").has_method("anchor_position"),
        "Back exposes an authored CursorAnchor")
    check(basics_tab.get_node_or_null("Anchor") != null and fighters_tab.get_node_or_null("Anchor") != null,
        "both section tabs expose authored CursorAnchors")
    var profile_control: Control = htp.find_child("ProfileControl", true, false)
    for anchor_name in ["AnchorP1", "AnchorP2", "AnchorCtrl"]:
        check(profile_control.get_node_or_null(anchor_name) != null, "profile segment exposes %s" % anchor_name)

    # Focus chain follows the visual order: tabs -> profile -> Back.
    var chain: Array = htp.focus_chain()
    check(chain.size() >= 5, "the focus chain covers tabs, the input profile and Back")
    check(chain[0] == basics_tab.get_node("HitArea"), "focus starts on the section tabs")
    check(chain[chain.size() - 1] == back, "Back closes the focus order")
    for control in chain:
        check((control as Control).focus_mode != Control.FOCUS_NONE, "every focus-chain entry is interactive")

    # FIGHTERS: roster strip + selected presentation + move list.
    htp.show_section("FIGHTERS")
    await settle(4)
    check(htp.section() == "FIGHTERS", "FIGHTERS activates")
    check((fighters_tab.get_node("Rail") as Panel).visible and not (basics_tab.get_node("Rail") as Panel).visible,
        "the active tab rail follows the section")
    check(htp.find_child("FightersBody", true, false).visible and not htp.find_child("BasicsBody", true, false).visible,
        "one body zone is visible at a time")
    var Roster = load("res://scripts/roster.gd")
    check(htp.roster_ids() == Roster.ids(), "the roster strip carries the full roster")
    var tiles: Array = htp.roster_tiles()
    check(tiles.size() == Roster.ids().size(), "one compact tile per roster fighter")
    for i in tiles.size():
        check(str(tiles[i].fighter_id) == str(Roster.ids()[i]), "tile %d keeps its stable fighter id" % i)
        check(tiles[i].portrait_texture() != null, "tile %d shows its portrait" % i)
        check((tiles[i] as Control).focus_mode != Control.FOCUS_NONE, "tile %d is keyboard reachable" % i)
        check(tiles[i].anchor() != null, "tile %d exposes its CursorAnchor" % i)
    htp.select_fighter("ggb")
    await settle(4)
    check(htp.selected_fighter_id() == "ggb", "fighter selection uses stable ids")
    check(tiles[2].is_candidate(), "the selected tile carries the candidate state")
    check(htp.render_view() != null and htp.render_view().subjects() == ["ggb"],
        "the selected fighter is rendered in the moderate presentation region")
    var move_rows: Array = []
    var move_names: Array = []
    for row in htp.instruction_rows():
        if row.get_node_or_null("MoveName") != null:
            move_rows.append(row)
            move_names.append(str((row.get_node("MoveName") as Label).text))
    check(move_rows.size() >= 2, "the selected fighter gets a short move list")
    check(move_names.has("STICKY GOO"), "GGB's real moves are shown, not lore text")
    for row in move_rows:
        check(row.focus_mode == Control.FOCUS_NONE, "move rows are not focusable")
        check(str((row.get_node("MoveInput") as Label).text) != "", "move rows carry compact input notation")

    # Legacy wall-of-text is nowhere on this screen.
    check(htp.find_child("HelpPage", true, false) == null, "the structured manual has no legacy HelpPage node")
    var wall := false
    for text in visible_strings(htp):
        if text.find("Esc: match setup") != -1 or text.find("Connect controllers before launching") != -1:
            wall = true
    check(not wall, "no legacy CONTROLS/MOVES wall-of-text is mounted")
    check(FileAccess.get_file_as_string("res://scripts/frontend/how_to_play.gd").find("res://scripts/demo_style.gd") == -1,
        "the manual never mounts the legacy demo_style page")

    htp.queue_free()
    await process_frame

# --- B. HELP route + Quit modal (Doc 07 §9-§10; home.gd API) ----------------
func _help_route_and_quit_modal() -> void:
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    await settle(30)
    var rows: Array = home.menu_rows()
    (rows[2].get_node("HitArea") as Button).pressed.emit()
    await settle(12)
    check(home.state == "help", "HOW TO PLAY opens the subpage")
    var page = home.find_child("HowToPlay", true, false)
    check(page != null, "the mounted help page is the structured How to Play screen")
    check(home.find_child("HelpPage", true, false) == null, "the legacy wall-of-text help page is not mounted")
    check(FileAccess.get_file_as_string("res://scripts/home.gd").find("Style.help(") == -1,
        "home.gd no longer routes HOW TO PLAY to demo_style.help()")
    if page != null:
        check(page.section_ids() == ["BASICS", "FIGHTERS"], "the mounted manual keeps its two sections")
        check(page.binding_for("basic") == "F", "the mounted manual shows the P1 bindings")
    var wall := false
    for text in visible_strings(home):
        if text.find("Esc: match setup") != -1 or text.find("Connect controllers before launching") != -1:
            wall = true
    check(not wall, "no legacy CONTROLS/MOVES wall-of-text is mounted on Main")
    var back: Button = home.find_child("HelpBack", true, false)
    check(back != null and back.visible, "the manual keeps the visible Back route")
    var hand = _hand()
    check(hand != null and not hand.is_carrying() and int(hand.visual) == 0,
        "How to Play uses the regular cursor, never a token carry")
    back.pressed.emit()
    await settle(12)
    check(home.state == "home" and home.find_child("HowToPlay", true, false) == null, "Back returns to Main")
    check(home.selected_index() == 2, "returning from How to Play keeps HOW TO PLAY selected")

    # Quit: existing in-place modal — asserted, not rebuilt.
    (rows[3].get_node("HitArea") as Button).pressed.emit()
    await settle(12)
    check(home.is_quit_modal_open() and home.state == "quit", "QUIT opens the confirmation layer, not a page")
    check(home.is_inside_tree() and home.find_child("Navigation", true, false).visible,
        "Main stays mounted behind the confirmation")
    var focus = home.get_viewport().gui_get_focus_owner()
    check(focus != null and str(focus.name) == "ActionStay", "the default modal focus is STAY")
    # WALK-UP (Doc 08 §2 public input): dismiss through a real ui_cancel event.
    Input.parse_input_event(key_event(KEY_ESCAPE))
    await settle(12)
    check(not home.is_quit_modal_open() and home.state == "home", "Esc dismisses the confirmation")
    home.get_window().close_requested.emit()
    await settle(12)
    check(home.is_quit_modal_open(), "the OS close request takes the same confirmation path")
    var quit_conns := (home.find_child("ActionQuit", true, false) as Button).pressed.get_connections()
    check(quit_conns.size() > 0, "the modal QUIT action stays wired to the process exit")
    (home.find_child("ActionStay", true, false) as Button).pressed.emit()
    await settle(12)
    check(not home.is_quit_modal_open(), "STAY closes the confirmation")

    home.queue_free()
    await process_frame

# --- C. Story briefing scene (Doc 07 §11-§16) -------------------------------
func _story_briefing_surface() -> void:
    var story = load("res://scenes/story_briefing.tscn").instantiate()
    root.add_child(story)
    await settle(6)
    story.build()
    story.open("turbofit")
    await settle(8)
    check(story.enemy_render_resolved() or story.enemy_nameplate() != null,
        "the enemy presentation resolves, or falls back to a nameplate")
    print("ENEMY_PRESENTATION=", "render" if story.enemy_render_resolved() else "nameplate")
    var strings: Array = visible_strings(story)
    var joined := " ".join(strings)
    check(joined.find("BOBO") != -1 and joined.find("400 HP") != -1, "the enemy is identified as BOBO with 400 HP")
    check(joined.find("ENCOUNTER 01") != -1, "the header names ENCOUNTER 01")
    check(str(story.objective_label().text).find("Bobo") != -1, "an objective names the enemy")
    check(joined.find("3 stocks") != -1 and joined.find("does not attack") != -1, "the rules state the stock count and Bobo's behavior")
    var Roster = load("res://scripts/roster.gd")
    var expected: Array = Roster.ids()
    expected.erase("ice_mage")
    check(story.roster_ids() == expected, "the briefing uses the story playable ids")
    check(story.selected_fighter_id() == "turbofit", "the briefing opens on the story default fighter")
    check(story.roster_tiles().is_empty() and story.find_child("RosterStrip", true, false) == null,
        "the Encounter Briefing embeds no roster strip (Doc 05 §108)")
    story.select_fighter("ggb")
    await settle(4)
    check(story.selected_fighter_id() == "ggb" and story.render_view().subjects() == ["ggb"],
        "selection drives the presented fighter render")
    story.set_selected_id("")
    check(story.action_button().disabled, "START is inert without a selected fighter")
    story.set_selected_id("not_a_fighter")
    check(story.action_button().disabled and story.selected_fighter_id() == "",
        "unknown fighter ids never arm START")
    story.select_fighter("teknium")
    check(not story.action_button().disabled and story.selected_fighter_id() == "teknium",
        "a valid fighter arms START")
    story.action_button().grab_focus()
    await settle(3)
    var top_rule: Control = story.find_child("ActionTopRule", true, false)
    check(top_rule != null and top_rule.visible, "the rail action carries a structural focus cue, not color alone")
    var events_node = root.get_node("FrontendEvents")
    var seen: Array = []
    events_node.confirm.connect(func(id: String) -> void: seen.append("confirm:" + id))
    events_node.back.connect(func(id: String) -> void: seen.append("back:" + id))
    story.action_button().pressed.emit()
    await settle(2)
    check(seen.has("confirm:story_start"), "START reports an accepted semantic confirm")
    story.back_button().pressed.emit()
    await settle(2)
    check(seen.has("back:story"), "Back reports the semantic back event")
    var offending := false
    for text in visible_strings(story):
        if text.to_upper().find("MATCH SETUP") != -1:
            offending = true
    check(not offending and story.back_button().text == "BACK", "no MATCH SETUP vocabulary on the briefing; Back is the player route")
    story.show_result(true)
    await settle(4)
    check(story.action_button().text == "REPLAY" and story.back_button().text == "BACK",
        "the win result offers replay while the header action stays BACK")
    story.show_result(false)
    await settle(2)
    check(story.action_button().text == "RETRY" and story.back_button().text == "BACK",
        "the loss result offers retry while the header action stays BACK")
    var exited := [false]
    story.exit_finished.connect(func() -> void: exited[0] = true)
    story.play_exit()
    check(story.is_exiting(), "the Back path runs the briefing exit animation")
    await settle(30)
    check(exited[0], "the exit finishes so the host routes Story -> Main")
    story.queue_free()
    await process_frame

# --- C2. Story Result surface (Doc 05 §136-159) ------------------------------
func _story_result_surface() -> void:
    var result = load("res://scenes/story_result.tscn").instantiate()
    root.add_child(result)
    await settle(8)
    result.present(true, "turbofit")
    await settle(4)
    check(str(result.title_label().text) == "YOU'RE PRETTY COOL" and str(result.detail_label().text) == "BOBO DEFEATED",
        "the win copy is the package wording")
    check(str(result.action_button().text) == "REPLAY" and str(result.menu_button().text) == "MAIN MENU",
        "the win action group offers REPLAY and MAIN MENU")
    check(result.change_fighter_button().visible, "the result offers CHANGE FIGHTER")
    check(result.selected_fighter_id() == "turbofit" and result.render_view().subjects() == ["turbofit"],
        "the result keeps the played fighter present")
    result.present(false, "turbofit")
    await settle(2)
    check(str(result.title_label().text) == "TRY AGAIN"
        and str(result.detail_label().text) == "Out of stocks. Bobo is still standing."
        and str(result.action_button().text) == "RETRY",
        "the loss copy is the package wording with RETRY")
    result.queue_free()
    await process_frame

# --- D. Story route through the MatchFlow frontend (WP-0 step 4) ------------
func _story_route() -> void:
    var story = load("res://tests/fixtures/story_route.gd").new()
    var host = await story.enter(self)
    check(host.entry_mode() == "story" and host.active_surface() == "story_select",
        "the Story route opens in the MatchFlow host on the Fighter Select")
    var select = host.story_select()
    check(select != null and select.visible, "the host presents the Story Fighter Select")
    check(select.roster_ids() == story_ids(), "the Select uses the encounter's playable ids")
    var tiles: Array = select.roster_tiles()
    check(tiles.size() == story_ids().size(), "one selection tile per playable fighter")
    check(select.selected_fighter_id() == "turbofit", "the Select opens on the default fighter")
    check(await story.open_briefing(self, host), "Continue reaches the Encounter Briefing")
    var briefing = host.story_briefing()
    check(briefing != null and briefing.visible, "the host presents the Encounter Briefing")
    check(briefing.get_parent().get_parent() == host, "the briefing is hosted by MatchFlow, outside gameplay")
    check(str(briefing.action_button().text) == "START ENCOUNTER", "the briefing exposes the screen-level START ENCOUNTER action")
    check(str(briefing.back_button().text) == "BACK" and briefing.back_button().visible, "Back stays visible on the briefing")
    check(briefing.selected_fighter_id() == "turbofit", "the briefing presents the committed fighter")
    check(briefing.find_child("RosterStrip", true, false) == null,
        "the briefing scene carries no roster strip of its own (Doc 05 §108)")
    check(briefing.roster_tiles() == select.roster_tiles(),
        "pre-WP-4 roster probes read the shared Select (no second selector)")
    var offending := false
    for text in visible_strings(briefing):
        if text.to_upper().find("MATCH SETUP") != -1:
            offending = true
    check(not offending, "no MATCH SETUP vocabulary is player-facing in the briefing")
    # Back: Briefing -> Story Fighter Select -> Main (Doc 01 §9)
    briefing.back_button().pressed.emit()
    await settle(2)
    check(briefing.is_exiting(), "Back runs the briefing exit instead of a debug route")
    var back_to_select: bool = await story.wait_for(self, func() -> bool:
        return host.active_surface() == "story_select" and select.visible, 240)
    check(back_to_select, "the Briefing Back restores the Story Fighter Select")
    select.back_button().pressed.emit()
    var home_scene = await story.wait_for_scene(self, "home.tscn")
    check(home_scene != null, "the Select Back returns to the Main route")
    check(root.get_node_or_null("MainArena") == null, "no arena was constructed for a Back return")
    if home_scene != null:
        home_scene.queue_free()
    await story.free_hosts(self)
    # START: gameplay launches from the frozen story config
    var launch_host = await story.enter(self)
    var arena = await story.start_encounter(self, launch_host)
    check(arena != null and arena.story_state == "playing", "START launches the encounter from the story config")
    if arena == null:
        return
    var playable: Array = []
    for id in launch_host_story_ids():
        playable.append(str(id))
    check(arena.fighters.size() == 2 and arena.player_one.character_id in playable,
        "the launch uses a valid playable fighter id")
    check(arena.find_child("StoryBriefing", true, false) == null,
        "gameplay hosts no story panel of its own (frontend-owned since step 4)")
    check(arena.setup == null, "no debug setup screen is constructed for a story launch (Doc 02 §9)")
    var hud = arena.find_child("MatchControls", true, false)
    check(hud != null and str(hud.text).to_upper().find("MATCH SETUP") == -1,
        "the story HUD keeps player-facing vocabulary")
    arena.queue_free()
    await story.free_hosts(self)

func launch_host_story_ids() -> Array:
    return load("res://scripts/catalogs/story_encounter_catalog.gd").allowed_fighter_ids("story_01")

func story_ids() -> Array:
    var ids: Array = load("res://scripts/roster.gd").ids()
    ids.erase("ice_mage")
    return ids

func _hand():
    var cursor = root.get_node_or_null("Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand

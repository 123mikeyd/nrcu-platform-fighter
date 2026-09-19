extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok, note):
    checks += 1
    print(("PASS " if ok else "FAIL ") + note)
    if not ok: failures += 1
func frames(n):
    for i in n:
        await physics_frame
        await process_frame
func run():
    var flow = load("res://scenes/match_flow.tscn").instantiate()
    root.add_child(flow); current_scene = flow; await frames(3)
    flow.open_story(); await frames(60)
    flow._on_story_select_continue("teknium"); await frames(60)
    flow._on_story_start(); await frames(190)
    var arena = current_scene
    check(arena.has_method("start_match"), "ordinary Story Start reaches arena")
    check(arena.player_two.character_id == "bobo", "first encounter Bobo")
    # Forced blast-zone outcomes exercise production lifecycle, not combat skill.
    arena.player_two.receive_hit(1000, Vector3.RIGHT, 0)
    await frames(90)
    flow = current_scene
    check(flow.active_surface() == "story_result", "first win returns to result")
    check(flow.story_result().action_button().text == "NEXT ENCOUNTER", "first win is stage complete")
    flow.story_result().action_button().pressed.emit(); await frames(90)
    check(flow.active_surface() == "story_briefing", "next requires separate briefing Start")
    check(flow.story_selection_id() == "teknium", "hero retained")
    check(flow.story_encounter_id() == "story_02", "second encounter selected")
    check(flow.story_briefing().get_node("ReferenceFrame/Header/EncounterLabel").text == "ENCOUNTER 02", "second briefing label matches encounter")
    flow.story_briefing().action_button().pressed.emit(); await frames(190)
    arena = current_scene
    check(arena.player_two.character_id == "ice_mage", "second encounter Ice Mage")
    check(arena.player_two.bot_difficulty == "normal", "Normal bot")
    check(arena.player_one.stocks == 3 and arena.player_two.stocks == 3, "fresh stocks")
    check(not arena.bobo_health_bar.visible, "stock opponent has no Bobo HP bar")
    arena.player_one.stocks = 1; arena.player_one._handle_blast_zone(); await frames(90)
    flow = current_scene
    check(flow.story_result().action_button().text == "RETRY", "second encounter retry")
    flow.story_result().action_button().pressed.emit(); await frames(190)
    arena = current_scene
    check(arena.player_two.character_id == "ice_mage", "retry preserves current encounter")
    arena.player_two.stocks = 1; arena.player_two._handle_blast_zone(); await frames(90)
    flow = current_scene
    check(flow.story_result().action_button().text == "RESTART RUN", "final result completes slice")
    check(flow.story_result().title_label().text == "your pretty cool", "approved literal victory text")
    var key = InputEventKey.new(); key.keycode = KEY_R; key.pressed = true
    Input.parse_input_event(key); Input.flush_buffered_events(); await frames(90)
    check(flow.active_surface() == "story_briefing" and flow.story_encounter_id() == "story_01", "R restarts via first briefing")
    print("RELEASE_STORY_COMPLETE checks=%d fails=%d" % [checks, failures])
    quit(1 if failures else 0)

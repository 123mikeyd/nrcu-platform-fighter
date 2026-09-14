extends SceneTree
# Story result / lifecycle contract — MIGRATED for WP-0 step 4: the encounter is
# launched by the MatchFlow host from a story MatchLaunchConfig, gameplay keeps
# the Story state machine and its cleanup, and the Story Result (shipped wording
# + REPLAY/RETRY + MAIN MENU) is presented by the host's briefing surface (the
# standalone Story Result redesign is WP-5).
var failures := 0
var story

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    return event

func run():
    root.size = Vector2i(1280, 720)
    story = load("res://tests/fixtures/story_route.gd").new()
    var host = await story.enter(self)
    var launch_host_id: int = host.get_instance_id()
    var arena = await story.start_encounter(self, host)
    if arena == null:
        check(false, "the encounter launches through the MatchFlow story route")
        quit(1)
        return
    # Status/cleanup fixtures start after Go, not during Ready.
    story.run_ready(arena)
    var hero = arena.player_one
    var mage = arena.player_two
    for f in arena.fighters: f.set_physics_process(false)
    mage.receive_hit(150, Vector3.RIGHT, 4)
    check(not arena.match_over and arena.story_state == "playing" and mage.health == 250,
        "first stock loss is not completion")
    mage.receive_hit(150, Vector3.RIGHT, 4)
    check(not arena.match_over and mage.health == 100, "second stock loss continues encounter")
    check(mage.apply_freeze(hero), "Bobo receives existing finite freeze")
    var bolt = load("res://scripts/projectile.gd").new()
    bolt.source = hero
    bolt.sound_wave = true
    arena.add_child(bolt)
    mage.receive_hit(150, Vector3.RIGHT, 4)
    check(arena.match_over and arena.story_state == "complete", "final elimination completes the one-stage story")
    # Same-frame resolution: cleanup, freeze release and control lock (the arena
    # is replaced by the frontend Story Result at the end of this frame).
    check(not arena.winner_label.visible, "generic freeplay winner text does not leak")
    check(hero.freeze_remaining == 0 and not hero.get_node("FrozenShell").visible,
        "completion clears freeze even with physics disabled")
    check(bolt.is_queued_for_deletion(), "completion immediately queues every projectile for cleanup")
    for f in arena.fighters: check(not f.controls_enabled, "result blocks combat")
    check(arena.find_child("StoryBriefing", true, false) == null,
        "gameplay no longer hosts the story panel (frontend-owned since step 4)")
    arena._reset_match()
    check(arena.match_over and arena.story_state == "complete",
        "R never restarts a resolved encounter in place (REPLAY owns it)")
    # --- the frontend Story Result ---
    var result_host = await story.wait_for_flow(self, launch_host_id)
    check(result_host != null, "the completed encounter returns to the MatchFlow host")
    check(not is_instance_valid(arena), "the completed gameplay is torn down before the Story Result")
    if result_host == null:
        quit(1)
        return
    var cursor_layer = root.get_node_or_null("Cursor")
    check(cursor_layer != null and cursor_layer.hand != null and not cursor_layer.hand.is_carrying(),
        "results cursor does not carry a token")
    var briefing = result_host.story_briefing()
    var token_leak := false
    for node in briefing.find_children("*", "", true, false):
        if not (node is CanvasItem):
            continue
        var named := str(node.name)
        if (named == "StoryToken" or named.begins_with("PlayerToken")) and (node as CanvasItem).is_visible_in_tree():
            token_leak = true
    check(not token_leak, "no StoryToken/PlayerToken state leaks into the Story Result")
    check(briefing.visible and str(briefing.title_label().text) == "your pretty cool",
        "victory title is the exact requested lowercase string")
    check(str(briefing.action_button().text) == "REPLAY" and briefing.back_button().visible,
        "victory offers replay and back")
    # --- REPLAY: a fresh encounter ---
    var replay = await story.start_encounter(self, result_host)
    check(replay != null and replay.story_state == "playing" and not replay.match_over and replay.fighters.size() == 2,
        "Replay launches a fresh single encounter")
    check(get_nodes_in_group("fighters").size() == 2, "Replay removes old fighters")
    if replay != null:
        for f in replay.fighters:
            f.set_physics_process(false)
            check(f.stocks == 3 and f.damage_percent == 0 and f.freeze_remaining == 0 and f.freeze_immunity == 0 and f.ice_cast_cooldown == 0,
                "Replay resets stocks, damage and freeze lifecycle")
        # --- loss -> RETRY ---
        story.run_ready(replay)
        for i in 3: replay.player_one._handle_blast_zone()
        check(replay.story_state == "lost" and replay.match_over, "human stock exhaustion shows loss")
        var loss_host = await story.wait_for_flow(self, result_host.get_instance_id())
        check(loss_host != null, "the loss returns to the Story Result host")
        if loss_host != null:
            check(str(loss_host.story_briefing().title_label().text) != "your pretty cool"
                and str(loss_host.story_briefing().action_button().text) == "RETRY", "loss offers Retry, not victory")
            var retry = await story.start_encounter(self, loss_host)
            check(retry != null and retry.story_state == "playing"
                and retry.player_one.stocks == 3 and retry.player_two.stocks == 3, "Retry starts a fresh duel")
            if retry != null:
                # --- Esc during the encounter: the player route Story -> Main ---
                story.run_ready(retry)
                var hero2 = retry.player_one
                retry.player_two.apply_freeze(hero2)
                var bolt2 = load("res://scripts/projectile.gd").new()
                bolt2.source = retry.player_two
                bolt2.freeze_bolt = true
                retry.add_child(bolt2)
                retry._unhandled_key_input(escape())
                check(retry.setup.visible and retry.story_state == "" and not retry.match_over,
                    "Esc exits the encounter to the gameplay hub without an active story state")
                check(hero2.freeze_remaining == 0 and hero2.freeze_immunity == 0 and not hero2.controls_enabled,
                    "exit clears freeze and stops the human")
                check(bolt2.is_queued_for_deletion(), "exit clears projectiles")
                var home_scene = await story.wait_for_scene(self, "home.tscn")
                check(home_scene != null, "Esc reaches the Main route")
                if home_scene != null:
                    home_scene.queue_free()
                await process_frame
    await story.free_hosts(self)

    # --- freeplay is unaffected: Teams and the original winner flow ---
    var direct = load("res://scenes/main.tscn").instantiate()
    root.add_child(direct)
    await process_frame
    direct.setup.mode.select(1)
    direct.setup._start()
    check(direct.fighters.size() == 4 and direct.teams_enabled and direct.story_state == "",
        "freeplay Teams survives the story exit")
    for f in direct.fighters: f.set_physics_process(false)
    for i in [0, 2]:
        for stock in 3: direct.fighters[i]._handle_blast_zone()
    check(direct.winner_label.visible and "TEAM B WINS!" in direct.winner_label.text
        and direct.find_child("StoryBriefing", true, false) == null, "freeplay uses the original winner flow")
    direct.queue_free()
    await story.free_hosts(self)
    await process_frame
    if failures == 0: print("PASS: story lifecycle via MatchFlow (hit progression, exact victory, cleanup, Replay, loss/Retry, Esc, freeplay teams/winner)")
    quit(1 if failures else 0)

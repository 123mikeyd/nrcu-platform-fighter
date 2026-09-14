extends SceneTree
# Story combat contract — MIGRATED for WP-0 step 4: the encounter is launched by
# the MatchFlow host from a story MatchLaunchConfig; gameplay keeps the combat
# and the Story state machine, and the Story Result (with REPLAY/RETRY) is the
# host's briefing surface. Marker line BOBO_INPUT is the suite's success
# contract.
var failures := 0
var story

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func key(code: int, down: bool):
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func frames(count: int):
    for i in count: await physics_frame
    await process_frame

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
        check(false, "the story encounter launches through MatchFlow")
        print("BOBO_INPUT failures=", failures)
        quit(1)
        return
    await frames(120)
    var hero = arena.player_one
    var bobo = arena.player_two
    check(hero.damage_percent == 0 and bobo.health == 400, "passive Bobo never attacks")
    var x: float = hero.position.x
    key(KEY_D,true)
    await frames(12)
    key(KEY_D,false)
    check(hero.position.x > x + 0.2, "human can freely move")
    hero.reset_fighter(Vector3(0,0.1,0),true)
    bobo.reset_fighter(Vector3(2,0.1,0),true)
    await frames(30)
    hero.facing = 1
    key(KEY_D,true)
    key(KEY_G,true)
    await frames(2)
    key(KEY_D,false)
    key(KEY_G,false)
    await frames(45)
    check(bobo.health < 400 and bobo.reaction_serial > 0, "real P1 projectile consumes HP and starts native reaction")
    var hp: float = bobo.health
    await frames(50)
    check(bobo.health == hp, "one projectile cannot consume HP twice")
    bobo.receive_hit(5,Vector3.RIGHT,100)
    bobo._handle_blast_zone()
    check(not arena.match_over and bobo.health == hp-5, "knockoff never bypasses HP")
    bobo.receive_hit(1000,Vector3.RIGHT,100)
    check(arena.story_state == "complete", "real lethal damage completes Story")
    # --- the Story Result is the host's surface (REPLAY / RETRY) ---
    var result_host = await story.wait_for_flow(self, launch_host_id)
    check(result_host != null, "the completed encounter returns to the MatchFlow host")
    if result_host != null:
        check(result_host.entry_mode() == "story" and result_host.active_surface() == "story_result",
            "the Story outcome opens the Story Result surface — never the multiplayer Results (PostMatch)")
        check(not result_host.is_surface_presented("postmatch"),
            "no multiplayer Results surface is presented for a Story outcome")
    if result_host == null:
        print("BOBO_INPUT failures=", failures)
        quit(1)
        return
    # The launch handshake frees this host (Doc 02 §5/§6): capture its identity
    # while it is alive — never read it off the freed node (dangling access).
    var result_host_id: int = result_host.get_instance_id()
    check(str(result_host.story_result().title_label().text) == "YOU'RE PRETTY COOL", "the package victory wording is presented")
    check(str(result_host.story_result().action_button().text) == "REPLAY", "the victory offers REPLAY")
    var replay = await story.start_encounter(self, result_host)
    check(replay != null and replay.story_state == "playing" and replay.player_two.health == 400,
        "Replay launches a fresh encounter and restores HP")
    if replay == null:
        print("BOBO_INPUT failures=", failures)
        quit(1)
        return
    await frames(120)
    for i in 3: replay.player_one._handle_blast_zone()
    check(replay.story_state == "lost", "player stock loss remains real")
    var loss_host = await story.wait_for_flow(self, result_host_id)
    check(loss_host != null, "the loss returns to the Story Result host")
    if loss_host != null:
        check(str(loss_host.story_result().action_button().text) == "RETRY", "the loss offers RETRY")
        var retry = await story.start_encounter(self, loss_host)
        check(retry != null and retry.player_two.health == 400 and retry.player_one.stocks == 3,
            "Retry restores both fighters")
        if retry != null:
            # Esc: the player route Story -> Main (no MATCH SETUP vocabulary).
            await frames(20)
            var live = root.get_node_or_null("MainArena")
            check(live == retry and is_instance_valid(retry) and retry.is_inside_tree(),
                "the retried encounter is the live arena before Esc")
            if live == retry and is_instance_valid(retry) and retry.is_inside_tree():
                retry._unhandled_key_input(escape())
                check(not retry.bobo_health_bar.visible, "Back hides the encounter-only HP bar")
                var home_scene = await story.wait_for_scene(self, "home.tscn")
                check(home_scene != null, "Esc leaves the encounter for the Main route")
                if home_scene != null:
                    home_scene.queue_free()
                await process_frame
    await story.free_hosts(self)
    await process_frame
    print("BOBO_INPUT failures=", failures)
    quit(1 if failures else 0)

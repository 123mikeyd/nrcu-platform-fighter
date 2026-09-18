extends SceneTree
var failures := 0
func check(ok: bool, message: String):
    if not ok: failures += 1; print("FAIL: "+message)
func _initialize(): call_deferred("run")
func key(code: int, pressed: bool):
    var event := InputEventKey.new()
    event.keycode = code; event.pressed = pressed
    Input.parse_input_event(event); Input.flush_buffered_events()
func run():
    var game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game); await process_frame
    if not game.has_method("_begin_ready"):
        print("FAIL: Ready Go lifecycle missing"); quit(1); return
    game.setup._start()
    check(game.ready_remaining > 0, "Start enters Ready")
    for f in game.fighters: check(not f.controls_enabled, "Ready gates humans and bots")
    key(KEY_F,true); key(KEY_G,true); key(KEY_SPACE,true)
    for i in 110: await physics_frame
    check(game.ready_remaining == 0, "bounded countdown ends")
    check(game.player_one.controls_enabled and game.player_one.attack_cooldown == 0 and not game.player_one.charging, "held start inputs do not auto attack")
    check(game.player_one.global_position.y < 0.3, "held jump does not auto jump")
    key(KEY_F,false); key(KEY_G,false); key(KEY_SPACE,false)
    game.show_setup()
    check(game.ready_remaining == 0 and not game.ready_label.visible, "setup cancels countdown")
    game.setup._start(); game.show_setup()
    for i in 100: await physics_frame
    for f in game.fighters: check(not f.controls_enabled, "cancelled countdown cannot unlock setup")
    game.setup._start()
    for f in game.fighters: f.set_physics_process(false)
    for i in range(1,game.fighters.size()): game.fighters[i].stocks = 0
    game._on_fighter_eliminated(game.fighters[1])
    check(game.ready_remaining == 0, "winner hides Ready")
    # WP-0 step 5: the completed match hands the payload to the MatchFlow host,
    # which owns the Results surface and the REMATCH action (the arena keeps no
    # Results screen of its own).
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var post = await vs.wait_for_post_match(self)
    check(post != null, "the completed match RETURNs to the PostMatch surface")
    if post != null:
        check(post.post_match_result() != null, "the payload reaches the PostMatch surface")
        post.post_match().result_screen.finish_reveal()
        var rematch = post.post_match().result_screen.find_child("Rematch", true, false)
        check(rematch != null and rematch.visible, "Results offers Rematch")
        rematch.pressed.emit()
        var arena2: Node = post.gameplay_node()
        var relaunched := false
        for i in 240:
            await process_frame
            if arena2 != null and is_instance_valid(arena2) and arena2.ready_remaining > 0 and not is_instance_valid(post):
                relaunched = true
                break
        check(relaunched, "Rematch LAUNCHes a fresh match with the same countdown")
        if relaunched:
            check(not arena2.match_over and arena2.fighters.size() == game.fighters.size(),
                "the rematch rebuilds the preserved setup")
        await vs.free_arenas(self)
    # WP-0 step 5: free_arenas already tore the manually mounted arena down — the
    # RETURN scene change does not own a test-mounted arena, so nothing here may
    # touch the freed original any more.
    if is_instance_valid(game):
        game.queue_free()
    await process_frame
    if failures == 0: print("PASS Ready Go, held input, cancellation, winner and rematch")
    quit(1 if failures else 0)

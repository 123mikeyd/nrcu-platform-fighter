extends SceneTree
# Bobo encounter HP contract — MIGRATED for WP-0 step 4: the encounter launches
# from MatchFlow's story route (briefing -> story MatchLaunchConfig) and the
# Story Result (REPLAY) is the host's surface. Marker line BOBO_STORY is the
# suite's success contract.
var failures := 0
var story

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ",message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
    root.size = Vector2i(1280, 720)
    story = load("res://tests/fixtures/story_route.gd").new()
    var host = await story.enter(self)
    var arena = await story.start_encounter(self, host)
    check(arena != null, "the encounter launches through the MatchFlow story route")
    if arena == null:
        print("BOBO_STORY failures=",failures)
        quit(1)
        return
    story.run_ready(arena)
    check(arena.player_two.character_id == "bobo", "first encounter is Bobo")
    check(arena.player_two.get("health") != null, "Bobo has genuine HP")
    var launch_host_id: int = host.get_instance_id()
    if arena.player_two.get("health") != null:
        var bobo = arena.player_two
        bobo.controls_enabled = true
        bobo.receive_hit(10, Vector3.RIGHT, 100)
        check(bobo.health == 390, "one hit consumes actual HP once")
        check(bobo.damage_percent == 0, "HP is not percent")
        bobo.receive_hit(1000, Vector3.RIGHT, 100)
        check(bobo.health == 0 and arena.story_state == "complete", "clamped lethal HP wins Story")
        bobo.receive_hit(10, Vector3.RIGHT, 10)
        check(bobo.health == 0, "defeated target rejects later damage")
        # --- REPLAY on the Story Result restores the encounter ---
        var result_host = await story.wait_for_flow(self, launch_host_id)
        check(result_host != null, "the completed encounter returns to the Story Result host")
        if result_host != null:
            check(str(result_host.story_result().action_button().text) == "REPLAY", "the victory offers REPLAY")
            var replay = await story.start_encounter(self, result_host)
            check(replay != null and replay.player_two.health == 400 and replay.story_state == "playing",
                "Replay restores full HP and restarts the Story state")
            if replay != null:
                arena.queue_free() if is_instance_valid(arena) else null
                replay.queue_free()
    await story.free_hosts(self)
    await process_frame
    print("BOBO_STORY failures=",failures)
    quit(1 if failures else 0)

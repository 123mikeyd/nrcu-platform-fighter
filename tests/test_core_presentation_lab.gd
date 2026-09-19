extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
    var lab = load("res://scenes/training_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_paused(true)
    lab.set_models_visible(true)
    check(lab.imported_visuals[0].has_method("present"), "training preview uses P3 presenter")
    if failures:
        lab.queue_free()
        await process_frame
        quit(1)
        return
    lab.overlay._process(0.0)
    check(lab.overlay.telemetry[0].text.contains("TEMP") and lab.overlay.telemetry[0].text.contains("Jump"), "preview persistently labels selected clip and temporary pose")
    lab.set_slot_mode(0, "Bot")
    lab.start_recording()
    var captured: Array = []
    for i in range(120):
        await physics_frame
        lab._simulate_tick()
        captured.append(sample(lab))
    lab.stop_recording()
    var v = lab.imported_visuals[0]
    var clock: float = v.animation_player.current_animation_position
    for i in range(3):
        await process_frame
        lab._physics_process(1.0 / 60)
    check(v.animation_player.current_animation_position == clock, "lab pause freezes real player")
    check(lab.start_replay(), "visual take replay starts")
    for i in range(120):
        await physics_frame
        lab.step_once()
        lab._physics_process(1.0 / 60)
        var actual := sample(lab)
        check(actual.slice(0, 5) == captured[i].slice(0, 5) and actual.slice(6) == captured[i].slice(6) and actual[5].is_equal_approx(captured[i][5]), "frame-step replay reproduces visual and physics sample %d" % i)
    lab.set_models_visible(false)
    lab.start_replay()
    for i in range(8):
        await physics_frame
        lab._simulate_tick()
    check(v.state.last_tick == lab.actors[0].runtime.tick, "hidden presenter remains on simulation clock")
    lab.start_replay()
    for visual in lab.imported_visuals: visual.free()
    for i in range(120):
        await physics_frame
        lab._simulate_tick()
        var actor = lab.actors[0]
        check([actor.position, actor.velocity, actor.runtime.states.locomotion] == captured[i].slice(0, 3), "removing render nodes preserves simulation %d" % i)
    lab.set_models_visible(true)
    check(is_instance_valid(lab.imported_visuals[0]), "preview recreates removed render node safely")
    lab.reset_lab()
    check(lab.imported_visuals[0].state.last_tick == 0, "reset resamples deterministic tick-zero pose")
    lab.queue_free()
    await process_frame
    if failures == 0: print("PASS: core presentation lab wiring, pause/step, replay, removal independence")
    quit(1 if failures else 0)
func sample(lab) -> Array:
    var actor = lab.actors[0]
    var v = lab.imported_visuals[0]
    var sk: Skeleton3D = v.skeleton
    return [actor.position, actor.velocity, actor.runtime.states.locomotion, v.state.output.duplicate(true), v.animation_player.current_animation_position, sk.get_bone_pose(sk.find_bone("LeftUpLeg")), v.position, v.model.rotation]

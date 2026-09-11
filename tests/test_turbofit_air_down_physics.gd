extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
var evidence: Array = []
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func key(code: int, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func step(count: int) -> void:
    for i in count:
        await physics_frame
        await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var floor := StaticBody3D.new()
    floor.collision_layer = 2
    floor.position.y = -0.5
    var col := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(30, 1, 4)
    col.shape = box
    floor.add_child(col)
    stage.add_child(floor)
    var f = F.new()
    f.character_id = "turbofit"
    stage.add_child(f)
    var target = F.new()
    target.player_index = 3
    stage.add_child(target)
    for facing in [1, -1]:
        for scenario in ["contact", "far", "early", "landing"]:
            for code in [KEY_SPACE, KEY_S, KEY_F]: key(code, false)
            f.reset_fighter(Vector3.ZERO, true)
            target.reset_fighter(Vector3(facing * (3.0 if scenario == "far" else 1.2), 0, 0), true)
            f.facing = facing
            await step(8)
            key(KEY_SPACE, true)
            await step(1)
            key(KEY_SPACE, false)
            var delay := 26 if scenario in ["contact", "far"] else (1 if scenario == "early" else 43)
            await step(delay - 1)
            key(KEY_S, true)
            key(KEY_F, true)
            await step(1)
            check(f.turbofit_attack_clip == "AirDownKick", "actual airborne S+F routes down")
            var saw_landing := false
            var trace: Array = []
            for i in 65:
                await step(1)
                var v = f.get_node("VisualRoot/TurboFitVisual")
                saw_landing = saw_landing or v.current_clip == "Landing"
                var sample := {"time": f.turbofit_attack_elapsed, "damage": target.damage_percent, "y": f.position.y, "x": f.position.x, "target": [target.position.x,target.position.y,target.position.z], "clip": f.turbofit_attack_clip, "visual": v.current_clip}
                if f.turbofit_attack_clip == "AirDownKick":
                    var volume: Dictionary = v.air_down_kick_volume(f.turbofit_attack_elapsed, 38.0/30.0, facing)
                    sample.foot = [volume.center.x,volume.center.y,volume.center.z]
                trace.append(sample)
            key(KEY_S, false)
            key(KEY_F, false)
            check(target.damage_percent == (14.0 if scenario == "contact" else 0.0), "%s facing%d actual foot contact expected damage, got%s" % [scenario, facing, target.damage_percent])
            check(f.turbofit_attack_clip.is_empty(), "landing cancels; held input does not retrigger grounded goalkeeper")
            check(saw_landing, "approved Landing retained on floor contact")
            evidence.append({"scenario": scenario, "facing": facing, "trace": trace, "damage": target.damage_percent})
    FileAccess.open("res://.verification/evidence/turbofit_air_down/physics_evidence.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS actual Space then S+F contact below both facings, far/early misses, once-only held input, real landing cancellation")
    quit(1 if failures else 0)

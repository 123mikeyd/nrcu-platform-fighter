extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
var evidence: Array = []
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
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
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var floor := StaticBody3D.new()
    floor.collision_layer = 2
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(30, 1, 4)
    collision.shape = box
    floor.position.y = -0.5
    floor.add_child(collision)
    stage.add_child(floor)
    var target = F.new()
    target.character_id = "teknium"
    target.player_index = 3
    stage.add_child(target)
    var f = F.new()
    f.character_id = "turbofit"
    stage.add_child(f)
    for sign_value in [1, -1]:
        for scenario in ["aligned", "far", "behind", "high_kick", "rising_false_positive", "landing", "landing_at_start", "friendly", "disabled"]:
            key(KEY_SPACE, false)
            key(KEY_F, false)
            f.reset_fighter(Vector3.ZERO, true)
            var separation := -1.2 if scenario == "behind" else (2.4 if scenario == "far" else 1.2)
            target.reset_fighter(Vector3(sign_value * separation, 0, 0), true)
            f.team_id = 1 if scenario == "friendly" else -1
            target.team_id = f.team_id
            f.facing = sign_value
            await step(8)
            if scenario == "disabled": target.controls_enabled = false
            key(KEY_SPACE, true)
            await step(1)
            key(KEY_SPACE, false)
            var delay := 12 if scenario == "high_kick" else (44 if scenario == "landing" else 41)
            if scenario == "rising_false_positive": delay = 1
            if scenario == "landing_at_start": delay = 42
            await step(delay - 1)
            key(KEY_F, true)
            await step(1)
            key(KEY_F, false)
            var trace: Array = []
            for i in 40:
                await step(1)
                var sample := {"elapsed": f.turbofit_attack_elapsed, "damage": target.damage_percent, "floor": f.is_on_floor(), "clip": f.turbofit_attack_clip, "position": [f.position.x, f.position.y, f.position.z]}
                if f.turbofit_attack_clip == "AirSideKick":
                    var visual = f.get_node("VisualRoot/TurboFitVisual")
                    var volume: Dictionary = visual.air_side_kick_volume(f.turbofit_attack_elapsed, 0.5, f.turbofit_attack_facing)
                    var center: Vector3 = volume.center
                    sample["foot_volume_center"] = [center.x, center.y, center.z]
                trace.append(sample)
            check(target.damage_percent == (14.0 if scenario == "aligned" else 0.0), "%s facing %d expected contact-only damage, got %s" % [scenario, sign_value, target.damage_percent])
            check(f.turbofit_attack_clip.is_empty(), "landing clears aerial activation")
            evidence.append({"scenario": scenario, "facing": sign_value, "damage": target.damage_percent, "trace": trace})
    var file := FileAccess.open("res://.verification/evidence/turbofit_air_kick/air_side_kick_fix_physics.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(evidence, "  "))
    file.close()
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS AirSideKick actual Space/F delay41 standing contact both facings; far/behind/high/landing/friendly/disabled exclusions")
    quit(1 if failures else 0)

extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = F.new()
    f.character_id = "turbofit"
    root.add_child(f)
    f.set_physics_process(false)
    var target = F.new()
    target.player_index = 3
    root.add_child(target)
    target.set_physics_process(false)
    var v = f.get_node("VisualRoot/TurboFitVisual")
    f.basic_attack(Vector2.DOWN, true)
    check(f.turbofit_attack_clip == "AirDownKick", "airborne down only selects approved AirDownKick")
    if not f.has_method("_query_air_down_kick") or not v.has_method("air_down_kick_volume"):
        check(false, "foot-local downward contact query required")
        f.free()
        target.free()
        quit(1)
        return
    check(is_equal_approx(v.animation_player.get_animation("AirDownKick").length, 38.0/30.0), "full source4-42 at 30fps")
    var exported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/air_down_kick_export_verification.json"))
    f.reset_fighter(Vector3.ZERO, true)
    for sample in exported.samples:
        var time := (float(sample.source_frame) - 4.0) / 30.0
        var foot: Array = sample.bone_world.LeftFoot
        var toe: Array = sample.bone_world.LeftToe_End
        var midpoint := (Vector3(foot[0], foot[1], foot[2]) + Vector3(toe[0], toe[1], toe[2])) * 0.5
        var expected := Vector3(-midpoint.y, midpoint.z, -midpoint.x) * 1.25
        var imported: Dictionary = v.air_down_kick_volume(time, 38.0/30.0, 1)
        # Keep existing Godot import optimization untouched for all old clips.
        # Its default angular/velocity simplification gives <=1.05cm here in
        # recovery. Exact cut endpoints and active strike samples remain tight.
        var tolerance := 0.0001 if int(sample.source_frame) in [4, 16, 17, 18, 19, 42] else 0.012
        check(imported.center.distance_to(expected) < tolerance, "source%d pose error%s expected%s actual%s" % [sample.source_frame, imported.center.distance_to(expected), expected, imported.center])
    for facing in [1, -1]:
        for mode in ["contact", "startup", "recovery", "far_below", "above", "depth", "friendly", "disabled", "hit", "reset", "stock"]:
            f.reset_fighter(Vector3(0, 3, 0), true)
            f.facing = facing
            f.basic_attack(Vector2.DOWN, true)
            f.turbofit_attack_elapsed = 14.0/30.0
            var volume: Dictionary = v.air_down_kick_volume(f.turbofit_attack_elapsed, 38.0/30.0, facing)
            target.reset_fighter(volume.center - Vector3(0, 1.6, 0), true)
            f.team_id = -1
            target.team_id = -1
            check(target.position.y < f.position.y, "contact test target really below attacker")
            match mode:
                "startup": f.turbofit_attack_elapsed = 12.0/30.0 - 0.001
                "recovery": f.turbofit_attack_elapsed = 15.0/30.0 + 0.001
                "far_below": target.position.y -= 2
                "above": target.position.y += 3
                "depth": target.position.z += 2
                "friendly":
                    f.team_id = 1
                    target.team_id = 1
                "disabled": f.controls_enabled = false
                "hit": f.receive_hit(1, Vector3.UP, 1)
                "reset": f.reset_fighter(Vector3(0, 3, 0), true)
                "stock": f.lose_stock()
            f._query_air_down_kick()
            f._query_air_down_kick()
            check(target.damage_percent == (14.0 if mode == "contact" else 0.0), "%s both-facings pose/capsule-only hit, once per target" % mode)
            if mode == "contact": check(target.velocity.y < 0, "downward spike")
    for aim in [Vector2.UP, Vector2(1, -1)]:
        f.reset_fighter(Vector3(0, 3, 0), true)
        f.basic_attack(aim, true)
        check(f.turbofit_attack_clip.is_empty(), "up fallback unchanged")
    f.reset_fighter(Vector3.ZERO, true)
    f.basic_attack(Vector2.DOWN, false)
    check(f.turbofit_attack_clip == "GoalkeeperKick", "ground S+F unchanged")
    f.reset_fighter(Vector3(0, 3, 0), true)
    f.basic_attack(Vector2.RIGHT, true)
    check(f.turbofit_attack_clip == "AirSideKick", "air neutral sidekick unchanged")
    f.free()
    target.free()
    if failures == 0: print("PASS AirDownKick routing, exact cut, small foot contact below, exclusions, once-only spike, lifecycle and prior routes")
    quit(1 if failures else 0)

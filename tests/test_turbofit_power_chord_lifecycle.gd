extends SceneTree
const FighterScript = preload("res://scripts/fighter.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok: failures += 1; printerr("FAIL: ",label)
func run() -> void:
    var f = FighterScript.new()
    f.character_id = "turbofit"
    root.add_child(f)
    var other = FighterScript.new()
    other.character_id = "turbofit"
    other.player_index = 1
    root.add_child(other)
    await process_frame
    f.set_physics_process(false)
    other.set_physics_process(false)
    var v = f.get_node("VisualRoot/TurboFitVisual")
    var ov = other.get_node("VisualRoot/TurboFitVisual")
    check(v.animation_player.get_animation("TwoHandCombo") != ov.animation_player.get_animation("TwoHandCombo"), "independent animation resources")
    for facing in [1.0, -1.0]:
        for phase in ["hold", "release", "recovery"]:
            for interruption in ["hit", "freeze", "grab", "stock", "reset", "disabled"]:
                f.reset_fighter(Vector3(0,8,0),true)
                f.controls_enabled = true
                f.facing = facing
                f.start_special(Vector2.ZERO)
                f.advance_charge(1.5)
                f._update_move_visuals(1.8)
                check(f.charging and v.power_hold_clock > 1.5, "air charge and continuing capped clock")
                if phase != "hold":
                    f.release_special()
                    f._update_move_visuals()
                    check(v.power_released, "release episode")
                    if phase == "recovery":
                        f.attack_cooldown = 0.2
                        f._update_move_visuals()
                        check(v.power_returning, "approved Idle blend")
                var source_time: float = v.animation_player.current_animation_position
                match interruption:
                    "hit": f.receive_hit(1,Vector3.RIGHT,1)
                    "freeze":
                        check(f.apply_freeze(other), "freeze accepted")
                        check(is_equal_approx(v.animation_player.current_animation_position,source_time), "freeze preserves held or release pose")
                    "grab": f.cancel_for_grab()
                    "stock": f.lose_stock()
                    "reset": f.reset_fighter(Vector3.ZERO,true)
                    "disabled": f.controls_enabled = false
                check(v.power_hold_clock == 0 and not v.power_released and not v.power_returning, "synchronous cancellation while physics stopped: " + interruption + phase)
                check(ov.power_hold_clock == 0 and not ov.power_released, "other instance unaffected")
    f.reset_fighter(Vector3.ZERO,true)
    f.controls_enabled = true
    f.start_special(Vector2.ZERO)
    f._update_move_visuals(2.7)
    f.release_special()
    f.attack_cooldown = 0 # Same-tick accepted reentry, before an idle presentation tick.
    f.start_special(Vector2.ZERO)
    check(v.power_hold_clock == 0 and not v.power_released and v.power_source_frame == 1, "new activation clears previous clock synchronously")
    f._update_move_visuals(1.0/60)
    check(v.power_source_frame < 4, "new quick tap uses fresh anticipation")
    f.release_special()
    check(v.power_source_frame == 20, "quick release contacts immediately")
    for aim in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
        f.reset_fighter(Vector3.ZERO,true)
        f.start_special(aim)
        f._update_move_visuals(0.1)
        check(not f.charging and v.power_hold_clock == 0 and not v.power_released, "directional special excludes Power Chord")
    for motion in [Vector3.ZERO, Vector3(7,0,0), Vector3(0,3,0), Vector3(0,-3,0)]:
        v.power_chord_contact(-1)
        v.sync_pose(motion.y == 0,motion,false,false,"",Vector3.RIGHT,1,0.01)
        check(not v.power_released and is_equal_approx(v.model.rotation.y,PI/2), "expiry restores ordinary facing")
        check(v.current_clip == ("Idle" if motion == Vector3.ZERO else ("Run" if motion.x > 0 else ("Jump" if motion.y > 0 else "FallLoop"))), "expiry restores locomotion")
    f._clear_move_state()
    f.queue_free(); other.queue_free()
    await process_frame
    print("PASS Power Chord lifecycle checks=",checks," failures=",failures)
    quit(1 if failures else 0)

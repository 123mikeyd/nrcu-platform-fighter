extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var view = dog._visual_root.get_node("DogeVisual")
    for facing in [1.0, -1.0]:
        dog.reset_fighter(Vector3.ZERO, true)
        dog.facing = facing
        dog.start_special(Vector2.UP)
        dog._update_move_visuals()
        check(view.current_clip == "Dive", "up uses existing Dive immediately")
        check((view.model.global_basis * Vector3.BACK).normalized().dot(Vector3.UP) > 0.999, "whole visual forward maps upward both facings")
        check(dog.rotation == Vector3.ZERO and dog.velocity.y == 13.5 and dog.recovery_active == 0.38 and dog.attack_cooldown == 0.65, "controller unchanged")
        dog._attack_flash.visible = true
        dog._update_move_visuals()
        check(not dog._attack_flash.visible and dog.attack_flash_time == 0.38, "Doge up hides only placeholder without editing its clock")
    dog.recovery_active = 0
    dog.velocity.y = 0.2
    dog._update_move_visuals(0.5)
    check(view.current_clip == "Dive", "episode outlasts damaging window until apex")
    dog.velocity.y = -0.1
    dog._update_move_visuals(0.03)
    check(view.current_clip == "MidairMoves2" and absf(view.flight_root.rotation.z) > 0 and absf(view.flight_root.rotation.z) < PI/2, "apex smoothly restores approved midair")
    dog._update_move_visuals(0.2)
    check(view.flight_root.rotation == Vector3.ZERO, "apex rotation fully restored")
    for sink in ["hit", "disable", "reset", "stock", "cancel", "freeze"]:
        dog.reset_fighter(Vector3.ZERO, true)
        dog.start_special(Vector2.UP)
        dog._update_move_visuals(0.1)
        var pose_time: float = view.animation_player.current_animation_position
        if sink == "hit": dog.receive_hit(3, Vector3.UP, 3)
        if sink == "disable": dog.controls_enabled = false
        if sink == "reset": dog.reset_fighter(Vector3.ZERO, true)
        if sink == "stock": dog.lose_stock()
        if sink == "cancel": dog._cancel_doge_attack()
        if sink == "freeze":
            var caster = F.new()
            caster.player_index = 1
            root.add_child(caster)
            caster.set_physics_process(false)
            check(dog.apply_freeze(caster), "freeze accepted")
            check(is_equal_approx(view.animation_player.current_animation_position, pose_time) and not view.animation_player.is_playing(), "freeze pauses exact skeleton pose")
            check(absf(view.flight_root.rotation.z) > 1, "freeze keeps whole current pose")
            dog._thaw()
            dog._update_move_visuals()
            caster.queue_free()
        check(view.up_elapsed < 0 and view.flight_root.rotation == Vector3.ZERO, "synchronous cleanup: " + sink)
    dog.reset_fighter(Vector3(1.35,0,0),true)
    dog.start_special(Vector2.UP)
    dog.velocity = Vector3.ZERO
    var grabber = F.new()
    root.add_child(grabber)
    grabber.set_physics_process(false)
    await physics_frame
    await process_frame
    grabber.start_special(Vector2.ZERO)
    grabber.teknium_magic.tick(0.20+4.0/24.0+0.35)
    dog._update_move_visuals()
    check(view.current_clip == "Electrocution" and view.flight_root.rotation == Vector3.ZERO and view.up_elapsed < 0,"real grab reaction has higher priority and clears flight")
    check(dog.recovery_spent and dog.jumps_used == 2,"grab does not refund up recovery")
    grabber.cancel_magic()
    dog._update_move_visuals()
    check(view.flight_root.rotation == Vector3.ZERO and view.current_clip != "Dive","release cannot resume stale Dive")
    grabber.queue_free()
    dog.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge upward presentation")
    quit(1 if failures else 0)

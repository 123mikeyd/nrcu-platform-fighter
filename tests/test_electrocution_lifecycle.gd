extends SceneTree
var failures := 0
func check(ok, message):
    if not ok: failures += 1; print("FAIL: ", message)
func _initialize(): call_deferred("run")
func run():
    for mode in ["victim_disabled","caster_disabled","hit","freeze","stock","reset","cancel","duplicate"]:
        var f = load("res://scripts/fighter.gd").new(); root.add_child(f); f.set_physics_process(false)
        var v = load("res://scripts/fighter.gd").new(); v.character_id = "doge_man"; root.add_child(v); v.set_physics_process(false); v.position.x = 1.35
        var twin = load("res://scripts/fighter.gd").new(); twin.character_id = "doge_man"; root.add_child(twin); twin.set_physics_process(false); twin.position.x = 9
        await physics_frame; await process_frame
        var visual = v.get_node("VisualRoot/DogeVisual")
        var other = twin.get_node("VisualRoot/DogeVisual")
        f.start_special(Vector2.ZERO); f.teknium_magic.tick(0.20+4.0/24.0+0.35); v._update_move_visuals(0)
        check(visual.current_clip == "Electrocution", mode+" real hold entered")
        v.jumps_used = 2; v.tackle_spent = true
        var frozen_position = visual.animation_player.current_animation_position
        match mode:
            "victim_disabled": v.controls_enabled = false
            "caster_disabled": f.controls_enabled = false
            "hit": v.receive_hit(3,Vector3.RIGHT,2)
            "freeze": v.apply_freeze(f)
            "stock": v.lose_stock()
            "reset": v.reset_fighter(Vector3.ZERO,true)
            "cancel": f.cancel_magic()
            "duplicate":
                check(other.current_clip != "Electrocution", "duplicate does not inherit clip")
                check(other.animation_player.get_animation("Electrocution") != visual.animation_player.get_animation("Electrocution"), "duplicate animations independent")
                f.cancel_magic()
        check(v.caught_by == null and v.electrocution_presentation.active_player == null, mode+" clears synchronously while physics stopped")
        if mode == "freeze":
            check(not visual.animation_player.is_playing() and is_equal_approx(visual.animation_player.current_animation_position,frozen_position), "freeze preserves paused designated pose")
            v._tick_freeze(1.1)
        if mode not in ["stock","reset"]: check(v.jumps_used == 2 and v.tackle_spent, mode+" does not refund airborne resources")
        if mode == "victim_disabled" or mode == "caster_disabled":
            check(visual.animation_player.assigned_animation != "Electrocution", mode+" no stale reaction when physics never runs again")
        v.controls_enabled = true; f.controls_enabled = true; v.hitstun = 0; v.attack_cooldown = 0
        v._update_move_visuals(0.1)
        check(visual.current_clip != "Electrocution" and visual.animation_player.speed_scale > 0, mode+" normal animation restored")
        f.queue_free(); v.queue_free(); twin.queue_free(); await process_frame
    if failures == 0: print("PASS: electrocution lifecycle, freeze priority, independent duplicates and no resource refund")
    quit(0 if failures == 0 else 1)

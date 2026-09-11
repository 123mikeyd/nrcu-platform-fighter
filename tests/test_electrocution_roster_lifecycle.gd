extends SceneTree
var failures := 0
func check(ok, message):
    if not ok: failures += 1; print("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
    for id in ["teknium","turbofit","ice_mage","fire_mage","ggb"]:
        for mode in ["victim_disabled","caster_disabled","hit","freeze","stock","reset","cancel","duplicate"]:
            var f = load("res://scripts/fighter.gd").new(); root.add_child(f); f.set_physics_process(false)
            var v = load("res://scripts/fighter.gd").new(); v.character_id = "ice_mage" if id == "fire_mage" else id; root.add_child(v);v.set_physics_process(false);v.position.x=1.35
            if id == "fire_mage": v.enable_fire_prototype()
            var twin = load("res://scripts/fighter.gd").new();twin.character_id=v.character_id;root.add_child(twin);twin.set_physics_process(false);twin.position.x=9
            await physics_frame;await process_frame
            var visual=v._visual_root.get_children()[0];var other=twin._visual_root.get_children()[0]
            f.start_special(Vector2.ZERO);f.teknium_magic.tick(0.20+4.0/24.0+0.35);v._update_move_visuals(0)
            check(v.electrocution_presentation.active_visual == visual,id+mode+" hold")
            v.jumps_used=2;v.tackle_spent=true
            var pose := {}
            if id == "ggb":
                for node in visual.reaction_originals:pose[node]=node.transform
            else: pose["time"]=visual.animation_player.current_animation_position
            match mode:
                "victim_disabled":v.controls_enabled=false
                "caster_disabled":f.controls_enabled=false
                "hit":v.receive_hit(3,Vector3.RIGHT,2)
                "freeze":v.apply_freeze(f)
                "stock":v.lose_stock()
                "reset":v.reset_fighter(Vector3.ZERO,true)
                "cancel":f.cancel_magic()
                "duplicate":
                    if id != "ggb":check(other.animation_player.get_animation("Electrocution") != visual.animation_player.get_animation("Electrocution"),id+" independent libraries")
                    else:check(other.reaction_originals.is_empty(),"GGB duplicate unchanged")
                    f.cancel_magic()
            check(v.caught_by == null and v.electrocution_presentation.active_visual == null,id+mode+" synchronous cleanup")
            if mode == "freeze":
                v._update_move_visuals(0.1)
                if id == "ggb":
                    for node in pose:check(node.transform.is_equal_approx(pose[node]),"GGB frozen exact pose")
                else:check(not visual.animation_player.is_playing() and is_equal_approx(visual.animation_player.current_animation_position,pose.time),id+" freeze paused exact")
                v._tick_freeze(1.1)
            if mode not in ["stock","reset"]:check(v.jumps_used==2 and v.tackle_spent,id+" no resources refunded")
            v.controls_enabled=true;f.controls_enabled=true;v.hitstun=0;v.attack_cooldown=0;v._update_move_visuals(0.1)
            if id == "ggb":check(visual.reaction_originals.is_empty(),"GGB restored")
            else:check(visual.current_clip != "Electrocution" and visual.animation_player.speed_scale>0,id+mode+" resumed")
            f.queue_free();v.queue_free();twin.queue_free();await process_frame
    if failures == 0:print("PASS roster lifecycle and independent instances")
    quit(1 if failures else 0)

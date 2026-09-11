extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok,message):
    if not ok:failures+=1;print("FAIL: ",message)
func run():
    var f=load("res://scripts/fighter.gd").new();root.add_child(f);f.set_physics_process(false)
    var v=load("res://scripts/fighter.gd").new();root.add_child(v);v.set_physics_process(false);v.position=Vector3(1.35,0,0)
    await physics_frame;await process_frame
    var m=f.teknium_magic;var visual=m.visual
    f.start_special(Vector2.RIGHT);m.tick(0.249)
    check(get_nodes_in_group("projectiles").is_empty(),"force still waits before0.25s")
    m.tick(0.001)
    var shots=get_nodes_in_group("projectiles")
    check(shots.size()==1,"force spawns at0.25s, not old0.667s")
    if shots.size()==1:
        shots[0].set_physics_process(false)
        check(shots[0].position.distance_to(visual.hand_tip())<0.001,"accelerated force still spawns exact evaluated hand")
        shots[0].queue_free()
    check(is_equal_approx(visual.animation_player.current_animation_position,16.0/24.0),"force source46 pose at0.25s")
    m.tick(0.25)
    check(is_equal_approx(visual.animation_player.current_animation_position,22.0/24.0),"force post-release advances six source frames in0.25s")
    m.cancel();f.attack_cooldown=0
    f.start_special(Vector2.ZERO);m.tick(0.199)
    check(v.caught_by==null and v.damage_percent==0,"no grab before0.20s")
    m.tick(0.001)
    check(v.caught_by==m,"grab attempts at0.20s, not old0.542s")
    check(is_equal_approx(visual.animation_player.current_animation_position,13.0/24.0),"grab source24 pose at0.20s")
    m.tick(4.0/24.0)
    check(m.phase=="hold" and is_zero_approx(m.elapsed),"grab source24 to28 remains normal24FPS")
    m.tick(1.25)
    check(m.phase=="ending" and v.damage_percent==10,"full original-speed hold and damage unchanged")
    m.tick(5.0/24.0)
    check(v.caught_by==null,"source64 release interval unchanged")
    f.queue_free();v.queue_free();await process_frame
    if failures==0:print("PASS: faster anticipation only, exact source-event hand pose, unchanged post-event speed/hold/finish")
    quit(0 if failures==0 else 1)

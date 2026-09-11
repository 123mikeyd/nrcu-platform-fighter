extends SceneTree
var failures := 0
func check(ok, message):
    if not ok: failures += 1; printerr("FAIL: ",message)
func _initialize(): call_deferred("run")
func fighter(pos: Vector3):
    var f = load("res://scripts/fighter.gd").new()
    f.character_id = "turbofit"
    root.add_child(f); f.set_physics_process(false); f.position = pos
    return f
func run():
    var f = fighter(Vector3.ZERO)
    f.start_special(Vector2.RIGHT)
    var shot = get_nodes_in_group("projectiles")[0]
    shot.set_physics_process(false)
    var origin: Vector3 = shot.position
    shot._physics_process(0.1)
    print("MEASURE displacement_0.1=",shot.position.x-origin.x," cooldown=",f.attack_cooldown)
    check(shot.position.x-origin.x < 1.0,"horizontal TurboFit pulse starts slower than 15 units/s shared bolt")
    check(shot.get_script().resource_path == "res://scripts/turbofit_sound_wave.gd","isolated TurboFit route")
    check(f.attack_cooldown == 0.55,"original cooldown preserved")
    if not shot.has_method("damage_active"):
        check(false,"pulse growth/deceleration/fade contract missing")
    else:
        check(shot._rings.size()==3,"three separated pressure fronts")
        check(shot._rings[0].mesh is ImmediateMesh,"bowed transverse fronts avoid edge-on straight bars at arena camera")
        var radius: float = shot.wave_radius
        var speed: float = shot.current_speed
        var old_x: float = shot.position.x
        shot._physics_process(0.3)
        check(shot.wave_radius > radius and shot.wave_radius <= 0.85,"bounded growth")
        check(shot.current_speed < speed,"visible deceleration")
        check(shot.position.x-old_x < 2.4,"later travel slows")
        shot._physics_process(0.3)
        check(not shot.damage_active(),"fade is visual only")
        check(shot.opacity > 0 and shot.opacity < 0.8,"fade opacity decreases")
        check(shot.distance_travelled < 5.0,"short cumulative range")
        shot._physics_process(0.21)
        check(shot.is_queued_for_deletion(),"finite TTL cleanup")
    f.queue_free();shot.queue_free();await process_frame
    f = fighter(Vector3.ZERO)
    f.start_special(Vector2.RIGHT)
    shot = get_nodes_in_group("projectiles")[0]
    var previous_speed := 10.0
    var previous_radius := 0.4
    var last_distance := 0.0
    var samples := 0
    var saw_fade := false
    for i in 65:
        await physics_frame;await process_frame
        if not is_instance_valid(shot):break
        samples += 1
        check(shot.current_speed < previous_speed,"real physics monotonically decelerates")
        check(shot.wave_radius > previous_radius and shot.wave_radius <= 0.85,"real physics monotonically grows within cap")
        check(shot.distance_travelled <= 4.86,"real physics path stays bounded")
        if shot.age >= 0.65:
            saw_fade = true
            check(not shot.damage_active() and shot.opacity < 0.8,"real fade cannot damage")
        previous_speed=shot.current_speed;previous_radius=shot.wave_radius;last_distance=shot.distance_travelled
    check(samples>20 and saw_fade and not is_instance_valid(shot),"actual physics runs growing slowing fading then deletes")
    check(last_distance>4.7 and last_distance<=4.86,"short real total path measured")
    print("MEASURE real_samples=",samples," last_distance=",last_distance)
    f.queue_free();await process_frame
    if failures == 0: print("PASS TurboFit sound wave")
    quit(1 if failures else 0)

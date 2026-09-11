extends SceneTree
var failures := 0
func check(ok,message):
    if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func fighter(pos:Vector3):
    var f=load("res://scripts/fighter.gd").new();f.character_id="turbofit";root.add_child(f);f.set_physics_process(false);f.position=pos;return f
func shot(f):
    var s=load("res://scripts/turbofit_sound_wave.gd").new();s.source=f;root.add_child(s);s.position=f.position+Vector3(0.8,1,0);s.set_physics_process(false);return s
func run():
    var a=fighter(Vector3.ZERO);var b=fighter(Vector3(10,0,0))
    var s=shot(a);var duplicate=shot(a)
    s._physics_process(0.4)
    var before=[s.lifetime,s.wave_radius,s.current_speed,s.distance_travelled,s.age]
    s.reflect(b,Color.RED)
    check(s.source==b and s.direction==-1,"reflection transfers allegiance and reverses")
    check(before==[s.lifetime,s.wave_radius,s.current_speed,s.distance_travelled,s.age],"reflection preserves ALL finite budgets")
    check(duplicate.age==0 and duplicate.direction==1,"duplicate clocks independent")
    check(s._rings[0].material_override!=duplicate._rings[0].material_override,"per-wave materials independent")
    for i in 20:s.reflect(a if i%2 else b,Color.RED)
    s._physics_process(0.51)
    check(s.is_queued_for_deletion(),"repeat reflection cannot extend lifetime")
    duplicate.queue_free();s.queue_free();await process_frame
    # Actual SoundOrb path, once per activation, no radius/mechanics changes.
    s=shot(a);s.position=b.position+Vector3(0.8,1,0)
    s._physics_process(0.01)
    b.start_special(Vector2.DOWN)
    check(s.source==b and s.direction==-1,"actual orb reflects variant")
    b._tick_sound_orb(0.02)
    check(s.direction==-1,"orb does not re-reflect same wave")
    check(b.SOUND_ORB_RADIUS==1.15 and a.damage_percent==0,"compact zero-damage utility unchanged")
    b.reset_fighter(Vector3(10,0,0),true)
    check(s.is_queued_for_deletion(),"new owner's reset clears reflected projectile")
    await process_frame
    s=shot(a);a.lose_stock()
    check(s.is_queued_for_deletion(),"stock loss clears owned wave")
    await process_frame
    s=shot(a);a.controls_enabled=false;s._physics_process(0.01)
    check(s.is_queued_for_deletion(),"disabled controls clears projectile")
    s.queue_free();a.queue_free();b.queue_free();await process_frame
    a=fighter(Vector3.ZERO);s=shot(a);a.queue_free();await process_frame
    s._physics_process(0.01);check(s.is_queued_for_deletion(),"deleted source safe cleanup")
    s.queue_free();await process_frame
    if failures==0:print("PASS TurboFit wave reflection budgets / actual SoundOrb / independent lifecycle")
    quit(1 if failures else 0)

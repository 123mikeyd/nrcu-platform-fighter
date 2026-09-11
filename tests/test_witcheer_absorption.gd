extends SceneTree
var failures:=0
var checks:=0
var f
var enemy
func _initialize():call_deferred("run")
func check(ok:bool,msg:String):
    checks+=1
    if not ok:failures+=1;printerr("FAIL: "+msg)
func dance(age:=0.5):
    f.reset_fighter(Vector3.ZERO,true);f.damage_percent=30;f.start_special(Vector2.DOWN);f._tick_witcheer(age)
func shot(kind:String):
    var p=load("res://scripts/"+kind+".gd").new();p.source=enemy;root.add_child(p);p.set_physics_process(false);return p
func run():
    f=load("res://scripts/fighter.gd").new();f.character_id="witcheer";root.add_child(f);f.set_physics_process(false)
    enemy=load("res://scripts/fighter.gd").new();root.add_child(enemy);enemy.set_physics_process(false);enemy.position=Vector3(-3,0,0)
    await physics_frame;await process_frame
    for kind in ["projectile","goo_projectile","teknium_force_projectile","turbofit_sound_wave","freeze"]:
        dance()
        var p=shot("projectile" if kind=="freeze" else kind)
        if kind=="freeze":p.freeze_bolt=true
        if kind=="turbofit_sound_wave":
            p.position=Vector3(-0.4,1,0);p._sweep_wave(Vector3(0.2,0,0))
        else:p._hit_target(f)
        var amount=4 if kind=="freeze" else (8 if kind=="teknium_force_projectile" else 11)
        check(f.damage_percent==30-amount,kind+" heals actual payload")
        check(p.is_queued_for_deletion(),kind+" consumed")
        check(f.freeze_remaining==0,kind+" no freeze on consume")
        check(get_nodes_in_group("goo_puddles").is_empty(),kind+" no puddle")
        p.queue_free();await process_frame
    for age in [0.0,0.3,1.334,1.66]:
        dance(age);var p=shot("projectile");p._hit_target(f)
        check(f.damage_percent==41,"vulnerable startup/recovery "+str(age));p.queue_free()
    dance();f.damage_percent=3;var clamp_shot=shot("projectile");clamp_shot._hit_target(f);check(f.damage_percent==0,"clamp healing to zero")
    dance();f.shielding=true;var shield=shot("projectile");shield._hit_target(f);check(f.damage_percent>=30,"shield precedence no healing");shield.queue_free()
    for mode in ["self","team","reflected_enemy","reflected_self","hidden","expired","wave_fade"]:
        dance();var p=shot("turbofit_sound_wave" if mode=="wave_fade" else "projectile")
        match mode:
            "self":p.source=f
            "team":f.team_id=2;enemy.team_id=2
            "reflected_enemy":p.source=f;p.reflect(enemy,Color.WHITE)
            "reflected_self":p.reflect(f,Color.WHITE)
            "hidden":p.hide()
            "expired":p.lifetime=0
            "wave_fade":p.age=p.FADE_START
        if mode=="wave_fade":p.position=Vector3(-0.4,1,0);p._sweep_wave(Vector3(0.2,0,0))
        else:p._try_absorb(f)
        check(f.damage_percent==(19 if mode=="reflected_enemy" else 30),"allegiance/visibility "+mode)
        p.queue_free();f.team_id=-1;enemy.team_id=-1
    for mode in ["melee","freeze","grab","stock","reset","setup","winner"]:
        dance()
        match mode:
            "melee":f.receive_hit(2,Vector3.RIGHT,1)
            "freeze":f.apply_freeze(enemy)
            "grab":f.cancel_for_grab()
            "stock":f.lose_stock()
            "reset":f.reset_fighter(Vector3.ZERO,true)
            "setup","winner":f.controls_enabled=false;f._update_move_visuals()
        var before=f.damage_percent;var p=shot("projectile");p._try_absorb(f)
        check(f.witcheer_clip.is_empty(),"cancel "+mode);check(f.damage_percent==before,"no stale healing "+mode);p.queue_free()
    dance();check(f.absorb_witcheer_projectile(enemy,0),"zero utility consumed");check(f.damage_percent==30,"zero utility no healing")
    f.queue_free();enemy.queue_free();await process_frame
    print("PASS absorption matrix %d checks"%checks if failures==0 else "matrix failures %d"%failures);quit(0 if failures==0 else 1)

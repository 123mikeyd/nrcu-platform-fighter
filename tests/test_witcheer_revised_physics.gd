extends "res://tests/test_witcheer_physics.gd"
func run():
    render="--capture" in OS.get_cmdline_user_args()
    arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
    load("res://tools/play_witcheer.gd").configure(arena)
    # Duplicate Witcheers prove independent celebration state and animation resources.
    arena.setup.rows[1].character.select(load("res://scripts/match_config.gd").CHARACTERS.find("witcheer"));arena.setup._start()
    f=arena.fighters[0];v=arena.fighters[1];visual=f.get_node("VisualRoot/WitcheerVisual")
    for other in arena.fighters:other.control_type="human";other.input_device=99;other.set_physics_process(false)
    f.input_device=-1
    await frames(4)
    for kind in ["projectile","goo_projectile","teknium_force_projectile","turbofit_sound_wave","freeze"]:
        await prepare();v.position.x=-5;f.damage_percent=30
        key(KEY_S,true);await press(KEY_G);key(KEY_S,false);await frames(24)
        check(f.witcheer_absorbing and f.witcheer_clip=="Celebration","real keyboard active dance "+kind)
        check(v.witcheer_clip.is_empty(),"duplicate fighter does not inherit dance")
        var p=load("res://scripts/"+("projectile" if kind=="freeze" else kind)+".gd").new();p.source=v;p.direction=1
        if kind=="freeze":p.freeze_bolt=true
        arena.add_child(p);p.position=f.position+Vector3(-1.1,1.1,0)
        if kind=="goo_projectile":p.fall_speed=0
        await frames(12)
        var amount=4 if kind=="freeze" else (8 if kind=="teknium_force_projectile" else 11)
        check(f.damage_percent==30-amount,"actual swept contact heals "+kind)
        check(f.freeze_remaining==0,"physical consume has no freeze "+kind)
        check(not is_instance_valid(p) or p.is_queued_for_deletion(),"actual projectile gone "+kind)
        await shot("absorb_"+kind)
        await frames(60)
        check(f.damage_percent==30-amount,"no late damage/heal "+kind)
        check(get_nodes_in_group("goo_puddles").is_empty(),"no consumed-goo puddle "+kind)
    await prepare();v.position.x=-5;f.damage_percent=30
    key(KEY_S,true);key(KEY_G,true);await frames(30)
    f.receive_hit(2,Vector3.RIGHT,1);await frames(125)
    check(f.witcheer_clip.is_empty() and not f.witcheer_absorbing,"held G cannot restart after melee/expiry")
    release();await frames(3)
    key(KEY_S,true);key(KEY_G,true);await frames(30);check(f.apply_freeze(v),"dance freeze interruption")
    await frames(90);check(f.freeze_remaining==0 and f.witcheer_clip.is_empty(),"held G cannot restart on thaw")
    release();await frames(3)
    await prepare();v.position.x=7
    key(KEY_S,true);key(KEY_G,true);await frames(30)
    f.controls_enabled=false
    check(f.witcheer_clip.is_empty() and not f.witcheer_absorbing,"disable clears dance synchronously even if physics stops")
    f.reset_fighter(Vector3(-2,0,0),true);await frames(4)
    check(f.witcheer_clip.is_empty(),"held G cannot fire after reset/unlock")
    release();await frames(3)
    # Real jump up-basic: ordinary falling acceleration and no additional recovery resource.
    await prepare();v.position.x=7
    await press(KEY_SPACE);await frames(2)
    var prior_y:float=f.velocity.y;var jumps:int=f.jumps_used
    key(KEY_W,true);await press(KEY_F);key(KEY_W,false)
    check(f.witcheer_clip=="SpinRise","keyboard airborne W+F routes up basic")
    check(f.velocity.y<prior_y and f.jumps_used==jumps and not f.recovery_spent,"up-basic ordinary gravity/no extra lift")
    await frames(15);await shot("up_basic")
    await frames(90);check(f.is_grounded() and f.witcheer_clip.is_empty(),"up-basic real landing cancel")
    await prepare();f.position.y=0.25;f.velocity.y=-4;v.position=f.position+Vector3(0.5,1.4,0)
    key(KEY_W,true);await press(KEY_F);key(KEY_W,false);await frames(40)
    check(v.damage_percent==0,"late descending up-basic cancels before source event")
    release();arena.show_setup();await frames(3);await shot("revised_ready")
    check(not f.controls_enabled and f.witcheer_clip.is_empty(),"setup cancels all state")
    arena.queue_free();await process_frame
    print(("PASS " if failures==0 else "FAIL ")+"REVISED PHYSICS: %d checks, %d failures; rendered=%s"%[checks,failures,str(render)])
    quit(0 if failures==0 else 1)

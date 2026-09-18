extends "res://tests/test_teknium_kit_rework.gd"
func run():
    arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
    var ids=load("res://scripts/match_config.gd").CHARACTERS
    for i in 2:
        arena.setup.rows[i].character.select(ids.find("teknium" if i==0 else "doge_man"));arena.setup.rows[i].kind.select(0)
    arena.setup.rows[2].kind.select(2);arena.setup.rows[3].kind.select(2);arena.setup._refresh();arena.setup._start();await frames(150)
    f=arena.fighters[0];target=arena.fighters[1]
    var kit=f.teknium_specials
    for direction in [-1,1]:
        await reset_case();f.facing=direction
        target.reset_fighter(Vector3(-2+direction*3,0,0),true);await frames(8)
        key(KEY_G,true);await frames(30);key(KEY_G,false);await frames(18)
        check(target.damage_percent>10,"partial shot hits both facings "+str(direction))
        await reset_case();f.facing=direction
        f.reset_fighter(Vector3(-2,3,0),true);await frames(2)
        key(KEY_W,true);key(KEY_G,true);await frames(2);key(KEY_W,false)
        key(KEY_A if direction<0 else KEY_D,true);await frames(31)
        check(f.velocity.x*direction>19 and absf(f.velocity.y)<0.1,"eight-way aim supports either horizontal direction "+str(direction))
    await reset_case()
    key(KEY_G,true);await frames(30);key(KEY_E,true);await frames(2)
    check("STORED" in f._move_status.text,"stored energy remains visible to player")
    await reset_case()
    key(KEY_S,true);key(KEY_G,true);await frames(3)
    check("REMOTE" in f._move_status.text,"armed grenade has visible remote-ready status")
    f.controls_enabled=false;await frames(2)
    check(not is_instance_valid(kit.grenade),"match disable clears owned grenade")
    await reset_case()
    f.start_special(Vector2.ZERO);f.advance_charge(1);f.release_special()
    f.controls_enabled=false;await frames(2)
    check(get_nodes_in_group("teknium_charge_shots").is_empty(),"match disable clears charge shots")
    # Shield/team and far vertical misses retain native damage policy.
    await reset_case(); f.facing=1
    target.reset_fighter(Vector3(1,0,0),true);await frames(8)
    target.set_physics_process(false);target.shielding=true
    f.start_special(Vector2.ZERO);f.release_special();await frames(18)
    check(target.damage_percent>0 and target.damage_percent<5,"shield reduces charge-shot damage")
    target.set_physics_process(true)
    await reset_case(); f.team_id=1;target.team_id=1
    target.reset_fighter(Vector3(1,0,0),true);await frames(8)
    f.start_special(Vector2.ZERO);f.release_special();await frames(18)
    check(target.damage_percent==0,"charge shot cannot damage teammate")
    f.team_id=-1;target.team_id=-1
    await reset_case();target.reset_fighter(Vector3(1,5,0),true);target.set_physics_process(false)
    f.start_special(Vector2.ZERO);f.release_special();await frames(18)
    check(target.damage_percent==0,"charge shot misses high target")
    target.set_physics_process(true)
    # Passive recharge cannot fire on a cancelled/held edge.
    await reset_case();key(KEY_G,true);await frames(20)
    f.receive_hit_from(1,Vector3.LEFT,1,target);await frames(35)
    check(not f.charging and get_nodes_in_group("teknium_charge_shots").is_empty(),"hit interrupts charging without a ghost shot or held restart")
    await reset_case();key(KEY_W,true);key(KEY_G,true);await frames(8)
    f.apply_freeze(target);await frames(5)
    check(kit.phase=="idle" and f.velocity.y<=0,"freeze cancels recovery startup impulse")
    # Fixed wall blocks rays and bounds both specials/projectiles.
    await reset_case()
    var wall=StaticBody3D.new();var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(.25,9,4);col.shape=box;wall.add_child(col);arena.add_child(wall);wall.position=Vector3(0,3,0)
    target.reset_fighter(Vector3(1,0,0),true);await frames(8)
    f.start_special(Vector2.ZERO);f.release_special();await frames(18)
    check(target.damage_percent==0 and get_nodes_in_group("teknium_charge_shots").is_empty(),"charge shot is consumed by stage wall")
    await reset_case();target.reset_fighter(Vector3(1,0,0),true);await frames(8)
    f.start_special(Vector2.DOWN);kit.grenade.global_position=Vector3(-0.5,.4,0);kit.grenade.velocity=Vector3.ZERO
    await frames(23);f.start_special(Vector2.DOWN);await frames(2)
    check(target.damage_percent==0,"remote blast cannot cross a stage wall")
    await reset_case();key(KEY_W,true);key(KEY_G,true);await frames(2);key(KEY_W,false);key(KEY_D,true);await frames(45)
    check(f.global_position.x<-.4,"recovery burst stops at physical wall")
    wall.queue_free();await frames(2)
    # Native basics still enter their approved controllers after new specials.
    await reset_case();key(KEY_F,true);await frames(2)
    check(f.reaction_recovery.lab_move=="jab","Tek neutral basic stays original jab")
    await reset_case();key(KEY_D,true);key(KEY_F,true);await frames(2)
    check(f.reaction_recovery.lab_move=="side_basic","Tek grounded side basic stays approved tap combo")
    await reset_case();key(KEY_W,true);key(KEY_F,true);await frames(2)
    check(f.reaction_recovery.lab_move=="uppercut","Tek up basic stays approved uppercut")
    await reset_case();f.reset_fighter(Vector3(-2,4,0),true);await frames(2);key(KEY_F,true);await frames(2)
    check(f.humanoid_air_basic.active,"Tek air neutral stays shared aerial kick")
    var help=load("res://scripts/demo_style.gd").MOVES
    check("remote" in help and "Shadow Kick" in help and not "force push" in help,"in-game help describes new four-special controls")
    for code in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_G,KEY_SPACE,KEY_E,KEY_F]:key(code,false)
    arena.queue_free();await frames(3)
    check(get_nodes_in_group("teknium_charge_shots").is_empty() and get_nodes_in_group("teknium_grenades").is_empty() and get_nodes_in_group("teknium_afterimages").is_empty(),"scene teardown cleans owned objects")
    print("TEKNIUM_KIT_SAFETY_COMPLETE checks=%d failures=%d" % [checks,fails]);quit(1 if fails else 0)

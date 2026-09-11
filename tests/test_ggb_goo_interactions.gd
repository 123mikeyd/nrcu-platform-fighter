extends SceneTree
const Goo=preload("res://scripts/goo_projectile.gd")
const Pool=preload("res://scripts/goo_puddle.gd")
var failures:=0
var arena
var caster
var enemy
func _initialize():call_deferred("run")
func check(ok:bool,msg:String):
    if not ok: failures+=1;printerr("FAIL: "+msg)
func frames(n:int):
    for i in n:
        await physics_frame
        await process_frame
func clear_effects():
    for p in get_nodes_in_group("projectiles")+get_nodes_in_group("goo_puddles"):p.queue_free()
    await process_frame
func glob(pos:Vector3):
    var p=Goo.new();p.source=caster;arena.add_child(p);p.position=pos
    return p
func pool(pos:Vector3):
    var p=Pool.new();p.source=caster;p.surface=arena;arena.add_child(p);p.position=pos
    return p
func key(code:int,pressed:bool):
    var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
    Input.parse_input_event(e);Input.flush_buffered_events()
func run():
    arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
    await process_frame
    var slots=load("res://scripts/match_config.gd").default_slots()
    slots[0].character="ggb";slots[1].character="turbofit"
    slots[2].kind="empty";slots[3].kind="empty"
    arena.start_match(slots,false)
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    caster=arena.fighters[0];enemy=arena.fighters[1]
    for f in arena.fighters:f.set_physics_process(false);f.position=Vector3(12,0,0)
    # A downward ray reaches the real raised platform, not a guessed stage Y.
    var p=glob(Vector3(-5.2,4.2,0));p.fall_speed=-5;p.travel=Goo.MAX_TRAVEL
    await frames(20)
    check(get_nodes_in_group("goo_puddles").size()==1,"downward glob creates raised platform pool")
    if not get_nodes_in_group("goo_puddles").is_empty():
        check(absf(get_nodes_in_group("goo_puddles")[0].position.y-3.25)<0.04,"pool follows physical platform top")
    await clear_effects()
    # Fighter surface is damage, never a pool; shield uses shared chip.
    enemy.reset_fighter(Vector3(0,0,0),true);enemy.shielding=true
    p=glob(Vector3(-1,1,0));p.fall_speed=0
    await frames(12)
    check(is_equal_approx(enemy.damage_percent,3.85),"goo retains 11 damage / shield 35 percent chip")
    check(get_nodes_in_group("goo_puddles").is_empty(),"fighter hit cannot become terrain puddle")
    enemy.reset_fighter(Vector3(0,0,0));enemy.apply_freeze(caster)
    p=glob(Vector3(-1,1,0));p.fall_speed=0
    await frames(12)
    check(enemy.freeze_remaining==0 and enemy.damage_percent==11,"direct goo damage shatters Ice freeze normally")
    await clear_effects()
    # Terrain before a fighter must occlude it (thin wall).
    var wall=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new()
    box.size=Vector3(0.12,3,2);shape.shape=box;wall.add_child(shape);arena.add_child(wall);wall.position=Vector3(-0.6,1,0)
    enemy.reset_fighter(Vector3(0,0,0));await frames(2)
    p=glob(Vector3(-1.5,1,0));p._physics_process(0.3)
    check(enemy.damage_percent==0 and p.is_queued_for_deletion(),"ordered sweep stops at terrain before fighter")
    check(get_nodes_in_group("goo_puddles").is_empty(),"vertical wall is not a sticky floor")
    wall.queue_free();await clear_effects()
    # Reflection through the actual Sound Orb method, then future pool allegiance.
    enemy.position=Vector3(0,0,0);caster.position=Vector3(12,0,0)
    p=glob(Vector3(-0.95,1,0));p.lifetime=0.7
    enemy.sound_orb_time=0.55;enemy._tick_sound_orb(0)
    check(p.source==enemy and p.direction==-1 and p.lifetime==0.7,"Orb transfers goo ownership without extending TTL")
    enemy._tick_sound_orb(0)
    check(p.direction==-1,"same Orb cannot reflect twice")
    p.fall_speed=-4
    await frames(18)
    check(get_nodes_in_group("goo_puddles").size()==1,"reflected goo still creates pool")
    if not get_nodes_in_group("goo_puddles").is_empty():
        var reflected_pool=get_nodes_in_group("goo_puddles")[0]
        check(reflected_pool.source==enemy,"future pool uses reflected allegiance")
        caster.reset_fighter(reflected_pool.position+Vector3(0,0.1,0));caster.set_physics_process(true)
        await frames(12);caster.set_physics_process(false)
        check(caster.is_on_floor() and caster.ground_speed_multiplier()==0.65,"reflected pool actually slows its original caster")
        enemy.position=reflected_pool.position+Vector3(0,0.1,0);enemy.control_type="keyboard";enemy.set_physics_process(true)
        await frames(12);enemy.set_physics_process(false)
        check(enemy.is_on_floor() and enemy.ground_speed_multiplier()==1,"reflected pool exempts grounded new owner")
    enemy.lose_stock();await process_frame
    check(get_nodes_in_group("goo_puddles").is_empty(),"new owner stock loss cleans reflected pool")
    # Contact slow uses no persistent status; grounded only, strongest not product.
    enemy.reset_fighter(Vector3(0,0.1,0),true);enemy.control_type="keyboard";enemy.player_index=1
    enemy.set_physics_process(true);await frames(12);enemy.set_physics_process(false)
    var a=pool(Vector3(0,0.025,0));pool(Vector3(0.1,0.025,0))
    check(enemy.is_on_floor() and enemy.ground_speed_multiplier()==0.65,"overlap strongest slow is 0.65, not 0.4225")
    key(KEY_D,true);enemy.set_physics_process(true);await frames(8)
    check(is_equal_approx(enemy.velocity.x,4.875),"actual keyboard movement reaches 65 percent of 7.5 speed")
    key(KEY_SPACE,true);await frames(2)
    check(enemy.velocity.y>10 and enemy.jumps_used==1 and enemy.ground_speed_multiplier()==1,"jump height/count unaffected and airborne recovers")
    key(KEY_D,false);key(KEY_SPACE,false)
    enemy.reset_fighter(Vector3(0,0.1,0));await frames(12);enemy.set_physics_process(false)
    caster.position=Vector3(0,0,0)
    check(caster.ground_speed_multiplier()==1,"owner excluded")
    caster.team_id=2;enemy.team_id=2
    check(enemy.ground_speed_multiplier()==1,"friendly excluded")
    caster.team_id=-1;enemy.team_id=-1
    enemy.shielding=true
    check(enemy.ground_speed_multiplier()==0.65,"shield does not erase environmental slow")
    enemy.shielding=false
    enemy.apply_freeze(caster)
    check(enemy.freeze_remaining>0 and enemy.ground_speed_multiplier()==0.65,"puddle does not shatter or replace freeze")
    enemy._tick_freeze(1.1)
    check(enemy.freeze_remaining==0 and enemy.ground_speed_multiplier()==0.65,"thaw returns to contact slow")
    enemy.velocity.y=2
    check(enemy.ground_speed_multiplier()==1,"rising jump excludes even stale floor flag")
    enemy.velocity.y=0;enemy.position.y=0.8
    check(enemy.ground_speed_multiplier()==1,"airborne over puddle excluded")
    enemy.position.y=0;enemy.position.x=3
    check(enemy.ground_speed_multiplier()==1,"leaving recovers immediately")
    enemy.position.x=0
    a.lifetime=0
    get_nodes_in_group("goo_puddles")[1].queue_free()
    check(enemy.ground_speed_multiplier()==1,"expiry and queued deletion clear without extra tick")
    await clear_effects()
    for i in 5:pool(Vector3(0,0.025,0))
    await process_frame
    check(get_nodes_in_group("goo_puddles").size()==3,"oldest evicted at three pools per owner")
    caster.reset_fighter(Vector3(12,0,0));await process_frame
    check(get_nodes_in_group("goo_puddles").is_empty(),"reset clears pools")
    caster.start_special(Vector2.LEFT);caster.start_special(Vector2.LEFT)
    check(get_nodes_in_group("projectiles").size()==1 and caster.attack_cooldown==0.55,"existing 0.55 cooldown bounds casts")
    await clear_effects()
    p=glob(Vector3(0,30,0));await frames(60)
    check(is_instance_valid(p) and p.travel<=4.5 and p.position.x<=4.501,"high throw horizontal travel capped")
    await frames(35)
    check(not is_instance_valid(p),"high throw expires without infinite falling")
    pool(Vector3(0,0.025,0));arena.show_setup()
    check(enemy.ground_speed_multiplier()==1,"menu immediately clears slow")
    await process_frame
    check(get_nodes_in_group("goo_puddles").is_empty(),"menu removes pools with stopped fighter physics")
    caster.controls_enabled=true;enemy.controls_enabled=true
    pool(Vector3(0,0.025,0));enemy.stocks=0
    arena._on_fighter_eliminated(enemy)
    check(arena.match_over and caster.ground_speed_multiplier()==1,"winner clears slow immediately")
    await process_frame
    check(get_nodes_in_group("goo_puddles").is_empty(),"winner cleans pools")
    arena.queue_free();await process_frame
    if failures==0:print("PASS: GGB goo platform/terrain/fighter/shield/freeze/Orb/air/team/stack/cap/TTL/cooldown/reset/menu")
    quit(1 if failures else 0)

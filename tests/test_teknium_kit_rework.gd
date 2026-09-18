extends SceneTree
var fails := 0
var checks := 0
var arena
var f
var target
func _initialize(): call_deferred("run")
func frames(n):
    for i in n:
        await physics_frame
        await process_frame
func check(ok, message):
    checks += 1
    print(("PASS: " if ok else "FAIL: ") + message)
    if not ok: fails += 1
func key(code, down):
    var e = InputEventKey.new()
    e.keycode = code; e.physical_keycode = code; e.pressed = down
    Input.parse_input_event(e); Input.flush_buffered_events()
func reset_case():
    for code in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_G,KEY_SPACE,KEY_E,KEY_F]: key(code,false)
    f.reset_fighter(Vector3(-2,0,0),true)
    target.reset_fighter(Vector3(8,0,0),true)
    await frames(15)
func run():
    arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
    var ids = load("res://scripts/match_config.gd").CHARACTERS
    for i in 2:
        arena.setup.rows[i].character.select(ids.find("teknium" if i == 0 else "doge_man"))
        arena.setup.rows[i].kind.select(0)
    arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
    arena.setup._refresh(); arena.setup._start(); await frames(150)
    f = arena.fighters[0]; target = arena.fighters[1]
    await reset_case()
    key(KEY_S,true); key(KEY_G,true); await frames(3)
    var kit = f.get_node_or_null("TekniumSpecials")
    check(kit != null and is_instance_valid(kit.get("grenade")),"Down+B tosses one live remote holy grenade through ordinary input")
    if kit:
        var grenade = kit.grenade
        await frames(140)
        check(is_instance_valid(grenade) and not grenade.is_queued_for_deletion(),"held Down+B never detonates; grenade has no timed fuse")
        key(KEY_G,false); await frames(2); key(KEY_G,true); await frames(2)
        check(not is_instance_valid(kit.grenade),"next fresh Down+B remotely detonates")
        key(KEY_G,false); await frames(35); key(KEY_G,true); await frames(2)
        check(is_instance_valid(kit.grenade),"next fresh press tosses new grenade")
        f.reset_fighter(Vector3.ZERO,true); await frames(2)
        check(not is_instance_valid(kit.grenade),"reset clears grenade and held input does not retoss")
    for code in [KEY_S,KEY_G]: key(code,false)
    await reset_case()
    key(KEY_G,true); await frames(32)
    check(f.charging and f.charge_time > 0.4,"neutral hold charges a projectile rather than grabbing")
    key(KEY_SPACE,true); await frames(2); key(KEY_SPACE,false)
    check(not f.charging and kit.get("stored_charge") != null and kit.get("stored_charge") > 0.4,"dedicated jump cancels and stores charge")
    key(KEY_G,false); await frames(45)
    key(KEY_G,true); await frames(2)
    check(f.charging and f.charge_time > 0.4,"stored charge resumes on next neutral hold")
    key(KEY_G,false); await frames(2)
    check(not f.charging and get_nodes_in_group("teknium_charge_shots").size() == 1,"release fires stored charge projectile")
    if get_nodes_in_group("teknium_charge_shots").size() == 1:
        var shot = get_nodes_in_group("teknium_charge_shots")[0]
        check(shot.payload_damage() > 8,"stored charge increases projectile damage")
    await reset_case()
    target.reset_fighter(Vector3(1,0,0),true); await frames(10)
    key(KEY_G,true); await frames(2); key(KEY_G,false); await frames(18)
    check(target.damage_percent >= 5 and target.damage_percent < 10,"tap fires smaller shot with real damage")
    await reset_case()
    target.reset_fighter(Vector3(-6,0,0),true); await frames(10)
    f.facing = 1
    key(KEY_G,true); await frames(2); key(KEY_G,false); await frames(35)
    check(target.damage_percent == 0,"charge projectile misses target behind shooter")
    await reset_case()
    key(KEY_W,true); key(KEY_G,true); await frames(3)
    check(kit.get("phase") == "rise_charge" and f.recovery_spent,"Up+B reserves recovery and charges before launch")
    var start_pos: Vector3 = f.global_position
    key(KEY_W,false); key(KEY_D,true); await frames(12)
    check(f.global_position.distance_to(start_pos) < 0.4,"recovery startup holds position while aiming")
    await frames(20)
    check(kit.get("phase") == "rise_burst" and f.velocity.x > 15 and absf(f.velocity.y) < 1,"startup direction re-aims burst horizontally")
    key(KEY_D,false); key(KEY_G,false); await frames(25)
    check(f.global_position.x-start_pos.x > 4 and f.global_position.x-start_pos.x < 8,"recovery displacement is bounded")
    await reset_case()
    f.reset_fighter(Vector3(-2,5,0),true); await frames(2)
    key(KEY_W,true); key(KEY_G,true); await frames(2); key(KEY_G,false); key(KEY_W,false)
    await frames(48)
    var before_y: float = f.global_position.y
    key(KEY_W,true); key(KEY_G,true); await frames(2)
    check(kit.get("phase") == "idle" and f.recovery_spent and f.global_position.y < before_y+0.5,"recovery cannot be used twice in air")
    key(KEY_W,false); key(KEY_G,false); await frames(100)
    check(not f.recovery_spent,"landing restores recovery")
    for direction in [-1,1]:
        await reset_case()
        f.facing = direction
        target.reset_fighter(Vector3(-2+direction*2.5,0,0),true); await frames(10)
        var origin: Vector3 = f.global_position
        var code = KEY_D if direction > 0 else KEY_A
        key(code,true); key(KEY_G,true); await frames(7)
        check(kit.get("phase") == "shadow_dash" and f.velocity.x*direction > 18,"side+B fast committed Shadow Kick facing "+str(direction))
        check(get_nodes_in_group("teknium_afterimages").size() > 0,"side dash leaves green posed afterimages "+str(direction))
        var view = f._visual_root.get_node("TekniumVisual")
        check(view.current_clip == "humanoid_air_neutral/Neutral","side dash holds existing extended-leg kick, not a run")
        key(code,false); await frames(22)
        check(target.damage_percent == 13,"dash swept damage hits target once "+str(direction))
        check((f.global_position.x-origin.x)*direction > 1 and (f.global_position.x-origin.x)*direction < 8,"bounded controller-root dash "+str(direction))
        await frames(30)
        check(kit.get("phase") == "idle" and get_nodes_in_group("teknium_afterimages").is_empty(),"held side special cannot restart and trails expire")
    await reset_case()
    target.reset_fighter(Vector3(-5,0,0),true); await frames(10)
    key(KEY_D,true); key(KEY_G,true); await frames(20); key(KEY_D,false); key(KEY_G,false)
    check(target.damage_percent == 0,"shadow kick misses behind")
    for direction in [-1,1]:
        await reset_case()
        f.facing=direction
        f.start_special(Vector2.DOWN)
        var g = kit.grenade
        check(is_instance_valid(g) and g.velocity.x*direction>0,"grenade toss follows facing "+str(direction))
        await frames(50)
        target.reset_fighter(Vector3(g.global_position.x+0.5,0,0),true); await frames(10)
        var damage_before: float = target.damage_percent
        f.start_special(Vector2.DOWN); await frames(2)
        check(target.damage_percent-damage_before==16,"remote blast damages nearby opponent once "+str(direction))
        await frames(20)
        check(target.damage_percent==16,"blast visual cannot repeat damage")
    await reset_case()
    f.start_special(Vector2.DOWN); await frames(35)
    f.start_special(Vector2.DOWN); await frames(2)
    check(target.damage_percent==0,"remote blast misses outside radius")
    await reset_case()
    f.reset_fighter(Vector3(-2,2,0),true)
    target.reset_fighter(Vector3(0.5,2,0),true); target.set_physics_process(false)
    key(KEY_W,true); key(KEY_G,true); await frames(2); key(KEY_W,false); key(KEY_D,true); await frames(26)
    check(kit.get_node_or_null("HolyTechCue") != null,"recovery has visible holy-tech charge/burst cue")
    key(KEY_D,false); key(KEY_G,false); await frames(16)
    check(target.damage_percent==12,"recovery burst swept once-target contact deals damage")
    target.set_physics_process(true)
    # Wall test uses physical terrain, not a teleported clamp.
    await reset_case()
    var wall = StaticBody3D.new(); var wc=CollisionShape3D.new(); var box=BoxShape3D.new()
    box.size=Vector3(0.25,8,4); wc.shape=box; wall.add_child(wc); arena.add_child(wall); wall.position=Vector3(0,3,0)
    target.reset_fighter(Vector3(1,0,0),true); await frames(5)
    key(KEY_D,true); key(KEY_G,true); await frames(22); key(KEY_D,false); key(KEY_G,false)
    check(f.global_position.x < -0.4 and target.damage_percent==0,"Shadow Kick stops at stage wall and cannot hit through it")
    wall.queue_free(); await frames(2)
    for mode in ["hit","freeze","disable","stock","reset"]:
        await reset_case()
        key(KEY_D,true); key(KEY_G,true); await frames(7)
        if mode=="hit": f.receive_hit_from(2,Vector3.LEFT,1,target)
        elif mode=="freeze": f.apply_freeze(target)
        elif mode=="disable": f.controls_enabled=false
        elif mode=="stock": f.lose_stock()
        else: f.reset_fighter(Vector3(-2,0,0),true)
        await frames(2)
        check(kit.phase=="idle" and get_nodes_in_group("teknium_afterimages").is_empty(),"interrupt clears dash and ghosts "+mode)
    await reset_case()
    f.start_special(Vector2.ZERO); f.advance_charge(1.5); kit.store(); f.start_special(Vector2.DOWN)
    f.lose_stock(); await frames(2)
    check(kit.stored_charge==0 and not is_instance_valid(kit.grenade),"stock loss clears charge and remote grenade")
    await reset_case()
    key(KEY_G,true); await frames(100); key(KEY_E,true); await frames(2)
    check(kit.stored_charge==f.MAX_CHARGE_TIME and not f.charging,"shield stores full charge without auto-fire")
    key(KEY_G,false); key(KEY_E,false); await frames(2)
    f.start_special(Vector2.ZERO); f.cancel_touch_charge(); await frames(2)
    check(not f.charging and kit.stored_charge==f.MAX_CHARGE_TIME,"touch cancellation stores instead of firing")
    arena.queue_free(); await frames(2)
    print("TEKNIUM_KIT_COMPLETE checks=%d failures=%d" % [checks,fails])
    quit(1 if fails else 0)

extends SceneTree
var fails = 0
var checks = 0
var arena
var f
func _initialize(): call_deferred("run")
func frames(n):
    for i in n:
        await physics_frame
        await process_frame
func check(ok, message):
    checks += 1
    print(("PASS: " if ok else "FAIL: ")+message)
    if not ok: fails += 1
func key(code, down):
    var e = InputEventKey.new()
    e.keycode=code; e.physical_keycode=code; e.pressed=down
    Input.parse_input_event(e); Input.flush_buffered_events()
func reset_case():
    for code in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_G,KEY_SPACE,KEY_E,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_ENTER,KEY_L,KEY_O]: key(code,false)
    for other in arena.fighters:
        if other!=f: other.reset_fighter(Vector3(4,0.2,0),true)
    await frames(2)
    f.reset_fighter(Vector3(-2,0.2,0),true)
    await frames(25)
func joy_button(code,down):
    var event=InputEventJoypadButton.new(); event.device=0; event.button_index=code; event.pressed=down
    Input.parse_input_event(event); Input.flush_buffered_events()
func touch(index,point,down):
    var event=InputEventScreenTouch.new(); event.index=index; event.position=root.get_final_transform()*point; event.pressed=down
    Input.parse_input_event(event); Input.flush_buffered_events()
func run():
    arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); current_scene=arena; await process_frame
    var ids=load("res://scripts/match_config.gd").CHARACTERS
    for i in 2:
        arena.setup.rows[i].character.select(ids.find("teknium")); arena.setup.rows[i].kind.select(0)
    arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
    arena.setup._refresh(); arena.setup._start(); await frames(150)
    for player in 2:
        f=arena.fighters[player]
        arena.fighters[1-player].reset_fighter(Vector3(4,0.2,0),true)
        var special=KEY_G if player==0 else KEY_L
        var directions=[KEY_A,KEY_D,KEY_W,KEY_S,KEY_SPACE] if player==0 else [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_ENTER]
        for code in directions:
            await reset_case()
            key(special,true); await frames(16); key(code,true); await frames(2)
            check(not f.charging and f.teknium_specials.stored_charge>0.15,"fresh store P%d key %d"%[player+1,code])
            check(get_nodes_in_group("teknium_charge_shots").is_empty(),"store does not fire")
            if code in [KEY_W,KEY_UP,KEY_SPACE,KEY_ENTER]: check(f.velocity.y>0,"Up/dedicated Jump stores+jumps")
            await frames(4)
            check(not f.charging and f.teknium_specials.phase=="idle","held Special no phantom")
        for code in directions.slice(0,4):
            await reset_case(); key(code,true); key(special,true); await frames(2)
            check(not f.charging and f.teknium_specials.stored_charge==0,"initial directional Special keeps original route")
            check(f.last_move in ["SHADOW KICK","HOLY IGNITION","HOLY HAND GRENADE"],"directional route identity "+f.last_move)
        await reset_case()
        key(directions[4],true); key(special,true); await frames(8)
        check(f.charging,"initial Jump+neutral Special charges; held Jump is not fresh")
        key(directions[4],false); await frames(2); key(directions[4],true); await frames(2)
        check(not f.charging and f.velocity.y>0,"repressed dedicated Jump stores+jumps")
        await reset_case(); key(special,true); await frames(12)
        key(special,false); key(directions[3],true); await frames(2)
        check(not f.charging and f.teknium_specials.stored_charge>0 and get_nodes_in_group("teknium_charge_shots").is_empty(),"same-tick release+direction stores before firing")
        await reset_case(); key(special,true); await frames(12)
        key(directions[0],true); key(directions[1],true); await frames(2)
        check(not f.charging and f.teknium_specials.stored_charge>0,"opposed fresh directions store without choosing attack")
        f.reset_fighter(Vector3(-2,0,0),true); await frames(3)
        check(not f.charging and f.teknium_specials.stored_charge==0 and f.teknium_specials.phase=="idle","reset clears stored charge and latches held Special")
        await reset_case()
    f=arena.fighters[0]; f.input_device=0
    await reset_case()
    joy_button(JOY_BUTTON_B,true); await frames(12)
    var axis=InputEventJoypadMotion.new(); axis.device=0; axis.axis=JOY_AXIS_LEFT_X; axis.axis_value=-0.8
    Input.parse_input_event(axis); Input.flush_buffered_events(); await frames(3)
    check(not f.charging and f.teknium_specials.stored_charge>0 and f.velocity.x<0,"synthetic stick fresh-left stores+moves")
    joy_button(JOY_BUTTON_B,false); axis=axis.duplicate(); axis.axis_value=0; Input.parse_input_event(axis); Input.flush_buffered_events()
    await reset_case(); joy_button(JOY_BUTTON_B,true); await frames(12); joy_button(JOY_BUTTON_DPAD_UP,true); await frames(2)
    check(not f.charging and f.velocity.y>0,"synthetic D-pad Up stores+jumps")
    joy_button(JOY_BUTTON_B,false); joy_button(JOY_BUTTON_DPAD_UP,false); f.input_device=-1
    await reset_case()
    var mobile=root.get_node("MobileTouch")
    var zones=mobile.regions(root.get_visible_rect().size)
    touch(0,zones.special,true); await frames(12)
    check(f.charging,"touch Special charges via actual provider")
    touch(1,zones.pad+Vector2(0,-70),true); await frames(2)
    check(not f.charging and f.teknium_specials.stored_charge>0 and f.velocity.y>0,"touch fresh Up stores+jumps")
    await frames(4); check(not f.charging and f.teknium_specials.phase=="idle","touch held Special no phantom")
    touch(1,zones.pad,false); touch(0,zones.special,false); await frames(2)
    touch(0,zones.special,true); await frames(2)
    check(f.charging and f.charge_time>0.1,"touch fresh Special resumes")
    touch(0,zones.special,false); await frames(2)
    check(get_nodes_in_group("teknium_charge_shots").size()==1,"touch release fires")
    print("EDGES_COMPLETE checks=%d fails=%d"%[checks,fails]); quit(1 if fails else 0)

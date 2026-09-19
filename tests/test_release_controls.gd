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
func run():
    arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
    var ids=load("res://scripts/match_config.gd").CHARACTERS
    for i in 2:
        arena.setup.rows[i].character.select(ids.find("teknium")); arena.setup.rows[i].kind.select(0)
    arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
    arena.setup._refresh(); arena.setup._start(); await frames(150)
    for i in 2:
        f=arena.fighters[i]
        var shield=KEY_E if i==0 else KEY_O
        var right=KEY_D if i==0 else KEY_RIGHT
        key(shield,true); key(right,true); await frames(3)
        check(not f._read_raw_controls(0).shield,"retired keyboard shield P"+str(i+1))
        check(not f.shielding and not f._shield_visual.visible,"no generic state or visual P"+str(i+1))
        check(f.velocity.x>0,"old shield key cannot lock movement P"+str(i+1))
        var damage=f.damage_percent
        f.receive_hit(10,Vector3(1,0.2,0),3)
        check(is_equal_approx(f.damage_percent-damage,10),"full damage with retired key P"+str(i+1))
        key(shield,false); key(right,false)
    f=arena.fighters[0]
    f.reset_fighter(Vector3(-2,0,0),true)
    arena.fighters[1].reset_fighter(Vector3(0,0,0),true)
    f.bot_difficulty="hard"
    arena.fighters[1].attack_cooldown=1
    var bot=load("res://scripts/bot_controller.gd").new()
    bot.sequence=3
    check(not bot.read(f,0).shield,"bot never requests universal shield")
    f.input_device=0
    var joy=InputEventJoypadButton.new(); joy.device=0; joy.button_index=JOY_BUTTON_LEFT_SHOULDER; joy.pressed=true
    Input.parse_input_event(joy); Input.flush_buffered_events()
    check(not f._read_raw_controls(0).shield,"synthetic shoulder ignored")
    joy=joy.duplicate(); joy.pressed=false; Input.parse_input_event(joy); Input.flush_buffered_events(); f.input_device=-1
    f.reset_fighter(Vector3(-2,0,0),true); arena.fighters[1].reset_fighter(Vector3(8,0,0),true); await frames(15)
    key(KEY_G,true); await frames(20)
    check(f.charging,"ordinary neutral hold underway")
    key(KEY_D,true); await frames(3)
    check(not f.charging and f.teknium_specials.stored_charge>0.2,"fresh right stores charge")
    check(f.velocity.x>0,"storage permits horizontal movement")
    await frames(5)
    check(f.teknium_specials.phase=="idle" and not f.charging,"held Special cannot follow storage")
    key(KEY_D,false); key(KEY_G,false); await frames(2)
    key(KEY_G,true); await frames(2)
    check(f.charging and f.charge_time>0.2,"fresh neutral resumes stored charge")
    key(KEY_G,false); await frames(2)
    check(not f.charging and get_nodes_in_group("teknium_charge_shots").size()==1,"uncancelled release fires")
    print("CONTROLS_COMPLETE checks=%d fails=%d"%[checks,fails])
    quit(0 if fails==0 else 1)

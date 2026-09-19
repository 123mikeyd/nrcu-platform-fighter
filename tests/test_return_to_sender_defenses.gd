extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String):
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: "+label)
func _initialize(): call_deferred("run")
func make(id: String):
    var f = load("res://scripts/fighter.gd").new()
    f.character_id = id
    root.add_child(f)
    f.set_physics_process(false)
    return f
func run():
    var source = make("teknium")
    var doge = make("doge_man")
    var witch = make("witcheer")
    for victim in [doge,witch]:
        victim._handle_blast_zone()
        victim.revival.tick(0.3,victim.read_controls(0))
        victim.revival.tick(2.4,victim.read_controls(0))
        victim.damage_percent = 50
        if victim == doge:
            victim.doge_counter.start()
            victim.doge_counter.elapsed = 0.2
        else:
            victim._start_witcheer("Celebration")
            victim.witcheer_absorbing = true
            victim.witcheer_elapsed = float(victim.witcheer_moves.Celebration.contact_time)+0.02
        for id in ["projectile","goo_projectile","fire_projectile","teknium_force_projectile","teknium_charge_shot"]:
            var projectile = load("res://scripts/"+id+".gd").new()
            projectile.source = source
            root.add_child(projectile)
            projectile.set_physics_process(false)
            check(not projectile._try_absorb(victim),"protected target cannot absorb/heal/counter "+victim.character_id+" "+id)
            projectile._hit_target(victim)
            check(victim.damage_percent == 50,"protected projectile leaves percent unchanged "+id)
            check(victim.freeze_remaining == 0 and (victim.burn == null or victim.burn.remaining == 0),"protected projectile cannot add status "+id)
            projectile.free()
        check(victim != doge or doge.doge_counter.phase != "hook","protected Doge never retaliates")
        source.global_position = victim.global_position - Vector3(1.2,0,0)
        source.facing = 1
        source.teknium_magic.capture()
        check(not is_instance_valid(victim.caught_by),"electric grab cannot capture protected target")
        victim._clear_move_state()
    # Direct source-less hit must not reach a primed counter either.
    doge._begin_revival()
    doge.doge_counter.start()
    doge.doge_counter.elapsed = 0.2
    doge.receive_hit(30,Vector3.RIGHT,5)
    check(doge.doge_counter.phase != "hook","source-less hit rejected before counter")
    # Bot consumes identical hold and can leave on its ordinary movement intent.
    source._clear_move_state()
    source.control_type = "bot"
    source._begin_revival()
    source.revival.tick(0.3,source.read_controls(0))
    source.revival.tick(0.5,source.read_controls(0))
    check(source.revival.phase == "idle" or source.revival.elapsed < source.revival.platform_seconds,"bot uses same bounded hold")
    source.revival.tick(2.5,source.read_controls(0))
    check(source.revival.phase == "idle","bot always leaves by timeout")
    # Held special through revival is latched, never silently charged/fired.
    source.control_type = "human"
    source.input_device = 0
    source.reset_fighter(Vector3.ZERO,true)
    source._begin_revival()
    var intent = source.read_controls(0)
    intent.special = true
    source.revival.tick(0.3,intent)
    source.revival.tick(0.5,intent)
    check(source._special_was_down and not source.charging,"held special is latched through orientation")
    # Gamepad horizontal state follows the same shared hold/depart API.
    var joy := InputEventJoypadMotion.new()
    joy.device = 0
    joy.axis = JOY_AXIS_LEFT_X
    joy.axis_value = 1.0
    Input.parse_input_event(joy)
    Input.flush_buffered_events()
    source._physics_process(1.0/60)
    check(source.revival.phase == "idle" and source.is_revival_protected(),"gamepad horizontal input departs")
    var release: InputEventJoypadMotion = joy.duplicate()
    release.axis_value = 0
    Input.parse_input_event(release)
    for f in [source,doge,witch]: f.free()
    print("RETURN_TO_SENDER_DEFENSES_COMPLETE checks=%d failures=%d" % [checks,failures])
    quit(1 if failures else 0)

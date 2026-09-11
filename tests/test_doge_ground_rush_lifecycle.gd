extends "res://tests/test_doge_ground_rush_safety.gd"
func key(code: int, down: bool) -> void:
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func run() -> void:
    stage = Node3D.new()
    root.add_child(stage)
    floor_at(Vector3(0,-0.5,0),Vector3(30,1,4))
    f = F.new()
    target = F.new()
    stage.add_child(f)
    stage.add_child(target)
    await reset(Vector3.ZERO,1,Vector3(12,0,0))
    f.player_index = 1
    key(KEY_S,true)
    key(KEY_G,true)
    await step(160)
    check(f.charging and f.charge_time == 2.25,"cap and hold without auto release")
    check(f.position.distance_to(Vector3.ZERO)<0.002,"charge is planted full duration")
    check(f.get_node("VisualRoot/DogeVisual").current_clip=="GroundCharge","source charge clip shown")
    key(KEY_G,false)
    key(KEY_S,false)
    key(KEY_E,true)
    key(KEY_A,true)
    await step(2)
    check(not f.shielding,"rush has no shield armor")
    check(f.facing==1 and f.velocity.x>0,"rush facing locked despite opposite direction")
    check(not f.try_jump(),"direct jump gated during rush")
    f.basic_attack(Vector2.ZERO,false)
    f.start_special(Vector2.UP)
    check(f.doge_attack_clip.is_empty() and not f.recovery_spent,"direct attack/special gated")
    key(KEY_E,false)
    key(KEY_A,false)
    await step(44) # Full-charge rush now lasts .75 seconds.
    check(f.doge_ground_rush.phase=="recovery","finite rush enters recovery")
    check(not f.try_jump(),"direct jump gated during recovery")
    await step(20)
    check(f.doge_ground_rush.phase=="idle" and f.try_jump(),"bounded recovery unlocks jump")
    await step(1)
    f.start_special(Vector2.DOWN)
    check(not f.charging,"air down retains original no-op fallback")
    for phase in ["charge","rush","recovery"]:
        for interrupt in ["hit","freeze","grab","stock","reset","disable"]:
            await reset(Vector3.ZERO,1,Vector3(12,0,0))
            f.start_special(Vector2.DOWN)
            if phase != "charge":
                f.advance_charge(2.25)
                f.release_special()
                if phase == "recovery": await step(46)
            check(f.doge_ground_rush.phase==phase,"fixture "+phase)
            if interrupt=="hit": f.receive_hit(5,Vector3(-1,1,0),5)
            elif interrupt=="freeze": f.apply_freeze(target)
            elif interrupt=="grab": f.cancel_for_grab()
            elif interrupt=="stock": f.lose_stock()
            elif interrupt=="reset": f.reset_fighter(Vector3.ZERO,true)
            else: f.controls_enabled=false
            check(f.doge_ground_rush.phase=="idle" and not f.charging and f.doge_ground_rush.targets.is_empty(),phase+" cleared by "+interrupt)
            var damage: float = target.damage_percent
            f.release_special()
            await step(4)
            check(target.damage_percent==damage,"no stale release hit "+interrupt)
    await reset(Vector3.ZERO,1,Vector3(12,0,0))
    f.player_index=1
    f.controls_enabled=false
    key(KEY_S,true)
    key(KEY_G,true)
    await step(3)
    f.controls_enabled=true
    await step(2)
    check(not f.charging,"controls unlock latches held G; no accidental activation")
    key(KEY_G,false)
    key(KEY_S,false)
    await step(2)
    f.controls_enabled=false
    key(KEY_G,true)
    await step(2)
    f.controls_enabled=true
    await step(2)
    check(not f.charging,"neutral G held through setup also latched")
    key(KEY_G,false)
    print("GROUND_RUSH_LIFECYCLE_CHECKS ",checks," failures ",failures)
    stage.queue_free()
    await process_frame
    if not failures: print("PASS rush cap held facing vulnerability interruption lifecycle input gates")
    quit(1 if failures else 0)

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
    floor_at(Vector3(0,-0.5,0),Vector3(20,1,4))
    floor_at(Vector3(0,2.75,0),Vector3(2,0.5,4),true)
    f=F.new()
    target=F.new()
    stage.add_child(f)
    stage.add_child(target)
    for face in [1,-1]:
        for shield in [false,true]:
            await reset(Vector3(-2*face,0,0),face,Vector3.ZERO)
            target.set_physics_process(false)
            target.shielding=shield
            launch()
            await step(55)
            check(is_equal_approx(target.damage_percent,4.9 if shield else 14),"single hit with existing shield math")
            check(f.position.x*face<0,"solid opponent capsules retained")
        await reset(Vector3(-2*face,0,0),face,Vector3.ZERO)
        f.team_id=0
        target.team_id=0
        target.set_physics_process(false)
        launch()
        await step(55)
        check(target.damage_percent==0,"allies not damaged")
        check(f.doge_ground_rush.terrain_ray(Vector3(0,1,0),Vector3(0,-0.1,0)).get("collider") != target,"terrain query excludes overlapping ally")
    await reset(Vector3(-3,0,0),1,Vector3(-1,0,0))
    var second = F.new()
    second.character_id="doge_man"
    second.player_index=4
    second.position=Vector3(1,0,0)
    stage.add_child(second)
    await step(5)
    launch()
    await step(55)
    check(target.damage_percent==14 and second.damage_percent==14,"multi opponents each once per activation")
    second.queue_free()
    await process_frame
    await reset(Vector3(-2,0,0),1,Vector3.ZERO)
    target.set_physics_process(false)
    f.start_special(Vector2.DOWN)
    f.advance_charge(2.25)
    # Physics is deliberately disabled for this direct API charge interval.
    f.set_physics_process(false)
    await step(15)
    check(target.damage_percent==0,"charge interval never damages")
    f.receive_hit(5,Vector3(1,1,0),5)
    check(f.damage_percent==5 and f.doge_ground_rush.phase=="idle","charge vulnerable; no armor")
    f.release_special()
    check(target.damage_percent==0,"hit cancellation cannot release damage")
    for rate in [15,10]:
        Engine.physics_ticks_per_second=rate
        for face in [1,-1]:
            await reset(Vector3(0,3,0),face,Vector3(-6*face,0,0))
            f.player_index=1
            key(KEY_S,true)
            key(KEY_G,true)
            await step(2)
            check(f.charging and f.is_grounded() and f._drop_time==0,"native Down+G chord cannot drop thin platform")
            f.advance_charge(2.25)
            key(KEY_G,false)
            await step(1)
            check(not f.try_drop_through(),"direct drop blocked during committed rush/recovery")
            await step(11)
            key(KEY_S,false)
            check(f.is_grounded() and absf(f.position.x)<=0.431,"max charge large physics steps stop before narrow ledge "+str(rate))
            check(f.doge_ground_rush.phase=="idle","edge recovery finishes at low physics rate")
    Engine.physics_ticks_per_second=60
    await reset(Vector3(0,1.8,0),1,Vector3.ZERO)
    f.recovery_spent=true
    f.jumps_used=2
    f.start_special(Vector2.DOWN)
    check(not f.charging and not f.is_grounded(),"fighter head cannot grant ground rush")
    await step(2)
    check(f.recovery_spent and f.jumps_used==2,"head contact cannot refund air resources")
    await reset(Vector3(-3,0,0),1,Vector3(3,0,0))
    f.control_type="bot"
    f._bot.timer=100
    f._bot.intent={"left":false,"right":false,"up":false,"down":true,"jump":false,"attack":false,"special":true,"shield":false}
    await step(2)
    check(f.charging,"actual bot intent uses same grounded charge route")
    f._bot.intent.special=false
    await step(2)
    check(f.doge_ground_rush.phase=="rush","bot special release uses latched down route")
    f.apply_freeze(target)
    f._bot.intent.special=true
    await step(5)
    check(f.doge_ground_rush.phase=="idle" and f.freeze_remaining>0,"frozen bot cannot resume rush")
    await reset(Vector3(8.8,0,0),1,Vector3(-6,0,0))
    launch()
    await step(1)
    f.receive_hit(5,Vector3(1,0.2,0),12)
    await step(25)
    check(f.doge_ground_rush.phase=="idle" and not f.is_grounded() and f.velocity.y<0,"external hit off edge cancels rush with real gravity")
    print("GROUND_RUSH_ROBUSTNESS_CHECKS ",checks," failures ",failures)
    stage.queue_free()
    await process_frame
    if not failures: print("PASS rush teams shields multi opponents vulnerability thin ledges low FPS")
    quit(1 if failures else 0)

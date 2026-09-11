extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func frames(count:int):
    for i in count: await physics_frame
    await process_frame
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.setup.rows[0].character.select(4)
    arena.setup._start()
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    var mage=arena.fighters[0]
    var target=arena.fighters[1]
    for f in arena.fighters:
        f.set_physics_process(false)
        f.position=Vector3(12,8,0)
    mage.position=Vector3(-3,0,0)
    target.position=Vector3(0,0,0)
    target.character_id="turbofit"
    # Actual Orb reflection, then production projectile physics back into caster.
    mage.start_special(Vector2.RIGHT)
    mage._tick_character_move(0.2)
    if get_nodes_in_group("projectiles").is_empty():
        printerr("FAIL: post-Go cast did not create a projectile");arena.queue_free();await process_frame;quit(1);return
    var bolt=get_nodes_in_group("projectiles")[0]
    bolt.position=target.position+Vector3(-0.95,1,0)
    target.sound_orb_time=0.55
    target._tick_sound_orb(0)
    check(bolt.source==target and bolt.direction==-1 and bolt.freeze_bolt,"Sound Orb transfers owner and retains freeze property")
    check(bolt._visual.rotation.z>0,"reflected crystal points along reflected travel")
    await frames(12)
    check(mage.freeze_remaining>0 and mage.damage_percent==4,"reflected bolt freezes original caster")
    check(target.freeze_remaining==0,"reflection excludes new owner")
    mage.reset_fighter(Vector3(-3,0,0))
    target.reset_fighter(Vector3(0,0,0))
    target.shielding=true
    mage.start_special(Vector2.ZERO)
    mage._tick_character_move(0.2)
    await frames(14)
    check(target.freeze_remaining==0 and is_equal_approx(target.damage_percent,1.4),"shield blocks actual bolt freeze, shared 35% chip retained")
    target.shielding=false
    target.reset_fighter(Vector3(0,0,0))
    mage.reset_fighter(Vector3(-3,0,0))
    mage.team_id=0
    target.team_id=0
    mage.start_special(Vector2.ZERO)
    mage._tick_character_move(0.2)
    await frames(18)
    check(target.damage_percent==0 and target.freeze_remaining==0,"friendly bolt physically passes teammate without damage/status")
    for p in get_nodes_in_group("projectiles"): p.queue_free()
    await process_frame
    mage.team_id=-1
    target.team_id=-1
    mage.reset_fighter(Vector3(-3,0,0))
    target.reset_fighter(Vector3(0,0,0))
    target.control_type="bot"
    target.apply_freeze(mage)
    target.set_physics_process(true)
    var x:float=target.position.x
    await frames(20)
    check(absf(target.position.x-x)<0.01 and target.attack_cooldown==0,"real bot intents cannot move or attack while frozen")
    target.set_physics_process(false)
    target.receive_hit(0,Vector3.RIGHT,7)
    check(target.freeze_remaining>0,"zero-damage utility push does not shatter")
    target.receive_hit(4,Vector3.RIGHT,1)
    check(target.freeze_remaining==0 and not target.apply_freeze(mage),"damaging bolt shatters without resetting freeze")
    mage.reset_fighter(Vector3(-3,0,0))
    mage.start_special(Vector2.ZERO)
    mage._tick_character_move(0.2)
    mage.attack_cooldown=0
    mage.start_special(Vector2.RIGHT)
    mage._tick_character_move(0.2)
    check(get_nodes_in_group("projectiles").size()==1,"dedicated 1.6-second cast cooldown cannot be bypassed by basic cooldown")
    mage.lose_stock()
    await process_frame
    check(get_nodes_in_group("projectiles").is_empty(),"stock loss removes owned freeze bolts")
    target.reset_fighter(Vector3.ZERO)
    target.apply_freeze(mage)
    arena.show_setup()
    check(target.freeze_remaining==0,"setup clears freeze immediately even if physics is stopped")
    arena.queue_free()
    await process_frame
    if failures==0: print("PASS: actual Orb reflection/hit, shield chip, friendly sweep, bot lock, zero/damaging hit semantics, cast cooldown, stock projectile and immediate setup cleanup")
    quit(1 if failures else 0)

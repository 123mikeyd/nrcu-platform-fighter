extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
var checks := 0
var dog
var foe
func check(ok: bool, label: String):
    checks += 1
    if not ok:
        failures += 1
        printerr("FAIL: " + label)
func key(code: int, down: bool):
    var ev := InputEventKey.new()
    ev.keycode = code; ev.pressed = down
    Input.parse_input_event(ev); Input.flush_buffered_events()
func step(t: float):
    var left := t
    while left > 0.000001:
        var dt := minf(left,0.01)
        await physics_frame
        dog._physics_process(dt)
        left -= dt
func fresh(face := 1.0):
    key(KEY_S,false); key(KEY_G,false)
    dog.reset_fighter(Vector3.ZERO,true)
    foe.reset_fighter(Vector3(face*2.5,0,0),true)
    dog.facing = face
    await step(0.1)
func _initialize(): call_deferred("run")
func run():
    var floor_body := StaticBody3D.new()
    var col := CollisionShape3D.new()
    var box := BoxShape3D.new(); box.size = Vector3(100,1,5)
    col.shape = box; floor_body.add_child(col); floor_body.position.y = -0.5
    root.add_child(floor_body)
    dog = F.new(); dog.character_id = "doge_man"; root.add_child(dog); dog.set_physics_process(false)
    foe = F.new(); foe.character_id = "teknium"; foe.collision_layer = 2; root.add_child(foe); foe.set_physics_process(false)
    await fresh()
    key(KEY_S,true); key(KEY_G,true); await step(0.01)
    check(dog.last_move == "TYSON COUNTER", "real down-special enters counter instead of bull charge")
    if dog.get("doge_counter") == null:
        finish(); return
    await step(0.15)
    dog.receive_hit_from(10,Vector3.LEFT,4,foe)
    check(dog.damage_percent == 0, "active counter blocks incoming melee")
    await step(0.3)
    check(foe.damage_percent == 15, "connected retaliation scales incoming damage by 1.5")
    await coverage()
    finish()
func coverage():
    for face in [1.0,-1.0]:
        for spacing in [1.3,2.8,6.0,-2.0]:
            await fresh(face)
            foe.global_position.x = spacing*face
            key(KEY_S,true); key(KEY_G,true); await step(0.16)
            var whooshes: int = dog.doge_counter.whoosh_count
            var impacts: int = dog.doge_counter.impact_count
            dog.receive_contact_hit(8,Vector3(-face,0,0),4,dog.global_position+Vector3.UP,"body")
            check(dog.damage_percent == 0 and dog.hitstun == 0, "body-contact block face%s" % face)
            check(dog.doge_counter.whoosh_count == whooshes+1, "trigger whoosh once")
            await step(0.18)
            var connects: bool = spacing > 0 and spacing < 3
            check(is_equal_approx(foe.damage_percent,12 if connects else 0), "directional short reach face%s spacing%s damage%s" % [face,spacing,foe.damage_percent])
            check((dog.counter_hitstop > 0) == connects and (foe.counter_hitstop > 0) == connects, "both-fighter hitstop only on connect")
            check(dog.doge_counter.impact_count == impacts+(1 if connects else 0), "impact only on connect")
            if connects:
                check(foe.velocity.x*face > 7, "strong directional knockback")
                check(foe.get_node("VisualRoot/TekniumVisual").animation_player.speed_scale == 0,"victim skeleton paused during hitstop")
                var clock: float = dog.doge_counter.elapsed
                await step(0.03)
                check(dog.doge_counter.elapsed == clock,"hitstop pauses combat clock")
            await step(1)
            check(is_equal_approx(foe.damage_percent,12 if connects else 0),"no duplicate retaliation")
            check(dog.doge_counter.phase == "idle" and not dog.doge_counter.pressure.visible,"finite cleanup; held G never repeats")
    for boundary in [0.0,0.11999,0.12,0.41999,0.42,0.6]:
        await fresh()
        dog.start_special(Vector2.DOWN)
        dog.doge_counter.elapsed = boundary
        dog.receive_hit_from(6,Vector3.LEFT,3,foe)
        var blocked: bool = boundary >= 0.12 and boundary < 0.42
        check((dog.damage_percent == 0) == blocked,"exact defense boundary %.5f" % boundary)
        check((dog.doge_counter.phase == "hook") == blocked,"boundary trigger %.5f" % boundary)
    await fresh()
    key(KEY_S,true); key(KEY_G,true); await step(0.45)
    check(dog.doge_counter.phase == "stance" and not dog.doge_counter.active(),"punishable whiff recovery")
    check(not dog.try_jump(),"cannot jump-cancel recovery")
    dog.basic_attack(Vector2.ZERO,false)
    check(dog.doge_attack_clip.is_empty(),"cannot attack-cancel recovery")
    dog.receive_hit_from(7,Vector3.LEFT,4,foe)
    check(dog.damage_percent == 7 and dog.doge_counter.phase == "idle","recovery punished normally")
    for interruption in ["reset","stock","disable","freeze","grab","second_hit"]:
        await fresh()
        key(KEY_S,true); key(KEY_G,true); await step(0.16)
        if interruption == "reset": dog.reset_fighter(Vector3.ZERO,true)
        elif interruption == "stock": dog.lose_stock()
        elif interruption == "disable": dog.controls_enabled = false
        elif interruption == "freeze": dog.apply_freeze(foe)
        elif interruption == "grab": dog.cancel_for_grab()
        else:
            dog.receive_hit_from(5,Vector3.LEFT,2,foe)
            dog.receive_hit_from(5,Vector3.LEFT,2,foe)
        check(dog.doge_counter.phase == "idle" and not dog.doge_counter.pressure.visible,"synchronous cancel "+interruption)
        await step(0.8)
        check(foe.damage_percent == 0,"no stale retaliation "+interruption)
    for damage in [4.0,16.0,24.0]:
        await fresh()
        dog.start_special(Vector2.DOWN); await step(0.16)
        dog.receive_hit_from(damage,Vector3.LEFT,4,foe); await step(0.3)
        check(is_equal_approx(foe.damage_percent,damage*1.5),"scaled incoming %s" % damage)
    await fresh()
    dog.start_special(Vector2.DOWN); await step(0.16)
    foe.shielding = true
    dog.receive_hit_from(10,Vector3.LEFT,4,foe); await step(0.18)
    check(dog.counter_hitstop == 0 and foe.counter_hitstop == 0,"shielded retaliation has no big-impact hitstop")
    await fresh()
    foe.global_position.x = 10
    var legacy = F.new(); legacy.character_id = "doge_man"; root.add_child(legacy); legacy.set_physics_process(false)
    legacy.global_position = Vector3(2.5,0,0)
    dog.start_special(Vector2.DOWN); await step(0.16)
    dog.receive_hit_from(10,Vector3.LEFT,4,legacy); await step(0.3)
    check(legacy.damage_percent == 15,"legacy capsule fighter contact; no anatomy pilot required")
    legacy.queue_free(); await process_frame
    # Imported v003 full interval is still the original one-second resource.
    check(is_equal_approx(dog.get_node("VisualRoot/DogeVisual").animation_player.get_animation("TysonTwoPiece").length,1.0),"installed Tyson interval 0..60 at60fps")
    for negative in ["friendly","shield","expired","visual_fade"]:
        await fresh()
        dog.start_special(Vector2.DOWN); await step(0.16)
        var shot = load("res://scripts/turbofit_sound_wave.gd" if negative == "visual_fade" else "res://scripts/projectile.gd").new()
        shot.source = foe; root.add_child(shot); shot.set_physics_process(false)
        if negative == "friendly": dog.team_id = 0; foe.team_id = 0
        elif negative == "shield": dog.shielding = true
        elif negative == "expired": shot.lifetime = 0
        else: shot.age = shot.FADE_START+0.01
        if negative == "visual_fade":
            shot.global_position = dog.global_position+Vector3.UP
            shot._sweep_wave(Vector3.ZERO)
        else:
            check(not shot._try_absorb(dog),"projectile interception rejects "+negative)
        check(dog.doge_counter.phase == "stance","no counter trigger "+negative)
        shot.queue_free(); dog.team_id = -1; foe.team_id = -1
    await fresh()
    dog.global_position.y = 3
    dog.start_special(Vector2.DOWN); await step(0.16)
    check(dog.doge_counter.active() and dog.global_position.y < 3,"air counter allows normal gravity, no lift")
    dog.receive_hit_from(10,Vector3.LEFT,4,foe)
    dog.lose_stock()
    check(dog.doge_counter.phase == "idle" and dog.counter_hitstop == 0,"stock clears triggered hook")
    await projectile_cases()
    await fresh()
    key(KEY_S,true); key(KEY_F,true); await step(0.01); key(KEY_F,false)
    check(dog.doge_attack_clip == "TysonTwoPiece" and dog.doge_counter.phase == "idle","ground down BASIC preserved")
func projectile_cases():
    for variant in ["projectile","frost","goo_projectile","fire_projectile","teknium_force_projectile","teknium_charge_shot","turbofit_sound_wave"]:
        for face in [1.0,-1.0]:
            await fresh(face)
            foe.global_position.x = face*6
            dog.start_special(Vector2.DOWN); await step(0.16)
            var shot = load("res://scripts/%s.gd" % ("projectile" if variant == "frost" else variant)).new()
            shot.source = foe; shot.direction = -face
            if variant == "frost": shot.freeze_bolt = true
            if variant == "teknium_charge_shot": shot.power = 1
            root.add_child(shot); shot.set_physics_process(false)
            shot.global_position = Vector3(face*1.4,1.25,0)
            var payload: float = shot.payload_damage()
            # Real ordered sweep into current native hurtbody; fighter clock stays active.
            for i in 20:
                if not is_instance_valid(shot) or shot.is_queued_for_deletion(): break
                await physics_frame
                shot._physics_process(0.01)
            check(dog.doge_counter.phase == "hook" and dog.damage_percent == 0,"swept projectile blocked %s face%s" % [variant,face])
            check(dog.freeze_remaining == 0 and dog.burn == null,"no projectile status leakage "+variant)
            check(not is_instance_valid(shot) or shot.is_queued_for_deletion(),"projectile consumed not reflected "+variant)
            check(dog.doge_counter.incoming == payload,"actual variant payload "+variant)
            await step(0.8)
            check(foe.damage_percent == 0,"distant projectile owner not auto-hit "+variant)
            if is_instance_valid(shot): shot.queue_free()

func finish():
    key(KEY_S,false); key(KEY_G,false)
    print("DOGE_COUNTER_COMPLETE checks=%d failures=%d" % [checks,failures])
    quit(1 if failures else 0)

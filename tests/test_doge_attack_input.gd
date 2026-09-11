extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, msg: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + msg)
func key(code: int, down: bool):
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func advance_for(dog, seconds: float):
    var left := seconds
    while left > 0.000001:
        var dt := minf(left, 0.01)
        await physics_frame
        dog._physics_process(dt)
        left -= dt
func _initialize(): call_deferred("run")
func run():
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var floor_body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(100,1,5)
    shape.shape = box
    floor_body.position.y = -0.5
    floor_body.add_child(shape)
    root.add_child(floor_body)
    for direction in [1.0,-1.0]:
        dog.reset_fighter(Vector3.ZERO,true)
        dog.facing = direction
        await advance_for(dog,0.1)
        check(dog.is_grounded(),"real terrain")
        for i in range(1,5):
            key(KEY_F,true)
            await advance_for(dog,0.01)
            check(dog.doge_attack_clip == "Punch%d" % i,"fresh press selects original step %d" % i)
            key(KEY_F,false)
            await advance_for(dog,float(dog.doge_attack_timings[dog.doge_attack_clip].duration))
        key(KEY_F,true)
        await advance_for(dog,2.0)
        check(dog.doge_attack_clip == "" and dog.doge_combo_next == 1,"held F does not repeat")
        key(KEY_F,false)
        await advance_for(dog,0.02)
        for follow in [false,true]:
            dog.reset_fighter(Vector3.ZERO,true)
            await advance_for(dog,0.1)
            key(KEY_S,true)
            key(KEY_F,true)
            await advance_for(dog,0.01)
            check(dog.doge_attack_clip == "TysonTwoPiece","S+F routes jab")
            key(KEY_S,false)
            key(KEY_F,false)
            await advance_for(dog,0.28)
            if follow:
                key(KEY_F,true)
                await advance_for(dog,0.01)
                check(dog.doge_tyson_followup,"fresh F commits right")
            else:
                check(not dog.doge_tyson_followup,"single tap never commits right")
            await advance_for(dog,0.22)
            var view = dog._visual_root.get_node("DogeVisual")
            check(view.animation_player.current_animation_position > 0.45 if follow else view.animation_player.current_animation_position < 0.35,"actual source pose follows chosen branch")
            await advance_for(dog,1.8)
            check(dog.doge_attack_clip == "","held followup never repeats")
            key(KEY_F,false)
            await advance_for(dog,0.02)
        key(KEY_W,true)
        key(KEY_F,true)
        await advance_for(dog,0.01)
        check(dog.doge_attack_clip == "Uppercut" and dog.jumps_used == 0,"W+F uppercut no jump")
        key(KEY_W,false)
        key(KEY_F,false)
    dog.queue_free()
    floor_body.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge both-combo keyboard edges, source branches, no-repeat, uppercut")
    quit(1 if failures else 0)

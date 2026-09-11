extends SceneTree
func _initialize():call_deferred("run")
func run():
    var floor=StaticBody3D.new();floor.collision_layer=2;var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(20,1,5);col.shape=box;floor.add_child(col);root.add_child(floor);floor.position.y=-0.5
    var f=load("res://scripts/fighter.gd").new();f.control_type="bot";f.bot_difficulty="normal";root.add_child(f);f.set_physics_process(false)
    var v=load("res://scripts/fighter.gd").new();v.player_index=3;root.add_child(v);v.set_physics_process(false);v.position=Vector3(1.35,0,0)
    await physics_frame
    await process_frame
    var caught=false
    var previous=""
    for i in 240:
        await physics_frame
        f._physics_process(1.0/60.0)
        if previous!=f.teknium_magic.phase:
            print("BOT_DIAG ",i," seq=",f._bot.sequence," phase=",f.teknium_magic.phase," f=",f.position," v=",v.position," face=",f.facing," hand=",f.teknium_magic.visual.hand_tip())
            previous=f.teknium_magic.phase
        if v.caught_by!=null:caught=true;break
    print("BOT_CAPTURE=",caught," seq=",f._bot.sequence," atkcd=",f.attack_cooldown," phase=",f.teknium_magic.phase)
    f.queue_free();v.queue_free();floor.queue_free();await process_frame
    print("PASS: autonomous bot real controller starts close grab" if caught else "FAIL: bot grab starved by preceding basic cooldown")
    quit(0 if caught else 1)

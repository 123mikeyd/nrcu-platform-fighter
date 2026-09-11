extends SceneTree
const F = preload("res://scripts/fighter.gd")
func _initialize(): call_deferred("run")
func run():
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    dog.position.y = 1
    dog.basic_attack(Vector2(1,1),true)
    var ok: bool = dog.doge_attack_clip == "AirDownKarate"
    if not ok: printerr("FAIL airborne down-basic must route to AirDownKarate, not immediate legacy down strike")
    else: print("PASS aerial down route")
    dog.queue_free()
    await process_frame
    quit(0 if ok else 1)

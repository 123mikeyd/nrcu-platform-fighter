extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var fighter_script: Script = load("res://scripts/fighter.gd")
    if not fighter_script.can_instantiate():
        push_error("Fighter does not compile")
        quit(1)
        return
    var stage := Node3D.new()
    root.add_child(stage)
    var platform := StaticBody3D.new()
    platform.collision_layer = 2
    platform.position.y = 3
    platform.add_to_group("pass_through_platforms")
    platform.set_meta("top_y", 3.25)
    platform.set_meta("half_width", 30.0)
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(60, 0.5, 4)
    collision.shape = box
    platform.add_child(collision)
    stage.add_child(platform)
    var dog = F.new()
    dog.character_id = "doge_man"
    dog.player_index = 3
    dog.position = Vector3(-6, 4, 0)
    stage.add_child(dog)
    for i in range(35):
        await physics_frame
    check(dog.is_on_floor(), "Doge establishes upper-platform contact")
    dog.start_special(Vector2.RIGHT)
    var saw_landing := false
    for i in range(150):
        await physics_frame
        if dog.torpedo_phase == "landing":
            saw_landing = true
            check(dog.is_on_floor(), "Landing animation requires contact")
            check(absf(dog.position.y - 3.25) < 0.03, "Torpedo lands on upper platform height")
    check(saw_landing, "Torpedo plays recovery on an upper platform")
    check(dog.torpedo_phase == "idle" and not dog.tackle_spent, "Upper landing restores usable move")
    stage.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: torpedo landing and resource reset on pass-through upper platform")
    quit(1 if failures else 0)

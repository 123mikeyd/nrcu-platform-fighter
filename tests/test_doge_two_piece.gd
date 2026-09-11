extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    # Synthetic routing fixture; not evidence of animation timing or contact.
    dog.doge_attack_timings["TysonTwoPiece"] = {"duration": 1.0, "hits": [{"time": 0.25}, {"time": 0.5}]}
    dog.basic_attack(Vector2.DOWN, false)
    check(dog.doge_attack_clip == "TysonTwoPiece", "ground S+F selects jab; fresh F required for haymaker")
    check(dog.attack_cooldown == 1.0, "complete two-piece reserves windup and recovery")
    dog.basic_attack(Vector2.LEFT, false)
    check(not dog.doge_punch_buffered and dog.doge_attack_facing == 1, "extra taps do not queue another combo or reverse the committed attack")
    dog._cancel_doge_attack()
    check(dog.doge_attack_clip.is_empty() and dog.attack_cooldown == 0, "interruption clears the complete two-piece")
    dog.basic_attack(Vector2.UP, false)
    check(dog.doge_attack_clip == "Uppercut", "up-basic retains its approved uppercut")
    dog._cancel_doge_attack()
    dog.basic_attack(Vector2.ZERO, true)
    check(dog.doge_attack_clip == "SupermanMoves2", "air-basic retains its approved Superman punch")
    dog._cancel_doge_attack()
    dog.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge connected two-piece routing")
    quit(1 if failures else 0)

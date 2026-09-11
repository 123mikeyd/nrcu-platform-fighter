extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = F.new()
    f.character_id = "doge_man"
    root.add_child(f)
    f.set_physics_process(false)
    f.basic_attack(Vector2.RIGHT, true)
    check(f.doge_attack_clip == "SupermanMoves2", "neutral horizontal aerial selects Superman")
    check(absf(f.attack_cooldown - 10.0 / 24.0) < 0.0001, "full approved source duration")
    if f.doge_attack_clip == "SupermanMoves2":
        f._tick_doge_attack(0.1)
        check(not f._doge_struck, "no input edge or windup damage")
        f._update_move_visuals()
        var v = f._visual_root.get_node("DogeVisual")
        check(v.current_clip == "SupermanMoves2", "actual aerial presentation")
        check(absf(v.animation_player.current_animation_position - 0.1) < 0.001, "uncompressed source clock")
        f.receive_hit(3, Vector3.UP, 3)
        check(f.doge_attack_clip.is_empty(), "hit cancels pending aerial strike")
    f.hitstun = 0
    f.attack_cooldown = 0
    f._cancel_doge_attack()
    f.basic_attack(Vector2.UP, true)
    check(f.doge_attack_clip.is_empty() and f.last_move == "UP AIR", "vertical up aerial unchanged")
    f.attack_cooldown = 0
    f.basic_attack(Vector2.DOWN, true)
    check(f.doge_attack_clip == "AirDownKarate" and f.last_move == "AIR KARATE KICK", "approved aerial down karate route is separate from Superman")
    f._cancel_doge_attack()
    f.attack_cooldown = 0
    f.basic_attack(Vector2.ZERO, false)
    check(f.doge_attack_clip == "Punch1", "ground neutral selects original four-piece first punch")
    f.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge Superman routing")
    quit(1 if failures else 0)

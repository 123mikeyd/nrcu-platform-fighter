extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok: failures += 1; printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = F.new()
    f.character_id = "turbofit"
    root.add_child(f)
    f.set_physics_process(false)
    var target = F.new()
    target.character_id = "doge_man"
    root.add_child(target)
    target.set_physics_process(false)
    target.position = Vector3(1.2,0,0)
    for aim in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT]:
        f.basic_attack(aim, false)
        f._update_move_visuals()
        check(f.last_move == "GUITAR SWING" and f.turbofit_attack_clip.is_empty(), "neutral/horizontal grounded basic retains original guitar attack")
        check(f.get_node("VisualRoot/TurboFitVisual").current_clip == "MeleeHorizontal", "grounded F uses original horizontal guitar animation")
        f.reset_fighter(Vector3.ZERO)
    f.basic_attack(Vector2.DOWN, true)
    f._update_move_visuals()
    check(f.last_move == "AIR DOWN KICK" and f.turbofit_attack_clip == "AirDownKick", "airborne S+F uses approved down kick, never goalkeeper")
    check(f.get_node("VisualRoot/TurboFitVisual").current_clip == "AirDownKick", "airborne down-basic uses approved source4-42")
    f.reset_fighter(Vector3.ZERO)
    f.basic_attack(Vector2.DOWN, false)
    check(f.last_move == "GOALKEEPER KICK", "grounded down basic selects approved goalkeeper kick")
    if f.has_method("_tick_turbofit_attack"):
        f._tick_turbofit_attack(0.449)
        check(target.damage_percent == 0, "kick cannot hit before frame 67 sample")
        f._tick_turbofit_attack(0.001)
        f._update_move_visuals()
        check(target.damage_percent == 14, "kick hits once at source 67, 0.45 seconds at 2x")
        var v = f.get_node("VisualRoot/TurboFitVisual")
        check(v.current_clip == "GoalkeeperKick", "controller selects goalkeeper visual")
        check(f.get_node_or_null("VisualRoot/Guitar") == null, "removed prototype guitar does not obscure kick footwork")
        check(absf(v.animation_player.current_animation_position - 0.9) < 0.002, "kick visual is clock-locked to exact strike sample")
        f._tick_turbofit_attack(0.2)
        check(target.damage_percent == 14, "kick does not repeat damage")
        f.reset_fighter(Vector3.ZERO)
        target.damage_percent = 0
        f.basic_attack(Vector2.UP, false)
        check(f.last_move == "GUITAR SWING" and f.turbofit_attack_clip.is_empty(), "rejected knee has no mapping; preexisting up guitar attack remains")
        f.reset_fighter(Vector3.ZERO)
        target.damage_percent = 0
        f.basic_attack(Vector2.DOWN, false)
        f.receive_hit(1, Vector3.UP, 1)
        check(f.get_node_or_null("VisualRoot/Guitar") == null, "interruption does not restore removed placeholder")
        f._tick_turbofit_attack(1)
        check(target.damage_percent == 0, "interruption cancels pending kick")
        f.reset_fighter(Vector3.ZERO)
        f.basic_attack(Vector2.DOWN, false)
        f.lose_stock()
        f._tick_turbofit_attack(1)
        check(target.damage_percent == 0, "stock loss cancels pending attack")
    else:
        check(false, "controller exposes dedicated animation-locked kick clock")
    f.queue_free()
    target.queue_free()
    await process_frame
    if failures == 0: print("PASS TurboFit kick routing, sampled impact timing, once-only damage, interruption, stock reset; rejected knee unmapped")
    quit(1 if failures else 0)

extends SceneTree
var failures := 0
var queries: Array = []
class Probe:
    extends "res://scripts/fighter.gd"
    var queries: Array = []
    func _directional_hit(damage: float, knockback: float, reach: float, direction: Vector3, cooldown: float) -> void:
        var v = get_node("VisualRoot/TurboFitVisual")
        queries.append({"clip":v.current_clip,"time":v.animation_player.current_animation_position,"damage":damage})
        super._directional_hit(damage,knockback,reach,direction,cooldown)
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
    if not ok: failures += 1; printerr("FAIL: ",message)
func run() -> void:
    var f = Probe.new()
    f.character_id = "turbofit"
    root.add_child(f)
    await process_frame
    f.set_physics_process(false)
    f.start_special(Vector2.ZERO)
    f.advance_charge(0.2)
    f._update_move_visuals(0.2)
    var v = f.get_node("VisualRoot/TurboFitVisual")
    check(v.current_clip == "TwoHandCombo", "held anticipation uses approved source")
    f.release_special()
    check(f.queries.size() == 1, "release queries immediately")
    check(absf(f.queries[0].time - 19.0/30) < 0.00001, "query sees exact source frame 20")
    f.queue_free()
    await process_frame
    print("PASS TurboFit Power Chord" if failures == 0 else "FAIL: Power Chord")
    quit(1 if failures else 0)

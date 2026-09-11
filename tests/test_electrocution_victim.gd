extends SceneTree
var failures := 0
func check(ok, message):
    if not ok: failures += 1; print("FAIL: ", message)
func _initialize(): call_deferred("run")
func run():
    var f = load("res://scripts/fighter.gd").new()
    root.add_child(f); f.set_physics_process(false)
    var v = load("res://scripts/fighter.gd").new(); v.character_id = "doge_man"
    root.add_child(v); v.set_physics_process(false); v.position = Vector3(1.35,0,0)
    await physics_frame; await process_frame
    var visual = v.get_node("VisualRoot/DogeVisual")
    var player = visual.animation_player
    check(player.has_animation("Electrocution"), "approved source reaction imported")
    f.start_special(Vector2.ZERO)
    var m = f.teknium_magic
    m.tick(0.20); v._update_move_visuals(0)
    check(v.caught_by == m and visual.current_clip != "Electrocution", "capture uses real contact; not startup reaction")
    m.tick(4.0/24.0); v._update_move_visuals(0)
    check(visual.current_clip == "Electrocution", "actual hold selects victim reaction")
    var first = player.current_animation_position
    m.tick(0.25); v._update_move_visuals(0)
    check(player.current_animation_position > first and not player.is_playing(), "reaction advances solely from hold clock while player stays paused")
    check(f.get_node("VisualRoot/TekniumVisual").current_clip == "GrabLoop", "caster keeps independent loop")
    for i in 4: m.tick(0.25); v._update_move_visuals(0)
    check(v.damage_percent == 10 and m.tick_count == 5 and m.phase == "ending", "unchanged five hold ticks and ten damage")
    m.tick(5.0/24.0); v._update_move_visuals(0)
    check(v.caught_by == null and visual.current_clip != "Electrocution" and player.speed_scale > 0, "release restores normal presentation")
    check(v.freeze_immunity == 0 and v.grab_immunity == 1, "freeze immunity untouched")
    f.queue_free(); v.queue_free(); await process_frame
    if failures == 0: print("PASS: actual grab electrocution victim presentation and unchanged mechanics")
    quit(0 if failures == 0 else 1)

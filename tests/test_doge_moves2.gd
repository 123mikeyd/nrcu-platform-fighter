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
    var v = f._visual_root.get_node("DogeVisual")
    f.velocity = Vector3.DOWN
    f._update_move_visuals()
    check(v.current_clip == "MidairMoves2", "offledge directly loops without fake takeoff")
    check(f.try_jump(), "ordinary jump accepted")
    check(v.current_clip == "JumpMoves2", "ordinary jump uses approved takeoff")
    f._update_move_visuals(0.34)
    check(v.current_clip == "MidairMoves2", "takeoff enters approved one second loop")
    check(f.try_jump(), "double jump accepted")
    check(v.current_clip == "JumpMoves2", "double jump restarts takeoff")
    check(v.animation_player.current_animation_position < 0.001, "double jump starts at source13")
    f._update_move_visuals(0.34)
    f.torpedo_phase = "landing"
    f._update_move_visuals()
    check(v.current_clip == "Landing", "existing special landing has priority")
    f.torpedo_phase = "idle"
    f.receive_hit(3, Vector3.UP, 3)
    check(v.current_clip == "HitMoves2", "actual hitstun uses approved reaction")
    f.hitstun = 3
    f._update_move_visuals(2)
    check(v.current_clip == "HitMoves2", "long existing stun holds reaction end")
    check(absf(v.animation_player.current_animation_position - v.animation_player.get_animation("HitMoves2").length) < 0.001, "no repeated recoil loop")
    f.receive_hit(3, Vector3.UP, 3)
    check(v.animation_player.current_animation_position < 0.001, "new hit restarts recoil")
    f.hitstun = 0
    f._update_move_visuals()
    check(v.current_clip == "MidairMoves2", "stun end returns directly to airborne loop")
    var other = F.new()
    other.character_id = "doge_man"
    root.add_child(other)
    other.set_physics_process(false)
    var ov = other._visual_root.get_node("DogeVisual")
    f.reset_fighter(Vector3.ZERO, true)
    f.try_jump()
    f._update_move_visuals(0.1)
    check(f.apply_freeze(other), "real freeze accepted")
    var frozen_time: float = v.animation_player.current_animation_position
    f._update_move_visuals(0.5)
    check(v.animation_player.current_animation_position == frozen_time and not v.animation_player.is_playing(), "freeze pauses actual takeoff pose")
    check(f.jumps_used == 1, "freeze never refunds jump")
    f._tick_freeze(1.1)
    f._update_move_visuals()
    check(v.current_clip == "MidairMoves2", "thaw ends interrupted takeoff episode without fake restart")
    f.reset_fighter(Vector3.ZERO, true)
    f.try_jump()
    f.cancel_for_grab()
    f.velocity = Vector3.DOWN
    f._update_move_visuals()
    check(v.current_clip == "MidairMoves2" and f.jumps_used == 1, "grab cancellation ends takeoff without refund")
    for clip in ["JumpMoves2", "MidairMoves2", "SupermanMoves2", "HitMoves2"]:
        var animation = v.animation_player.get_animation(clip)
        check(animation != ov.animation_player.get_animation(clip), "isolated resources " + clip)
        check(animation.loop_mode == (Animation.LOOP_LINEAR if clip == "MidairMoves2" else Animation.LOOP_NONE), "loop mode " + clip)
    f.queue_free()
    other.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge Moves2 movement and hit")
    quit(1 if failures else 0)

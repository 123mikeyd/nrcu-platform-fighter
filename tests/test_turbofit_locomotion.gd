extends SceneTree
const FighterScript = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok: failures += 1; printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = FighterScript.new()
    f.character_id = "turbofit"
    root.add_child(f)
    f.set_physics_process(false)
    var v = f.get_node("VisualRoot/TurboFitVisual")
    v.sync_pose(true, Vector3(2,0,0), false, false, "", Vector3.RIGHT, 1, 0.016)
    check(v.current_clip == "Walk", "slow ground travel selects actual Walk")
    v.sync_pose(true, Vector3(7,0,0), false, false, "", Vector3.RIGHT, 1, 0.016)
    check(v.current_clip == "Run", "fast ground travel selects actual Run")
    v.sync_pose(false, Vector3(0,-2,0), false, false, "", Vector3.RIGHT, 1, 0.016)
    check(v.current_clip == "FallLoop", "descending selects authored airborne loop")
    v.sync_pose(false, Vector3(0,-10,0), false, false, "", Vector3.RIGHT, 1, 2)
    check(v.current_clip == "FallLoop", "no timer-triggered midair landing")
    v.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, 1, 0.016)
    check(v.current_clip == "Landing", "floor contact begins landing")
    v.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, 1, 1)
    check(v.current_clip == "Idle", "landing completes once")
    v.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, 1, 0.1)
    check(v.current_clip == "Idle", "standing floor does not replay landing")
    v.sync_pose(false, Vector3(0,-2,0), false, false, "", Vector3.RIGHT, 1, 0.016)
    v.sync_pose(false, Vector3.ZERO, true, false, "", Vector3.RIGHT, 1, 0.016)
    v.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, 1, 0.016)
    check(v.current_clip == "Idle", "interruption clears fall episode")
    f.queue_free()
    await process_frame
    if failures == 0: print("PASS TurboFit Walk/Run, falling episode, floor-triggered landing and interruption")
    quit(1 if failures else 0)

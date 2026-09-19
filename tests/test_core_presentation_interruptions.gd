extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
    var script = load("res://scripts/core/presentation/teknium_presenter.gd")
    var a = script.new()
    var b = script.new()
    root.add_child(a)
    root.add_child(b)
    a.present({"locomotion": "idle", "grounded": true}, 0)
    b.present({"locomotion": "idle", "grounded": true}, 0)
    var sk: Skeleton3D = a.model.find_children("*", "Skeleton3D", true, false)[0]
    var bone := sk.find_bone("LeftUpLeg")
    var before := sk.get_bone_pose(bone)
    a.present({"locomotion": "run", "grounded": true}, 1)
    check(sk.get_bone_pose(bone).is_equal_approx(before), "transition starts at outgoing pose rather than snapping")
    a.present({"locomotion": "run", "grounded": true}, 3)
    check(not sk.get_bone_pose(bone).is_equal_approx(before), "timed blend progresses on committed ticks")
    var frozen_pose := sk.get_bone_pose(bone)
    var frozen_clock: float = a.animation_player.current_animation_position
    for tick in range(4, 15):
        a.present({"locomotion": "falling", "status": "frozen", "facing": -1}, tick)
    check(sk.get_bone_pose(bone).is_equal_approx(frozen_pose), "freeze preserves rendered blended pose")
    check(a.animation_player.current_animation_position == frozen_clock, "freeze does not age clip")
    check(is_equal_approx(a.model.rotation.y, PI / 2), "freeze holds facing too")
    a.present({"locomotion": "run", "grounded": true}, 15)
    check(is_equal_approx(a.animation_player.current_animation_position, frozen_clock + 1.0 / 60), "thaw excludes frozen ticks")
    frozen_pose = sk.get_bone_pose(bone)
    a.present({"locomotion": "rising", "status": "hitstun", "hit_id": 7}, 16)
    check(sk.get_bone_pose(bone).is_equal_approx(frozen_pose), "hit wins over jump-entry hard cut and begins 0.03s blend")
    check(a.animation_player.assigned_animation == "Hit", "hit interrupts locomotion")
    a.present({"locomotion": "rising", "status": "hitstun", "hit_id": 7}, 200)
    check(is_equal_approx(a.animation_player.current_animation_position, 2.0), "finished Hit holds endpoint, never loops")
    a.present({"status": "hitstun", "hit_id": 8}, 201)
    check(is_zero_approx(a.animation_player.current_animation_position), "new hit event restarts once")
    a.present({"action": "movement_lock"}, 202)
    check(a.animation_player.assigned_animation == "Block", "existing movement-lock presentation maps Block without defense implementation")
    a.present({"action": "recovery"}, 203)
    check(a.state.output.get("fallback", "").contains("recovery"), "recovery gap explicitly labeled")
    check(b.animation_player.assigned_animation == "Idle" and b.animation_player.current_animation_position == 0, "duplicate instances have independent clips and clocks")
    a.present({"locomotion": "idle", "grounded": true}, 0)
    check(a.animation_player.current_animation_position == 0 and sk.get_bone_pose(bone).is_equal_approx(b.model.find_children("*", "Skeleton3D", true, false)[0].get_bone_pose(bone)), "rewind clears transition and pose history")
    a.queue_free()
    b.queue_free()
    await process_frame
    if failures == 0: print("PASS: core presentation blends, freeze, hit, instance independence, rewind")
    quit(1 if failures else 0)

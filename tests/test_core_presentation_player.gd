extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ", message)
func _init() -> void: call_deferred("run")
func animation_metadata(animation: Animation) -> String:
    var tracks: Array = []
    for track in range(animation.get_track_count()):
        var keys: Array = []
        for key in range(animation.track_get_key_count(track)):
            keys.append([animation.track_get_key_time(track, key), animation.track_get_key_transition(track, key), animation.track_get_key_value(track, key)])
        tracks.append([animation.track_get_type(track), animation.track_get_path(track), animation.track_is_enabled(track), animation.track_is_imported(track), animation.track_get_interpolation_type(track), animation.track_get_interpolation_loop_wrap(track), keys])
    # Serialize now: no cached Resource or mutable container can alias the baseline.
    return var_to_str([animation.length, animation.loop_mode, animation.step, tracks])
func run() -> void:
    var path := "res://scripts/core/presentation/teknium_presenter.gd"
    check(ResourceLoader.exists(path), "real Teknium presenter exists")
    if failures:
        quit(1)
        return
    var source = load("res://assets/teknium/teknium_animations.glb").instantiate()
    var original: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
    var source_metadata: Dictionary = {}
    var source_clips := original.get_animation_list()
    for clip in source_clips:
        source_metadata[clip] = animation_metadata(original.get_animation(clip))
    var v = load(path).new()
    root.add_child(v)
    v.present({"locomotion": "walk", "grounded": true, "facing": -1.0}, 0)
    check(v.animation_player is AnimationPlayer, "real imported AnimationPlayer")
    check(v.animation_player.current_animation == "Walk", "Walk reaches actual player")
    v.present({"locomotion": "walk", "grounded": true}, 1)
    check(is_equal_approx(v.animation_player.current_animation_position, 1.0 / 60), "manual source clock reaches real player")
    check(v.play_count == 1, "steady state does not call play again")
    var clock: float = v.animation_player.current_animation_position
    await process_frame
    await process_frame
    check(v.animation_player.current_animation_position == clock, "render frames cannot advance player")
    check(is_equal_approx(v.model.rotation.y, -PI / 2), "facing persists at rest")

    v.present({"locomotion": "jump_startup", "grounded": true, "air_jumps_left": 1}, 2)
    check(v.animation_player.assigned_animation == "Jump", "jump startup enters approved Jump")
    var starts: int = v.play_count
    v.present({"locomotion": "jump_startup", "grounded": true, "air_jumps_left": 1}, 3)
    v.present({"locomotion": "rising", "air_jumps_left": 1}, 4)
    check(v.play_count == starts, "startup to rise continues episode without play restart")
    check(is_equal_approx(v.animation_player.current_animation_position, 2.0 / 60), "jump source timing unchanged")
    v.present({"locomotion": "rising", "air_jumps_left": 0}, 5)
    check(is_zero_approx(v.animation_player.current_animation_position), "accepted air jump starts a new visual episode")
    v.present({"locomotion": "rising", "air_jumps_left": 0}, 100)
    var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
    var rise_pose: Transform3D = sk.get_bone_pose(sk.find_bone("LeftUpLeg"))
    v.present({"locomotion": "falling"}, 101)
    v.present({"locomotion": "falling"}, 110)
    check(not rise_pose.is_equal_approx(sk.get_bone_pose(sk.find_bone("LeftUpLeg"))), "fall fallback is visibly distinct skeletal pose")
    check(is_equal_approx(v.animation_player.current_animation_position, v.animation_player.get_animation("Jump").length), "fall uses labeled source endpoint fallback")
    v.present({"locomotion": "landing", "grounded": true}, 111)
    check(v.state.output.get("fallback", "") != "", "landing fallback is explicit")
    v.present({"locomotion": "landing", "grounded": true}, 112)
    check(v.state.output.get("state", "") == "landing", "landing one-shot survives short gameplay landing state")
    v.present({"locomotion": "landing", "grounded": true}, 130)
    starts = v.play_count
    v.present({"locomotion": "landing", "grounded": true}, 131)
    check(v.play_count == starts and v.animation_player.assigned_animation == "Idle", "completed landing does not loop while telemetry stays landing")
    v.present({"locomotion": "rising", "status": "hitstun", "hit_id": 7}, 132)
    v.present({"action": "movement_lock"}, 133)
    v.present({"action": "recovery"}, 134)
    check(original.get_animation_list() == source_clips and v.animation_player.get_animation_list() == source_clips, "source clip inventory preserved")
    for clip in source_clips:
        check(animation_metadata(original.get_animation(clip)) == source_metadata[clip], "cached source metadata preserved: " + clip)
        check(animation_metadata(v.animation_player.get_animation(clip)) == source_metadata[clip], "presenter source length, loop, tracks and keys preserved: " + clip)
    source.free()
    v.free()
    if failures == 0: print("PASS: core presentation real AnimationPlayer")
    quit(1 if failures else 0)

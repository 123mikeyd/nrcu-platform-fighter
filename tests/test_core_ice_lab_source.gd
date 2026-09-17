extends "res://tests/test_core_combat_lab.gd"
func fingerprint(player: AnimationPlayer) -> String:
    var all: Array = []
    for clip in player.get_animation_list():
        var a := player.get_animation(clip)
        var tracks: Array = []
        for t in a.get_track_count():
            var keys: Array = []
            for k in a.track_get_key_count(t): keys.append([a.track_get_key_time(t,k),a.track_get_key_transition(t,k),a.track_get_key_value(t,k)])
            tracks.append([a.track_get_path(t),a.track_get_type(t),a.track_is_enabled(t),a.track_is_imported(t),a.track_get_interpolation_type(t),a.track_get_interpolation_loop_wrap(t),keys])
        all.append([clip,a.length,a.loop_mode,a.step,tracks])
    return var_to_str(all)
func run() -> void:
    var source = load("res://assets/ice_mage/ice_mage_combat.glb").instantiate()
    root.add_child(source)
    var ap: AnimationPlayer = source.find_children("*","AnimationPlayer",true,false)[0]
    var sk: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
    ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    var before := fingerprint(ap)
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0,"ice_mage")
    lab.select_fighter(1,"ice_mage")
    for slot in range(2):
        for code in [KEY_F if slot==0 else KEY_K,KEY_G if slot==0 else KEY_L]:
            lab.reset_lab()
            lab.actors[1-slot].position.x = 10 if slot==0 else -10
            for i in range(40): await tick(lab)
            var direction := KEY_D if slot==0 else KEY_LEFT
            key(direction,true)
            key(code,true)
            await tick(lab)
            key(direction,false)
            key(code,false)
            for i in range(10):
                await tick(lab)
                var visual = lab.imported_visuals[slot]
                var request: Dictionary = lab.simulation.kit_telemetry(slot+1).presentation
                ap.play(request.clip,0)
                ap.seek(request.elapsed,true)
                sk.force_update_all_bone_transforms()
                check(is_equal_approx(visual.model.rotation.y,request.facing*PI/2),"committed both-facing positive yaw")
                check(visual.scale == Vector3.ONE*1.15 and is_equal_approx(visual.position.y,.035),"source placement exactly once")
                for b in range(sk.get_bone_count()): check(visual.skeleton.get_bone_pose(b).is_equal_approx(sk.get_bone_pose(b)),"physical lab immutable oracle source pose")
    check(fingerprint(ap)==before,"lab playback leaves original keys loop modes durations immutable")
    var fresh = load("res://assets/ice_mage/ice_mage_combat.glb").instantiate()
    check(fingerprint(fresh.find_children("*","AnimationPlayer",true,false)[0])==before,"cached source remains immutable")
    fresh.free()
    lab.free()
    source.free()
    if not failures: print("PASS: actual lab parsed basic/cast source skeleton parity both facings and immutable imported metadata")
    quit(1 if failures else 0)

extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok: failures += 1; printerr("FAIL: " + message)
func _initialize(): call_deferred("run")
func run():
    var model = load("res://assets/doge_man/doge_attacks.glb").instantiate()
    root.add_child(model)
    var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
    check(ap.has_animation("TysonTwoPiece"), "installed asset contains new two-piece")
    if not ap.has_animation("TysonTwoPiece"):
        model.queue_free(); await process_frame; quit(1); return
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    check(document.append_from_file("res://tests/fixtures/parent_verified_merge.glb", state) == OK, "verified candidate loads")
    var exact = document.generate_scene(state, 60.0, false, true)
    root.add_child(exact)
    var source: AnimationPlayer = exact.find_children("*", "AnimationPlayer", true, false)[0]
    var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    var ref: Skeleton3D = exact.find_children("*", "Skeleton3D", true, false)[0]
    ap.play("TysonTwoPiece", 0); source.play("TysonTwoPiece", 0)
    check(is_equal_approx(ap.get_animation("TysonTwoPiece").length, 1.0), "authored one-second duration retained")
    var maximum := 0.0
    for frame in range(61):
        ap.seek(frame / 60.0, true); source.seek(frame / 60.0, true)
        sk.force_update_all_bone_transforms(); ref.force_update_all_bone_transforms()
        for bone in sk.get_bone_count():
            var name := sk.get_bone_name(bone)
            maximum = maxf(maximum, sk.get_bone_global_pose(bone).origin.distance_to(ref.get_bone_global_pose(ref.find_bone(name)).origin))
    check(maximum < 0.0001, "every imported authored pose agrees within 0.1mm; max=" + str(maximum))
    model.queue_free(); exact.queue_free(); await process_frame
    if failures == 0: print("PASS installed two-piece 61-frame source pose comparison; max_error=", maximum)
    quit(1 if failures else 0)

extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize(): call_deferred("run")
func run():
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var side = F.new()
    side.character_id = "doge_man"
    root.add_child(side)
    side.set_physics_process(false)
    var view = dog._visual_root.get_node("DogeVisual")
    var original = side._visual_root.get_node("DogeVisual")
    var sk = view.model.find_children("*", "Skeleton3D",true,false)[0]
    var refsk = original.model.find_children("*", "Skeleton3D",true,false)[0]
    for facing in [1.0,-1.0]:
        for frame in [0,5,10]:
            dog.reset_fighter(Vector3.ZERO,true)
            dog.facing = facing
            dog.start_special(Vector2.UP)
            dog._update_move_visuals(frame/24.0)
            original.sync_pose("tackle",facing,0.4,0.42,0.18,0.6)
            original.animation_player.play("Dive",0)
            original.animation_player.speed_scale = 0
            original.animation_player.seek(frame/24.0,true)
            sk.force_update_all_bone_transforms()
            refsk.force_update_all_bone_transforms()
            for i in sk.get_bone_count():
                var actual: Vector3 = view.flight_root.transform.affine_inverse() * view.to_local(sk.global_transform * sk.get_bone_global_pose(i).origin)
                var expected: Vector3 = original.to_local(refsk.global_transform * refsk.get_bone_global_pose(i).origin)
                check(actual.distance_to(expected) < 0.00002,"inverse rotation preserves bone " + sk.get_bone_name(i))
            var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
            var hips: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
            check((head-hips).normalized().dot(Vector3.UP) > 0.9,"head above hips in full flight")
    check(view.animation_player.get_animation("Dive") != original.animation_player.get_animation("Dive"),"per instance library preserved")
    dog.reset_fighter(Vector3.ZERO,true)
    dog.start_special(Vector2.RIGHT)
    dog._update_move_visuals()
    check(view.flight_root.rotation == Vector3.ZERO and view.current_clip == "Launch","side launch never inherits upward rotation")
    dog.queue_free()
    side.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge up inverse pose equivalence and side isolation")
    quit(1 if failures else 0)

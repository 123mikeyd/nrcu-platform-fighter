extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok,message):
    if not ok:
        failures+=1
        print("FAIL: ",message)
func run():
    var b = load("res://scripts/bobo_fighter.gd").new()
    root.add_child(b)
    b.set_physics_process(false)
    await process_frame
    var v = b.get_node("VisualRoot/BoboVisual")
    var a = v.animation_player
    var durations = {"Idle":11.3,"Block":17.0/30,"Hit":85.0/30,"HitWaist":49.0/30,"Defeat":66.0/30}
    for clip in durations:
        check(a.has_animation(clip), "native clip present: " + clip)
        check(absf(a.get_animation(clip).length-durations[clip])<0.0001,"source speed exact duration: "+clip)
    var meshes = v.model.find_children("*","MeshInstance3D",true,false)
    check(meshes.size()==1,"one approved mesh, not reaction carrier duplicates")
    var mesh = meshes[0]
    var arrays = mesh.mesh.surface_get_arrays(0)
    check(arrays[Mesh.ARRAY_BONES].size()==arrays[Mesh.ARRAY_VERTEX].size()*8,"all eight deform influences retained")
    check(mesh.get_active_material(0).albedo_texture!=null,"approved texture bound")
    var sk = v.model.find_children("*","Skeleton3D",true,false)[0]
    a.stop();a.play("Idle",0);a.seek(0,true);sk.force_update_all_bone_transforms()
    var bounds = load("res://tests/posed_character_bounds.gd").new().bounds(v.model)
    print("BOBO_EVALUATED_BOUNDS ",JSON.stringify(bounds))
    for name in bounds:
        check(bounds[name].height > 2.6 and bounds[name].height < 3.0,"big but bounded model height")
        check(absf(bounds[name].min[1])<0.02,"evaluated neutral feet at fighter floor")
    var bone = sk.get_bone_global_pose(3)
    v.react("Hit")
    a.advance(0.25)
    sk.force_update_all_bone_transforms()
    check(not sk.get_bone_global_pose(3).is_equal_approx(bone),"real skeletal hit motion")
    b.queue_free()
    await process_frame
    print("BOBO_ASSET failures=",failures)
    quit(1 if failures else 0)

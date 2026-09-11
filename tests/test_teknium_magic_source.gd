extends SceneTree
func _initialize():call_deferred("run")
func run():
    var actor=load("res://scripts/fighter.gd").new();root.add_child(actor);actor.set_physics_process(false)
    var visual=actor.get_node("VisualRoot/TekniumVisual")
    var samples=JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/magic_source_samples.json"))
    var maximum=0.0;var worst="";var count=0
    for clip in samples:
        for sample in samples[clip]:
            visual.magic_pose(clip,sample.seconds,1.0)
            for hand in sample.hands:
                var p=sample.hands[hand];var expected=Vector3(p[0],p[1],p[2]);var error=visual.hand_tip(hand).distance_to(expected)
                if error>maximum:maximum=error;worst=clip+" source"+str(sample.frame)+" "+hand
            count+=1
    print("SOURCE_COMPARE count=",count," max_world_error=",maximum," worst=",worst)
    actor.queue_free()
    await process_frame
    if maximum>0.002:print("FAIL: sampled approved source poses differ");quit(1)
    else:print("PASS: all inclusive source frames match evaluated review hand tips");quit(0)

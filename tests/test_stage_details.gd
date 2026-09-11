extends SceneTree
var failures := 0
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        print("FAIL: ",message)
func _initialize(): call_deferred("run")
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var bodies = arena.find_children("*","CollisionObject3D",true,false).size()
    var env = arena.find_children("*","WorldEnvironment",false,false)[0].environment
    var ambient = env.ambient_light_color
    for id in ["toy_room","sky"]:
        arena.apply_level(id)
        await process_frame
        var detail = arena.stage_theme.get_node_or_null("StageDetails")
        check(detail != null, id+" has composed detail layer")
        if detail:
            check(detail.wood.albedo_texture != null,"wood texture installed")
            check(detail.stone.albedo_texture != null,"stone texture installed")
            if id == "toy_room":
                var poster = detail.get_node_or_null("OriginalDrawing")
                check(poster != null and poster.mesh is QuadMesh,"poster full UV face")
                if poster and poster.mesh is QuadMesh:
                    check(absf(poster.mesh.size.x/poster.mesh.size.y-600.0/760.0)<0.001,"original portrait aspect")
            check(detail.is_in_group("stage_decor"),"decor is queryable")
            check(detail.find_children("*","MeshInstance3D",true,false).size() >= 100,"substantial shaped detail")
            check(detail.find_children("*","CollisionObject3D",true,false).is_empty(),"decor has no bodies")
            var moving = get_nodes_in_group("stage_decor_motion")
            check(not moving.is_empty(),"animated props present")
            if not moving.is_empty():
                var before = moving[0].transform
                await create_timer(0.4).timeout
                check(before != moving[0].transform,"actual motion advances")
        check(arena.find_children("*","CollisionObject3D",true,false).size() == bodies,"collision unchanged")
        if id == "toy_room": check(arena.stage_theme.find_children("Figure_*","Node3D",false,false).size() == 7,"seven figures retained")
    arena.apply_level("debug")
    await process_frame
    check(get_nodes_in_group("stage_decor").is_empty(),"decor cleanup")
    check(get_nodes_in_group("stage_decor_motion").is_empty(),"motion cleanup")
    check(env.ambient_light_color == ambient,"environment restored")
    check(get_nodes_in_group("fighters").is_empty(),"no decor fighters")
    arena.queue_free()
    await process_frame
    print("Stage details failures: ",failures)
    if failures == 0: print("PASS: detailed stages, animation and lifecycle")
    quit(1 if failures else 0)

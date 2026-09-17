extends "res://tests/test_core_hurtbox_match_actual.gd"
## Lab characterization after the opt-in/presenter RED→GREEN slices.
func key(code: int, down: bool) -> void:
    var event := InputEventKey.new(); event.physical_keycode = code; event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func tick_lab(lab) -> void:
    await physics_frame
    lab._physics_process(1.0/60.0)
func kick(lab, clip: String, facing: float) -> void:
    var direction := KEY_D if facing > 0 else KEY_A
    key(direction,true)
    if clip == "AirDownKick": key(KEY_S,true)
    key(KEY_F,true); await tick_lab(lab)
    key(KEY_F,false); key(direction,false); key(KEY_S,false)
    for i in (23 if clip == "AirDownKick" else 9): await tick_lab(lab)
func capture(lab, name: String) -> void:
    if DisplayServer.get_name() == "headless": return
    lab.set_process(false)
    var camera: Camera3D = root.get_camera_3d()
    var center: Vector3 = (lab.actors[0].position+lab.actors[1].position)*.5+Vector3.UP
    camera.size = 10
    camera.position = center+Vector3(0,2,28)
    camera.look_at(center)
    await RenderingServer.frame_post_draw
    var path := "res://.verification/core/collision-lab/"+name+".png"
    check(root.get_texture().get_image().save_png(path) == OK,"native damage capture")
    print("SCREENSHOT: ",path)
    lab.set_process(true)
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.select_fighter(0,"turbofit"); lab.set_generated_collision_enabled(true)
    var m = lab.simulation
    var cases := 0
    for clip in ["AirSideKick","AirDownKick"]:
        for facing in [-1.0,1.0]:
            lab.spawns = {1:Vector3(0,30,0),2:Vector3(10,30,0)}
            lab.reset_lab(); m.fighters[2].facing = facing
            await tick_lab(lab); await kick(lab,clip,facing)
            check(m.kit_telemetry(1).presentation.clip == clip,"real native input selects requested kick")
            var selected := [fixture(m,1,2,clip,facing,true),fixture(m,1,2,clip,facing,false)]
            var drift: Vector3 = lab.actors[0].position-lab.actors[1].position+Vector3(10,0,0)
            for want_hit in [true,false]:
                var chosen: Dictionary = selected[0 if want_hit else 1]
                check(not chosen.is_empty(),"legal actual generated lab fixture exists")
                if chosen.is_empty(): continue
                lab.spawns = {1:Vector3(0,30,0),2:Vector3(0,30,0)+chosen.offset+drift}
                lab.reset_lab(); m.fighters[2].facing = facing
                await tick_lab(lab); await kick(lab,clip,facing)
                check(m.fighters[2].percent == (14 if want_hit else 0),"actual lab generated damage hit/miss "+str([clip,facing,want_hit]))
                var record: Dictionary = m.collision_telemetry(2)
                var sphere: Vector3 = lab.actors[0].position+Pose.new().center(clip,.4 if clip == "AirDownKick" else 5.0/30,facing)
                check((not Queries.earliest_contact(sphere,sphere,.22,record.contact_snapshot.primitives).is_empty()) == want_hit,"actual precontact sphere vs published limbs agrees")
                if want_hit:
                    check(m.events.size() == 1 and m.events[0].geometry_mode == "generated_hurtboxes","generated damage event")
                    check(m.events[0].contact_evidence.pose_revision == record.contact_snapshot.pose_revision,"event frozen precontact evidence")
                    check(lab.imported_visuals[1].canonical.output.clip == "Hit","actual posthit render differs from contact evidence")
                    if facing > 0:
                        for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
                            root.content_scale_size = Vector2i.ZERO; root.size = dimensions
                            lab.set_collision_shapes_visible(true)
                            lab.set_collision_snapshot_phase("contact_snapshot")
                            lab._process(0)
                            await capture(lab,"native-%dx%d-%s-precontact" % [dimensions.x,dimensions.y,clip])
                    for i in 3: await tick_lab(lab)
                    check(m.fighters[2].percent == 14,"once victim remains")
                cases += 1
    lab.free()
    print("LAB ACTUAL CASES: ",cases)
    if not failures: print("PASS: collision lab real input generated aerial damage and contact evidence")
    quit(1 if failures else 0)

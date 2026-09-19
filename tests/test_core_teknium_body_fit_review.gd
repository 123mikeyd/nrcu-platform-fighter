extends "res://tests/test_core_combat_lab.gd"
# Real native physics, synthetic keys, unchanged combat-lab stage.
const OUT = "res://.verification/core/teknium-body-fit-review/"
var records = []
func capture(lab, name_: String) -> void:
    if DisplayServer.get_name() == "headless": return
    lab.set_process(false)
    var camera = root.get_camera_3d()
    camera.position = Vector3(0,1.2,9); camera.look_at(Vector3(0,1.2,0)); camera.size = 5.0
    for child in lab.get_children():
        if child is CanvasLayer: child.hide()
    await process_frame; await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(OUT+name_+".png")
func run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    root.size = Vector2i(1280,720)
    var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
    for opponent in ["teknium","turbofit"]:
        check(lab.select_fighter(1,opponent),"opponent selected")
        for generated in [false,true]:
            check(lab.set_generated_collision_enabled(generated),"mode installed")
            if generated:
                # Characterize the retained native body, not the new jostle policy.
                check(lab.simulation.reset_with_collision_profiles(lab.spawns, {1:lab.simulation.fighters[1].collision_host.builder._profile,2:lab.simulation.fighters[2].collision_host.builder._profile}, "legacy_solid"),"explicit legacy native-blocking fixture")
                lab._reset_round_input_and_visuals()
            for direction in [-1,1]:
                lab.simulation.reset({1:Vector3(-3*direction,0.1,0),2:Vector3(0,0.1,0)})
                lab.simulation.fighters[1].facing = direction; lab.simulation.fighters[2].facing = -direction
                for i in 20: await tick(lab)
                var code = KEY_D if direction == 1 else KEY_A
                key(code,true); Input.flush_buffered_events()
                var contacts = 0
                for i in 55:
                    await tick(lab)
                    var a = lab.actors[0]
                    for j in a.get_slide_collision_count():
                        if a.get_slide_collision(j).get_collider() == lab.actors[1]: contacts += 1
                key(code,false); Input.flush_buffered_events()
                for i in 10: await tick(lab)
                check(contacts > 0,"genuine native blocking prerequisite")
                var a = lab.actors[0]; var b = lab.actors[1]
                var separation = absf(a.position.x-b.position.x)
                var ca = a.get_node("CoreCapsule"); var cb = b.get_node("CoreCapsule")
                check(a.runtime.grounded and b.runtime.grounded,"both grounded after native approach")
                check(separation >= ca.shape.radius+cb.shape.radius-0.005,"no side penetration")
                var identity = opponent+"-"+("anatomical-v1" if generated else "compatibility")+"-"+str(direction)
                var record = {"case":identity,"separation":separation,"native_contacts":contacts,"a_position":a.position,"b_position":b.position,"a_radius":ca.shape.radius,"a_height":ca.shape.height,"a_center":ca.position,"a_bottom":ca.position.y-ca.shape.height/2,"b_radius":cb.shape.radius,"b_height":cb.shape.height,"b_center":cb.position}
                lab.set_collision_shapes_visible(true); await capture(lab,identity+"-standing-outline")
                lab.set_collision_shapes_visible(false); await capture(lab,identity+"-standing-visual")
                key(KEY_F,true); Input.flush_buffered_events(); await tick(lab)
                key(KEY_F,false); Input.flush_buffered_events()
                record["accepted_move"] = lab.simulation.fighters[1].move_id
                record["accepted_grounded"] = a.runtime.grounded
                record["accepted_status"] = a.runtime.states.status
                var first = 0 if lab.simulation.fighters[2].percent > 0 else -1
                for age in range(1,36):
                    await tick(lab)
                    if first < 0 and lab.simulation.fighters[2].percent > 0:
                        first = age; await capture(lab,identity+"-first-damage")
                record["first_damage_age"] = first; record["damage"] = lab.simulation.fighters[2].percent
                check(first >= 0,"Punch connects at legal native spacing "+identity)
                records.append(record)
    var file = FileAccess.open(OUT+"native-spacing.json",FileAccess.WRITE); file.store_string(JSON.stringify(records,"\t")); file.close()
    lab.free()
    if not failures: print("PASS: Teknium body fit native spacing and real Punch, ",records.size()," cases")
    quit(1 if failures else 0)

extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + msg)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var dogs: Array = []
    for color in [Color.RED, Color.BLUE]:
        var dog = F.new()
        dog.character_id = "doge_man"
        dog.body_color = color
        root.add_child(dog)
        dog.set_physics_process(false)
        dogs.append(dog)
    var visual = dogs[0]._visual_root.get_node_or_null("DogeVisual")
    var other = dogs[1]._visual_root.get_node_or_null("DogeVisual")
    check(visual != null and other != null, "Doge uses imported visual")
    if visual and other:
        check(visual.animation_player != null, "real imported animation player")
        check(is_equal_approx(visual.model.rotation.y, PI / 2) and visual.scale == Vector3.ONE * 1.25, "model orientation and scale")
        var mesh = visual.model.find_children("*", "MeshInstance3D", true, false)[0]
        var other_mesh = other.model.find_children("*", "MeshInstance3D", true, false)[0]
        var mat = mesh.get_active_material(0)
        var other_mat = other_mesh.get_active_material(0)
        check(mat != other_mat and mat.albedo_color != other_mat.albedo_color, "duplicate palette materials isolated")
        check(mat.albedo_texture != null and mat.metallic == 0 and mat.roughness >= 0.8 and not mat.emission_enabled, "readable textured material")
        for phase in ["launch", "tackle", "fall", "landing", "idle"]:
            dogs[0].torpedo_phase = phase
            dogs[0]._update_move_visuals()
            var expected: String = {"launch":"Launch", "tackle":"Dive", "fall":"Brake", "landing":"Landing", "idle":"MidairMoves2"}[phase]
            check(visual.current_clip == expected, "phase clip " + expected)
        dogs[0].start_special(Vector2.LEFT)
        dogs[0]._update_move_visuals()
        check(is_equal_approx(visual.model.rotation.y, -PI / 2), "left-facing model yaw")
        dogs[0].receive_hit(3, Vector3.UP, 3)
        check(visual.current_clip == "HitMoves2", "hit immediately replaces special pose with approved recoil")
        dogs[0].reset_fighter(Vector3.ZERO, true)
        check(visual.current_clip == "Idle" and dogs[0]._visual_root.rotation == Vector3.ZERO, "reset neutral pose, no root rotation")
    for dog in dogs: dog.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge visual integration")
    quit(1 if failures else 0)

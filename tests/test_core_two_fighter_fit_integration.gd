extends "res://tests/test_core_combat_lab.gd"

func verify_profiles(lab) -> void:
    for slot in range(2):
        var fighter: String = lab.selected_fighters[slot]
        var base = load("res://data/collision/generated/%s.tres" % fighter)
        var override = load("res://data/collision/overrides/%s_anatomical_v1.tres" % fighter)
        var effective = lab.simulation.fighters[slot + 1].collision_host.builder._profile
        check(effective.hurtboxes.size() == base.hurtboxes.size(), "full merged set, not partial override: " + fighter)
        check(effective.source_asset == base.source_asset and effective.source_sha256 == base.source_sha256, "source identity retained: " + fighter)
        check(effective.body_radius == base.body_radius and effective.body_height == base.body_height and effective.body_center == base.body_center, "cyan body metadata unchanged: " + fighter)
        var body = lab.actors[slot].get_node("CoreCapsule")
        check(is_equal_approx(body.shape.radius, base.body_radius) and is_equal_approx(body.shape.height, base.body_height) and body.position.is_equal_approx(base.body_center), "native cyan body uses unchanged generated dimensions: " + fighter)
        for original in base.hurtboxes:
            var actual = null
            for h in effective.hurtboxes:
                if h.hurtbox_id == original.hurtbox_id: actual = h
            check(actual != null and actual.bone_name == original.bone_name, "stable ID and bone preserved: " + original.hurtbox_id)
            if actual == null: continue
            var tuned = null
            for h in override.hurtboxes:
                if h.hurtbox_id == original.hurtbox_id: tuned = h
            if tuned != null:
                check(actual.radius == tuned.radius and actual.height == tuned.height and actual.local_transform == tuned.local_transform, "anatomical head/core installed: " + fighter + "/" + original.hurtbox_id)
                check(actual.radius < original.radius and actual.height < original.height, "head/core smaller: " + original.hurtbox_id)
            else:
                check(actual.radius == original.radius and actual.height == original.height and actual.local_transform == original.local_transform, "untuned limb unchanged: " + original.hurtbox_id)

func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    check(not lab.generated_collision_enabled, "compatibility remains default")
    var original_body = lab.actors[0].get_node("CoreCapsule").shape.duplicate()
    check(lab.select_fighter(1, "turbofit"), "mixed roster")
    var generation: int = lab.simulation.generation
    check(lab.set_generated_collision_enabled(true), "atomic merged install")
    check(lab.simulation.generation == generation + 1, "exactly one atomic reset")
    verify_profiles(lab)
    await tick(lab)
    for id in [1, 2]:
        check(lab.simulation.collision_telemetry(id).ok, "actual full pose snapshot valid")
    lab.reset_lab()
    verify_profiles(lab)
    check(lab.select_fighter(0, "turbofit") and lab.select_fighter(1, "teknium"), "reverse both slots")
    verify_profiles(lab)
    check(lab.set_generated_collision_enabled(false), "opt out")
    for id in [1, 2]:
        check(lab.simulation.collision_telemetry(id).geometry_mode == "legacy_body_capsule", "compatibility restored")
    check(lab.actors[0].get_node("CoreCapsule").shape.radius == original_body.radius and lab.actors[0].get_node("CoreCapsule").shape.height == original_body.height, "original compatibility body restored")
    check(lab.set_generated_collision_enabled(true), "re-enable tuned profiles")
    verify_profiles(lab)
    lab.free()
    if not failures: print("PASS: anatomical merged profiles both slots reset toggle and compatibility")
    quit(1 if failures else 0)

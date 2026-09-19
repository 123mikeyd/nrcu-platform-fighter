extends "res://tests/test_core_combat_lab.gd"

func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(1, "turbofit")
    check(lab.set_generated_collision_enabled(true), "initial tuned install")
    var override = load("res://data/collision/overrides/turbofit_anatomical_v1.tres")
    var source_hash: String = override.source_sha256
    var stable_id: String = override.hurtboxes[0].hurtbox_id
    var base_hash: String = override.provenance.generated_profile_sha256
    for fault in ["unflagged", "source", "base", "merge"]:
        var generation: int = lab.simulation.generation
        var hosts = [lab.simulation.fighters[1].collision_host, lab.simulation.fighters[2].collision_host]
        lab.simulation.fighters[1].percent = 37.0
        lab.pending_steps = 2
        match fault:
            "unflagged": override.hurtboxes[0].manual_override = false
            "source": override.source_sha256 = "wrong source"
            "base": override.provenance.generated_profile_sha256 = "wrong base"
            "merge": override.hurtboxes[0].hurtbox_id = "unknown_tuning_id"
        check(not lab.set_generated_collision_enabled(true), "reject " + fault + " instead of silently ignoring tuning")
        check(lab.generated_collision_notice.begins_with("REFUSED:"), "visible refusal: " + fault)
        check(lab.generated_collision_enabled and lab.generated_collision_button.button_pressed, "retains active mode: " + fault)
        check(lab.simulation.generation == generation and lab.simulation.fighters[1].percent == 37.0 and lab.pending_steps == 2, "refusal has no reset side effects: " + fault)
        check(lab.simulation.fighters[1].collision_host == hosts[0] and lab.simulation.fighters[2].collision_host == hosts[1], "both previous profiles retained: " + fault)
        override.hurtboxes[0].manual_override = true
        override.source_sha256 = source_hash
        override.provenance.generated_profile_sha256 = base_hash
        override.hurtboxes[0].hurtbox_id = stable_id
    check(lab.set_generated_collision_enabled(true), "valid resources recover")
    check(lab.has_method("_merge_anatomical_profile"), "required override preflight seam")
    if lab.has_method("_merge_anatomical_profile"):
        var base = load("res://data/collision/generated/teknium.tres")
        check(not lab._merge_anatomical_profile(base, null).get("errors", []).is_empty(), "missing override must not silently install base")
        check(not lab._merge_anatomical_profile(null, override).get("errors", []).is_empty(), "missing base fails closed")
    lab.free()
    if not failures: print("PASS: anatomical override refusal atomic and fail closed")
    quit(1 if failures else 0)

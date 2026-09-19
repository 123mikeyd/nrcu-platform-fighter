extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    check(lab.has_method("set_generated_collision_enabled"), "explicit generated collision opt-in API")
    if not lab.has_method("set_generated_collision_enabled"):
        lab.free(); quit(1); return
    check(not lab.generated_collision_enabled, "compatibility default")
    check(lab.select_fighter(0,"turbofit"), "Turbo selectable")
    var sim = lab.simulation
    var actor = lab.actors[0]
    var source = lab.sources[0]
    var generation: int = sim.generation
    lab.set_paused(true)
    key(KEY_F,true)
    lab.pending_steps = 3
    check(lab.set_generated_collision_enabled(true), "generated install succeeds")
    check(sim.generation == generation+1 and lab.pending_steps == 0 and lab.paused, "one full reset retains pause clears steps")
    check(lab.simulation == sim and lab.actors[0] == actor and lab.sources[0] == source,"ownership retained")
    check(sim.collision_telemetry(1).geometry_mode == "generated_hurtboxes", "Turbo generated recipient")
    check(sim.collision_telemetry(2).geometry_mode == "generated_hurtboxes", "Teknium generated recipient")
    var body = actor.get_node("CoreCapsule").shape
    lab.step_once(); await tick(lab)
    check(str(sim.kit_telemetry(1).presentation.get("activation_id", "")).is_empty(), "held attack suppressed")
    key(KEY_F,false)
    for i in 8:
        lab.step_once(); await tick(lab)
    check(actor.get_node("CoreCapsule").shape == body, "physical body stable across animated ticks")
    check(not lab.select_fighter(1,"ice_mage"), "Ice selection explicitly refused while enabled")
    check(lab.generated_collision_notice.contains("Ice") and lab.selected_fighters[1] == "teknium", "refusal visible and roster unchanged")
    check(lab.select_fighter(1,"turbofit"), "supported roster change")
    lab.step_once(); await tick(lab)
    check(sim.collision_telemetry(2).get("ok",false), "supported change installs matching profile")
    generation = sim.generation
    check(lab.set_generated_collision_enabled(false), "explicit optout")
    check(sim.generation == generation+1 and sim.collision_telemetry(1).geometry_mode == "legacy_body_capsule", "full reset restores compatibility")
    check(lab.select_fighter(1,"ice_mage"), "Ice selectable after optout")
    check(not lab.set_generated_collision_enabled(true) and not lab.generated_collision_enabled, "Ice cannot silently enter generated mode")
    check(lab.generated_collision_notice.contains("Ice"),"unsupported install notice")
    lab.free()
    if not failures: print("PASS: collision lab explicit mode reset roster and input")
    quit(1 if failures else 0)

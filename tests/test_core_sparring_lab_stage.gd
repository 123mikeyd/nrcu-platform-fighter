extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
func run():
	var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
	lab.main_support_shape.position.x = 2
	lab.main_support_shape.shape.size.x = 18
	check(lab.set_p2_input_owner("sparring_easy"), "select with actual altered stage")
	check(lab.sparring_inputs.stage_bounds == {"left":-7.0,"right":11.0,"top":0.0}, "Sparring receives authoritative collider bounds")
	lab.repo_inputs.stage_bounds.left = -99
	check(lab.sparring_inputs.stage_bounds.get("left") == -7.0, "owners do not alias bounds")
	lab.main_support_shape.rotation.z = .1
	var tick = lab.simulation.tick
	await physics_frame; lab._physics_process(1.0/60)
	check(lab.paused and lab.simulation.tick == tick, "unsupported stage pauses before sample/simulation")
	check(lab.sparring_inputs.stage_bounds.is_empty() and lab.repo_inputs.stage_bounds.is_empty(), "invalid geometry clears both owners")
	check(not lab.set_p2_input_owner("repo_ai") and lab.p2_input_owner == "sparring_easy", "invalid stage refuses switching atomically")
	check(not lab.generated_collision_notice.contains("Mikey"), "stage refusal is policy-neutral")
	lab.free()
	if not failures: print("PASS: Sparring authoritative stage geometry")
	quit(1 if failures else 0)

extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
func run():
	var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
	var floor_shape: CollisionShape3D
	for child in lab.get_children():
		if child is StaticBody3D:
			for shape in child.get_children():
				if shape is CollisionShape3D: floor_shape = shape
	check(floor_shape != null, "actual support collider exists")
	var expected := {"left": -12.0, "right": 12.0, "top": 0.0}
	check(lab.repo_inputs.stage_bounds == expected, "ready supplies actual stage before first AI sample")
	lab.set_p2_repo_ai(true)
	for mode in ["grounded_jostle", "legacy_solid"]:
		lab.set_comparison_interaction(mode)
		check(lab.repo_inputs.stage_bounds == expected, "same stage independent of comparison arm")
	floor_shape.shape = floor_shape.shape.duplicate()
	floor_shape.shape.size = Vector3(18, 2, 3)
	floor_shape.position = Vector3(1, .5, 0)
	floor_shape.get_parent().position = Vector3(3, 2, 0)
	floor_shape.get_parent().scale = Vector3(1.5, 2, 1)
	expected = {"left": -9.0, "right": 18.0, "top": 5.0}
	lab.reset_lab()
	check(lab.repo_inputs.stage_bounds == expected, "reset derives world transform and actual changed shape, not descriptor constants")
	var observation: Dictionary = lab.repo_inputs._observation(lab.simulation, 2)
	observation.stage_bounds.left = -999
	check(lab.repo_inputs.stage_bounds == expected, "observation clone cannot mutate configured geometry")
	lab.repo_inputs.stage_bounds = {"left":-1,"right":1,"top":-8}
	await physics_frame; lab._physics_process(1.0/60)
	check(lab.repo_inputs.stage_bounds == expected, "refresh before sampling prevents stale external params")
	lab.set_paused(true)
	var tick = lab.simulation.tick; var seq = lab.repo_inputs.ai.sequence
	await physics_frame; lab._physics_process(1.0/60)
	check(lab.simulation.tick == tick and lab.repo_inputs.ai.sequence == seq, "pause freezes adapted sensing clock")
	lab.step_once(); await physics_frame; lab._physics_process(1.0/60); lab._physics_process(1.0/60)
	check(lab.simulation.tick == tick+1 and lab.repo_inputs.stage_bounds == expected, "single step retains same stage and exactly one tick")
	var mikey_index := -1
	var sparring_index := -1
	for index in lab.p2_input_button.item_count:
		if lab.p2_input_button.get_item_text(index) == "P2: Mikey AI adapted": mikey_index = index
		if lab.p2_input_button.get_item_text(index) == "P2: Sparring / Easy (ours)": sparring_index = index
	check(mikey_index >= 0, "AI selector discloses adapted Mikey AI")
	check(sparring_index >= 0 and sparring_index < mikey_index, "Sparring remains a separate earlier AI choice")
	lab._sync_comparison_controls()
	check(lab.p2_input_button.selected == mikey_index and lab.p2_input_owner == "repo_ai" and lab.repo_inputs.enabled and not lab.sparring_inputs.enabled, "actual Mikey item selected while stage wiring is exercised")
	check("stage sensing" in lab.p2_input_button.tooltip_text, "tooltip discloses stage adaptation")
	floor_shape.rotation.z = .2
	lab.set_paused(false)
	var before = lab.simulation.tick
	await physics_frame; lab._physics_process(1.0/60)
	check(lab.paused and lab.simulation.tick == before, "unsupported stage stops before AI sample instead of silently falling back")
	check("REFUSED" in lab.generated_collision_notice and lab.repo_inputs.stage_bounds.is_empty(), "unsupported stage clears stale bounds and explains refusal")
	lab.set_p2_repo_ai(false)
	check(not lab.set_p2_repo_ai(true), "AI enable refuses unsupported terrain")
	lab.free()
	if not failures: print("PASS: AI lab real stage geometry wiring")
	quit(1 if failures else 0)

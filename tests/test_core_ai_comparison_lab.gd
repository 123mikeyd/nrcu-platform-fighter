extends SceneTree
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; print("FAIL: ", message)
func _init(): call_deferred("run")
func run():
	var lab = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab); lab.set_physics_process(false)
	await process_frame
	check(lab.has_method("set_p2_repo_ai"), "playable lab exposes explicit P2 Human / Repo AI opt-in")
	if not lab.has_method("set_p2_repo_ai"): lab.free(); quit(1); return
	check(not lab.repo_inputs.enabled, "existing two-human default preserved")
	check(lab.set_p2_repo_ai(true), "opt into supported repo AI")
	check(lab.repo_inputs.enabled and lab.ai_difficulty == "normal", "AI normal default")
	check(lab.generated_collision_enabled, "AI comparison installs anatomical contacts")
	check(lab.simulation.fighter_interaction_mode == "grounded_jostle", "accepted new interaction default")
	var profiles = lab.active_collision_profiles.duplicate(true)
	var generation = lab.simulation.generation
	check(lab.set_comparison_interaction("legacy_solid"), "prior solid comparison selectable")
	check(lab.simulation.fighter_interaction_mode == "legacy_solid", "prior solid really installed")
	check(lab.active_collision_profiles == profiles and lab.generated_collision_enabled, "same anatomical contact profiles both arms")
	check(lab.simulation.generation > generation, "mode switch is full reset")
	check(not lab.set_generated_collision_enabled(false), "F5 cannot confound active AI comparison")
	check(not lab.select_fighter(1,"ice_mage"), "unsupported Ice explicitly refused")
	check(lab.set_ai_difficulty("hard") and lab.ai_difficulty == "hard", "actual hard available")
	check(not lab.set_ai_difficulty("impossible"), "invalid difficulty refused")
	check(lab.set_p2_repo_ai(false) and not lab.repo_inputs.enabled, "human ownership restored")
	lab.free()
	if not failures: print("PASS: playable AI comparison ownership and equal contacts")
	quit(1 if failures else 0)

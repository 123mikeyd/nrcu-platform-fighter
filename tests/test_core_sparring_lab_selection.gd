extends SceneTree
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; print("FAIL: ", message)
func _init(): call_deferred("run")
func run():
	var lab = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab); lab.set_physics_process(false)
	check(lab.has_method("set_p2_input_owner"), "lab offers distinct Sparring owner")
	if not lab.has_method("set_p2_input_owner"): lab.free(); quit(1); return
	check(lab.p2_input_owner == "human", "preserve two-human initial mode")
	check(lab.p2_input_button.get_item_text(1).contains("Sparring"), "first AI recommendation is Sparring")
	check(lab.set_p2_input_owner("sparring_easy"), "select practice owner")
	lab._sync_comparison_controls()
	check(lab.sparring_inputs.enabled and not lab.repo_inputs.enabled, "exclusive AI ownership")
	check(lab.ai_difficulty_button.disabled and lab.ai_difficulty_button.selected == 0, "Sparring fixed Easy shown disabled")
	check(not lab.set_ai_difficulty("hard") and lab.ai_difficulty == "normal", "Sparring cannot retune Mikey")
	check(lab._roster_help_text().contains("Sparring") and not lab._roster_help_text().contains("P2 Repo AI"), "honest practice help")
	check(not lab.set_generated_collision_enabled(false), "comparison contacts remain identical")
	check(not lab.select_fighter(1,"ice_mage"), "Ice remains explicitly unsupported")
	var profiles = lab.active_collision_profiles.duplicate(true)
	check(lab.set_comparison_interaction("legacy_solid") and lab.active_collision_profiles == profiles, "same profiles in both comparison arms")
	check(lab.set_p2_input_owner("repo_ai") and lab.ai_difficulty == "normal", "Mikey unchanged normal survives practice")
	lab._sync_comparison_controls()
	check(not lab.ai_difficulty_button.disabled and lab.set_ai_difficulty("hard"), "Mikey difficulties remain available")
	check(lab.set_p2_input_owner("human"), "restore human")
	lab.free()
	if not failures: print("PASS: separate Sparring lab selection")
	quit(1 if failures else 0)

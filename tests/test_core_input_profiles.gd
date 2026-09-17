extends SceneTree
const Source = preload("res://scripts/core/input/player_input_source.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var one = Source.new()
	if not one.has_method("save_profile"):
		push_error("profile persistence missing")
		quit(1)
		return
	var path := "user://test_core_input_profiles.cfg"
	DirAccess.remove_absolute(path)
	one.bindings.jump = KEY_Z
	one.pad_bindings.jump = JOY_BUTTON_Y
	one.deadzone = 0.33
	one.tap_jump = true
	check(one.save_profile(path) == OK, "save first slot")
	var two = Source.new()
	two.slot = 1
	two.bindings.attack = KEY_P
	check(two.save_profile(path) == OK, "save second slot preserves first")
	var copy = Source.new()
	check(copy.load_profile(path) == OK, "load first slot")
	check(copy.bindings.jump == KEY_Z and copy.pad_bindings.jump == JOY_BUTTON_Y, "keyboard and pad rebind persisted")
	check(is_equal_approx(copy.deadzone, 0.33) and copy.tap_jump, "settings persisted")
	copy.slot = 1
	check(copy.load_profile(path) == OK and copy.bindings.attack == KEY_P, "independent slot")
	check(copy.load_profile("user://not_existing_core_profile.cfg") == ERR_FILE_NOT_FOUND, "missing returns safe error")
	var cfg := ConfigFile.new()
	cfg.set_value("player_1", "deadzone", "bad")
	cfg.save(path)
	check(copy.load_profile(path) == ERR_INVALID_DATA and copy.bindings.attack == KEY_P, "invalid data does not partially mutate profile")
	check(one.save_profile("user://absent_input_dir/settings.cfg") != OK, "write errors propagated")
	DirAccess.remove_absolute(path)
	if failures == 0: print("PASS core input profiles")
	quit(failures)

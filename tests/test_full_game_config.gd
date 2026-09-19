extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var path = "res://scripts/experimental/full_game_config.gd"
	if not ResourceLoader.exists(path):
		print("FAIL: opt-in full game configuration is missing")
		quit(1)
		return
	var config = load(path).new()
	assert(config.validate(["teknium", "turbofit"], "toy_room", "sparring_easy").is_empty())
	for id in ["doge_man", "ggb", "ice_mage", "witcheer", "mephisto", "invalid"]:
		assert(not config.validate([id, "teknium"], "toy_room", "sparring_easy").is_empty())
	assert(not config.validate(["teknium", "turbofit"], "sky", "sparring_easy").is_empty())
	assert(not config.validate(["teknium"], "toy_room", "human").is_empty())
	assert(not config.validate(["teknium", "turbofit"], "toy_room", "unknown").is_empty())
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/title.tscn")
	print("PASS: full game opt-in configuration")
	quit()

extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failures += 1
func _initialize() -> void:
	var lab = load("res://scripts/tools/collision_authoring_lab.gd").new()
	var expected := PackedStringArray()
	for id in ["doge_man", "ggb", "ice_mage", "mephisto", "teknium", "turbofit", "witcheer"]:
		expected.append("res://data/collision/generated/" + id + ".tres")
	check(lab.discover_profiles("res://data/collision") == expected, "exact seven canonical sorted exported profiles")
	var directory := "user://remap_discovery_regression"
	DirAccess.make_dir_recursive_absolute(directory)
	var p = load(expected[0]).duplicate(true)
	ResourceSaver.save(p, directory + "/z.tres")
	ResourceSaver.save(p, directory + "/a.tres")
	var f = FileAccess.open(directory + "/a.tres.remap", FileAccess.WRITE)
	f.store_string('[remap]\npath="' + directory + '/a.tres"\n'); f.close()
	f = FileAccess.open(directory + "/missing.tres.remap", FileAccess.WRITE)
	f.store_string('[remap]\npath="user://does-not-exist.res"\n'); f.close()
	check(lab.discover_profiles(directory) == PackedStringArray([directory + "/a.tres",directory + "/z.tres"]), "deduplicates remap and source; excludes unresolved canonical path")
	lab.free()
	quit(1 if failures else 0)

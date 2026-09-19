extends SceneTree
var failures := 0
func check(ok: bool, msg: String):
	if not ok: failures += 1; printerr("FAIL: ",msg)
func _init():
	var p = load("res://scripts/core/collision/character_collision_profile.gd").new()
	p.character_id = "fixture"; p.body_radius = 0.25; p.body_height = 2.0; p.body_center = Vector3(0,1,0)
	check(p.has_method("merged_with"), "separate manual override merge exists")
	var g = load("res://scripts/tools/generate_character_collisions.gd").new()
	check(g.has_method("write_generated"), "protected deterministic writer exists")
	if p.has_method("merged_with") and g.has_method("write_generated"):
		var o = p.duplicate(true); o.manual_override = true; o.override_fields = PackedStringArray(["body_radius"]); o.body_radius = 0.35
		var m: Dictionary = p.merged_with(o)
		check(m.errors.is_empty() and m.profile.body_radius == 0.35 and p.body_radius == 0.25, "explicit merge preserves manual field without mutating generated")
		p.body_radius = 0.3
		check(p.merged_with(o).profile.body_radius == 0.35, "regeneration keeps manual radius")
		o.override_fields.append("source_asset")
		check(not p.merged_with(o).errors.is_empty(), "unsupported metadata override rejected")
		o.override_fields = PackedStringArray(["body_radius"]); o.body_radius = NAN
		check(not p.merged_with(o).errors.is_empty(), "invalid overrides rejected")
		var path := "user://collision-generator-fixture.tres"
		DirAccess.remove_absolute(path)
		var first: Dictionary = g.write_generated(path,p,"")
		check(first.errors.is_empty(), "save generated resource")
		var initial := FileAccess.get_file_as_string(path)
		check(g.write_generated(path,p,first.sha256).errors.is_empty(), "known unmodified file regenerates")
		check(FileAccess.get_file_as_string(path) == initial, "output byte deterministic")
		var saved = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(saved.body_radius == p.body_radius, "saved resource loads with schema")
		var f := FileAccess.open(path,FileAccess.WRITE); f.store_string(initial+"\n; hand edit\n"); f.close()
		check(not g.write_generated(path,p,first.sha256).errors.is_empty(), "hand edited generated file refused")
		check("hand edit" in FileAccess.get_file_as_string(path), "hand edit remains untouched")
		DirAccess.remove_absolute(path)
	g.free()
	if failures == 0: print("PASS: core collision generator overrides")
	quit(1 if failures else 0)

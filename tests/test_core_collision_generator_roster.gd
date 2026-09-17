extends SceneTree
var failures := 0
func check(ok: bool, msg: String):
	if not ok: failures += 1; printerr("FAIL: ",msg)
func _init(): call_deferred("run")
func run():
	var g = load("res://scripts/tools/generate_character_collisions.gd").new()
	check(g.has_method("generate_roster"), "roster CLI saves profiles and manifest")
	if g.has_method("generate_roster"):
		var output := "user://collision-generator-roster"
		var summary: Dictionary = g.generate_roster(root,output)
		var ids: Array = load("res://scripts/roster.gd").ids()
		check(summary.roster_count == ids.size() and summary.entries.size() == ids.size(), "all actual roster IDs accounted")
		check(summary.generated_count+summary.failed_count == summary.unique_count, "exact analyzed/failed counts")
		var available := 0
		for id in ids:
			var meta: Dictionary = g.source_metadata(id)
			if not meta.errors.is_empty(): continue
			var f := FileAccess.open(meta.asset, FileAccess.READ)
			if f and f.get_buffer(4).get_string_from_ascii() == "glTF": available += 1
		check(summary.generated_count == available, "every installed GLB saved and reloaded; sphere rounding valid")
		var hashes := {}
		for e in summary.entries:
			if e.status == "generated":
				var p = ResourceLoader.load(e.profile,"",ResourceLoader.CACHE_MODE_IGNORE)
				check(p.source_sha256 == FileAccess.get_sha256(e.asset), "source fingerprint "+e.id)
				hashes[e.profile] = FileAccess.get_sha256(e.profile)
		var again: Dictionary = g.generate_roster(root,output)
		check(again.generated_count == summary.generated_count, "repeat generation counts unchanged")
		for path in hashes: check(hashes[path] == FileAccess.get_sha256(path), "deterministic full profile "+path)
		check(FileAccess.file_exists(output+"/manifest.json"), "saved manifest")
	g.free()
	if failures == 0: print("PASS: core collision generator roster")
	quit(1 if failures else 0)

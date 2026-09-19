extends SceneTree
# Run against the exported PCK from an output-only --path, never staging.
var failures := 0
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failures += 1
func _initialize() -> void:
	for id in ["teknium", "turbofit"]:
		var profile = load("res://data/collision/generated/" + id + ".tres")
		check(FileAccess.file_exists(profile.source_asset), id + " raw source in pack")
		check(FileAccess.get_sha256(profile.source_asset) == profile.source_sha256, id + " exact raw identity")
		var host = load("res://scripts/core/collision/collision_host.gd").new()
		check(host.configure(profile, "export-regression").is_empty(), id + " accepted generated source")
		var invalid = profile.duplicate(true)
		invalid.source_asset = "res://missing-collision-source.glb"
		check(not host.configure(invalid, "missing").is_empty(), id + " missing raw source rejected")
		invalid = profile.duplicate(true)
		invalid.source_sha256 = "0".repeat(64)
		check(not host.configure(invalid, "mismatch").is_empty(), id + " mismatched hash rejected")
	quit(1 if failures else 0)

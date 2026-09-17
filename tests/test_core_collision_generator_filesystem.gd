extends SceneTree
const G = preload("res://scripts/tools/generate_character_collisions.gd")
const BASE = "res://.verification/core/collision-generator-fs-fix"
var failures := 0
var work: String
func check(ok: bool, message: String):
	if not ok: failures += 1; printerr("FAIL: ", message)
func _init(): call_deferred("run")
func run():
	work = BASE.path_join("run-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(DirAccess.make_dir_recursive_absolute(work) == OK, "isolated fixture directory")
	var output := work.path_join("manifest-directory")
	DirAccess.make_dir_recursive_absolute(output.path_join("manifest.json"))
	var summary := G.generate_roster(root, output)
	check(summary.failed_count == summary.unique_count and summary.generated_count == 0, "manifest directory fails whole batch before generating")
	check(not summary.get("errors", []).is_empty(), "manifest failure explicit in API result")
	check(DirAccess.get_files_at(output).is_empty(), "manifest preflight leaves no unowned generated files")
	output = work.path_join("cli-manifest-directory")
	DirAccess.make_dir_recursive_absolute(output.path_join("manifest.json"))
	var logs := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(work.path_join("cli.engine.log")), "--script", "scripts/tools/generate_character_collisions.gd", "--", "--generate", "--output=" + output], logs, true)
	check(code != 0, "manifest directory CLI exit nonzero")
	var log_file := FileAccess.open(work.path_join("cli.stdout.log"), FileAccess.WRITE)
	log_file.store_string("exit=%s\n%s" % [code, "\n".join(logs)]); log_file.close()
	_test_candidates()
	_test_path_aliases()
	_test_late_manifest_failure()
	_test_hardlink_replacement()
	_test_regeneration()
	if failures == 0: print("PASS: core collision generator filesystem")
	quit(1 if failures else 0)

func _put(path: String, text: String):
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture writable: " + path)
	if file: file.store_string(text); file.close()

func _profile() -> Resource:
	var p = load("res://scripts/core/collision/character_collision_profile.gd").new()
	p.character_id = "fixture"; p.body_radius = 0.25; p.body_height = 2.0; p.body_center = Vector3(0, 1, 0)
	return p

func _test_candidates():
	var p := _profile()
	var path := work.path_join("sentinel.tres")
	var candidate := path + ".candidate.tres"
	_put(candidate, "HAND AUTHORED SENTINEL")
	var result := G.write_generated(path, p, "")
	check(result.errors.is_empty(), "unused legacy candidate does not block safe write")
	check(FileAccess.file_exists(candidate), "preexisting candidate sentinel not deleted")
	if FileAccess.file_exists(candidate): check(FileAccess.get_file_as_string(candidate) == "HAND AUTHORED SENTINEL", "preexisting candidate sentinel unchanged")
	var source := work.path_join("source-sentinel.txt")
	_put(source, "SOURCE SENTINEL")
	path = work.path_join("symlink-output.tres"); candidate = path + ".candidate.tres"
	var dir := DirAccess.open(work)
	check(dir.create_link(ProjectSettings.globalize_path(source), candidate.get_file()) == OK, "candidate symlink fixture")
	result = G.write_generated(path, p, "")
	check(result.errors.is_empty(), "legacy candidate symlink is never used")
	check(dir.is_link(candidate.get_file()), "preexisting candidate symlink not removed")
	check(FileAccess.get_file_as_string(source) == "SOURCE SENTINEL", "candidate symlink target source unchanged")

func _test_regeneration():
	var output := work.path_join("successful-roster")
	var first := G.generate_roster(root, output)
	check(first.generated_count == 7 and first.failed_count == 0, "successful seven-profile batch")
	var manifest := output.path_join("manifest.json")
	var initial := FileAccess.get_file_as_string(manifest)
	var second := G.generate_roster(root, output)
	check(second.generated_count == 7 and second.failed_count == 0, "successful regeneration")
	check(FileAccess.get_file_as_string(manifest) == initial, "complete manifest byte deterministic")
	for entry in first.entries:
		check(FileAccess.get_sha256(entry.profile) == entry.sha256, "deterministic profile hash: " + entry.id)
		check(ResourceLoader.load(entry.profile, "", ResourceLoader.CACHE_MODE_IGNORE).validate().is_empty(), "final published valid resource: " + entry.id)
	var edited = first.entries[0]
	var text := FileAccess.get_file_as_string(edited.profile) + "\n; hand edit\n"
	_put(edited.profile, text)
	var refused := G.generate_roster(root, output)
	check(refused.failed_count == 1 and refused.generated_count == 6, "ordinary hand-edit remains per-entry refusal")
	check(FileAccess.get_file_as_string(edited.profile) == text, "hand-edited output untouched")
	var receipt = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	check(receipt.entries[0].sha256 == edited.sha256 and receipt.entries[0].status == "failed", "refusal retains last good hash, never blesses edited bytes")

func _test_hardlink_replacement():
	var source := work.path_join("hardlink-source.tres")
	check(ResourceSaver.save(_profile(), source) == OK, "hardlink valid source")
	var original := FileAccess.get_file_as_string(source)
	var path := work.path_join("hardlink-output.tres")
	check(OS.execute("ln", [ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(path)]) == 0, "hardlink fixture")
	var changed := _profile(); changed.body_radius = 0.35
	var result := G.write_generated(path, changed, FileAccess.get_sha256(path))
	check(result.errors.is_empty(), "known output can replace directory entry")
	check(FileAccess.get_file_as_string(source) == original, "publication never truncates hardlinked source inode")
	check(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).body_radius == 0.35, "replacement readback matches changed resource")

func _test_late_manifest_failure():
	var output := work.path_join("late-manifest")
	# Real I/O failure after preflight, on first imported model instantiation.
	root.child_entered_tree.connect(func(_node):
		DirAccess.make_dir_absolute(output.path_join("manifest.json"))
	, CONNECT_ONE_SHOT)
	var summary := G.generate_roster(root, output)
	check(summary.generated_count == 0 and summary.failed_count == summary.unique_count, "late manifest failure cannot claim batch success")
	check(not summary.get("errors", []).is_empty(), "late manifest failure explicit")
	var recovery: String = summary.get("recovery_manifest", "")
	check(not recovery.is_empty() and FileAccess.file_exists(recovery), "late manifest failure retains recoverable hash receipt")
	if not recovery.is_empty() and FileAccess.file_exists(recovery):
		var receipt = JSON.parse_string(FileAccess.get_file_as_string(recovery))
		check(receipt.entries.size() == 7, "recovery records all seven artifacts")
		for entry in receipt.entries:
			check(FileAccess.get_sha256(entry.profile) == entry.sha256, "recovery hash identifies actual saved bytes: " + entry.id)
	check(DirAccess.dir_exists_absolute(output.path_join("manifest.json")), "late manifest obstruction preserved")

func _test_path_aliases():
	var source := work.path_join("protected.tres")
	check(ResourceSaver.save(_profile(), source) == OK, "valid protected resource")
	var original := FileAccess.get_file_as_string(source)
	var dir := DirAccess.open(work)
	check(dir.create_link(ProjectSettings.globalize_path(source), "target-alias.tres") == OK, "target alias fixture")
	var changed := _profile(); changed.body_radius = 0.3
	var result := G.write_generated(work.path_join("target-alias.tres"), changed, FileAccess.get_sha256(source))
	check(not result.errors.is_empty(), "target symlink rejected even with known hash")
	check(FileAccess.get_file_as_string(source) == original, "protected symlink resource unchanged")
	var protected_dir := work.path_join("protected-dir")
	DirAccess.make_dir_absolute(protected_dir)
	check(dir.create_link(ProjectSettings.globalize_path(protected_dir), "ancestor-alias") == OK, "ancestor alias fixture")
	result = G.write_generated(work.path_join("ancestor-alias/new/sub/fixture.tres"), changed, "")
	check(not result.errors.is_empty(), "writer rejects symlink at any ancestor")
	check(not DirAccess.dir_exists_absolute(protected_dir.path_join("new")), "writer validates before mkdir")
	for kind in ["output", "ancestor", "manifest", "target", "dangling", "directory-target", "dotdot"]:
		var output := work.path_join("alias-" + kind)
		DirAccess.make_dir_absolute(output)
		var out_dir := DirAccess.open(output)
		if kind == "output" or kind == "ancestor":
			check(out_dir.create_link(ProjectSettings.globalize_path(protected_dir), "link") == OK, "output alias fixture")
			output = output.path_join("link" if kind == "output" else "link/deep/new")
		elif kind == "manifest":
			check(out_dir.create_link(ProjectSettings.globalize_path(source), "manifest.json") == OK, "manifest alias fixture")
		elif kind == "target" or kind == "dangling":
			check(out_dir.create_link(ProjectSettings.globalize_path(source if kind == "target" else work.path_join("missing-source.tres")), "witcheer.tres") == OK, "last target alias fixture")
		elif kind == "directory-target": DirAccess.make_dir_absolute(output.path_join("witcheer.tres"))
		else:
			check(out_dir.create_link(ProjectSettings.globalize_path(protected_dir), "link") == OK, "dotdot alias fixture")
			output = output.path_join("link/../escaped")
		var summary := G.generate_roster(root, output)
		check(summary.generated_count == 0 and summary.failed_count == summary.unique_count, "all paths preflight before roster writes: " + kind)
		check(not FileAccess.file_exists(output.path_join("doge_man.tres")), "no earlier target written: " + kind)
		check(not summary.get("errors", []).is_empty(), "explicit path rejection: " + kind)
	check(FileAccess.get_file_as_string(source) == original, "all alias probes preserve protected resource")
	check(DirAccess.get_files_at(protected_dir).is_empty() and DirAccess.get_directories_at(protected_dir).is_empty(), "output aliases never write through protected ancestor")

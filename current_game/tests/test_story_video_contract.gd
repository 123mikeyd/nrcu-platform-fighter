extends SceneTree
var failures := 0
func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := "res://scripts/story_video.gd"
	if not ResourceLoader.exists(path):
		print("FAIL: story video player missing")
		quit(1)
		return
	var script: Script = load(path)
	if not script or not script.can_instantiate():
		quit(1)
		return
	var video = script.new()
	root.add_child(video)
	await process_frame
	check(video.has_method("cancel") and video.has_method("skip"), "explicit cancellation and skip")
	for id in ["witcheer_unlock", "turbofit_celebration", "basilisk_credits"]:
		check(ResourceLoader.exists(script.CLIPS[id]), "real installed path " + id)
	var credits: Script = load("res://scripts/story_credits.gd")
	check(credits.NAMES == ["123mikeyD", "Hermes Agent", "GPT Astra & Claude Opus", "Quark2World", "Arts Bro"], "exact credited names")
	var text := str(credits.SECTIONS)
	var titles := {}
	var mike_roles := 0
	var hermes_roles := 0
	for section in credits.SECTIONS:
		check(not titles.has(section[0]), "role title appears once: " + section[0])
		titles[section[0]] = true
		if section[1] == "123mikeyD": mike_roles += 1
		if section[1] == "Hermes Agent": hermes_roles += 1
	check(mike_roles == 8 and hermes_roles == 4, "intentional recurring names under role-first headings")
	for phrase in ["Game State Controller Coordinator", "UI/UX & Additional Art Assistance", "Sounds", "Core Development", "Architecture & Systems Design", "Nous Research community"]:
		check(phrase in text, "approved credit " + phrase)
	video.queue_free()
	await process_frame
	print("PASS: story video contract" if failures == 0 else "FAIL: %d checks" % failures)
	quit(0 if failures == 0 else 1)

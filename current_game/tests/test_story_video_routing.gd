extends SceneTree
const U = preload("res://scripts/unlocks.gd")
var checks := 0
var failures := 0
var arena
func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1
func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-16000, -16000)
	call_deferred("run")
func win() -> void:
	arena._cancel_ready()
	arena.player_two.stocks = 0
	arena._on_fighter_eliminated(arena.player_two)
func run() -> void:
	U.path_override = OS.get_user_data_dir().path_join("video_route_test.json")
	var file := FileAccess.open(U.path_override, FileAccess.WRITE)
	file.store_string('{"sentinel":"preserve","versus_matches":17,"unlocked":["ggb"]}')
	file.close()
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.open_story()
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == "teknium": arena.story_character.select(i)
	arena.story_action.pressed.emit()
	await process_frame
	check(arena.story_state == "playing" and not arena.story_video.active, "ordinary Bobo encounter has no Turbo movie")
	arena.story_vs.skip()
	# Exercise real next-encounter/start buttons through the route.
	while arena.story_encounter < arena.story_route.size() - 1:
		win()
		await process_frame
		arena.story_action.pressed.emit()
		await process_frame
		arena.story_action.pressed.emit()
		await process_frame
		if arena.story_opponent() == "turbofit":
			check(arena.story_video.active and arena.story_video.clip_id == "turbofit_celebration", "Turbo entrance routes supplied short")
			check(paused and not arena.player_one.controls_enabled, "fight is paused during entrance")
			var ready: float = arena.ready_remaining
			await create_timer(0.2).timeout
			check(is_equal_approx(ready, arena.ready_remaining), "READY cannot expire behind video")
			arena.story_video.skip()
			check(not paused and arena.story_vs.visible, "skip continues to VS, not results")
			arena.story_vs.skip()
			arena._cancel_ready()
			arena.player_one.stocks = 0
			arena._on_fighter_eliminated(arena.player_one)
			arena.story_action.pressed.emit()
			check(arena.story_video.active, "Turbo retry still gets its entrance")
			arena.story_video.skip()
			check(not arena.story_vs.visible and arena.ready_label.visible, "retry hands back to READY")
		arena.story_vs.skip()
	win()
	await process_frame
	await process_frame
	check(U.story_clears() == 1 and arena.story_state == "complete", "clear committed before any credits")
	check(arena.story_ending._hero == "teknium", "actual hero passed into ending")
	arena.story_ending._motion.kill()
	arena.story_ending._begin_movies()
	check(arena.story_ending.movie.clip_id == "basilisk_credits" and arena.story_ending.is_rolling(), "non-Turbo clear plays Basilisk alongside credits")
	check(not arena.challenger_screen.visible and not arena.story_panel.visible, "results/challenger wait for credits")
	arena.story_ending.movie.skip()
	check(not paused and arena.story_panel.visible, "credits skip returns to completed run")
	check(arena.story_ending.movie.player.stream == null, "credits audio and decoder released")
	await create_timer(1.8).timeout
	check(arena.challenger_screen.challenger_id == "witcheer", "normal earned challenger preserved")
	arena.challenger_screen.primary.pressed.emit()
	await process_frame
	win()
	check(U.earned("witcheer") and arena.story_video.active, "first Witcheer unlock commits then plays supplied movie")
	check(arena.story_video.clip_id == "witcheer_unlock", "Witcheer exact resource route")
	arena.story_video.skip()
	check(arena.challenger_screen.mode == "joined" and not paused, "unlock skip returns to joined card")
	arena.start_challenger("witcheer")
	await process_frame
	win()
	check(not arena.story_video.active, "already earned Witcheer does not replay unlock movie")
	# Test the final result sink AS Turbo, not merely versus Turbo.
	arena.show_setup()
	arena.open_story()
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == "turbofit": arena.story_character.select(i)
	arena.story_action.pressed.emit()
	arena.story_vs.skip()
	arena.story_encounter = arena.story_route.size() - 1
	win()
	await process_frame
	await process_frame
	check(U.story_clears() == 2 and "turbofit" in U.story_heroes(), "Turbo progression committed once")
	arena.story_ending._motion.kill()
	arena.story_ending._begin_movies()
	check(arena.story_ending.phase == "celebration" and not arena.story_ending.is_rolling(), "Turbo short precedes shared credits")
	arena.story_ending.movie.skip()
	check(arena.story_ending.phase == "credits" and arena.story_ending.movie.clip_id == "basilisk_credits", "skipping Turbo short still starts shared Basilisk")
	arena.show_setup()
	check(not paused and not arena.story_ending.visible and not arena.story_ending.movie.active, "setup cancels credits and restores pause state")
	check(arena.story_ending.movie.player.stream == null and not arena.story_panel.visible, "cancellation cannot resurrect completion callbacks")
	var saved := U._load()
	check(saved.get("sentinel") == "preserve" and saved.get("versus_matches") == 17, "unrelated save fields preserved")
	check(saved.get("story_clears") == 2, "skips/cancel never double-count progression")
	# Any allowed Story hero gets the common ending; no new roster permissions.
	for hero in arena._story_playable_ids():
		arena.story_ending.play(hero)
		arena.story_ending._motion.kill()
		arena.story_ending._begin_movies()
		if hero == "turbofit": arena.story_ending.movie.skip()
		check(arena.story_ending.movie.clip_id == "basilisk_credits", "shared credits route for " + hero)
		arena.story_ending.cancel()
	arena.story_video.play_clip("turbofit_celebration")
	arena.show_setup()
	check(not paused and arena.story_video.player.stream == null, "setup cancels a standalone short silently")
	arena.queue_free()
	await process_frame
	check(not paused, "scene teardown leaves tree unpaused")
	U.path_override = ""
	print("%s: story video routing %d checks / %d failed" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

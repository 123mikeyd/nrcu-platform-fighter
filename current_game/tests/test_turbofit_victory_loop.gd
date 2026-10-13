extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func run():
	# Isolate result replay from earned challenger interrupts and real progress.
	var unlocks = load("res://scripts/unlocks.gd")
	unlocks.path_override = "user://turbo_victory_test_unlocks.json"
	unlocks.bag_path_override = "user://turbo_victory_test_bag.json"
	FileAccess.open(unlocks.path_override, FileAccess.WRITE).store_string(JSON.stringify({"unlocked": unlocks.CHALLENGERS}))
	var screen = load("res://scripts/victory_screen.gd").new()
	root.add_child(screen)
	await process_frame
	for attempt in 2:
		screen.show_results([{"id": "turbofit"}], [{"id": "turbofit"}], "TURBOFIT WINS!")
		var winner: Dictionary = screen.actors[0]
		var loser: Dictionary = screen.actors[1]
		var player: AnimationPlayer = winner.player
		var clap: Animation = loser.player.get_animation("victory/VictoryClap")
		check(winner.get("clip") == "victory/VictoryClap", "winner uses exact loser clap")
		check(clap.loop_mode == Animation.LOOP_LINEAR, "source clap is linear loop")
		check(player.get_animation("victory/VictoryClap") == clap, "same immutable clip resource")
		var wraps := 0
		var previous := 0.0
		var moving := 0
		var skeleton: Skeleton3D = winner.visual.find_children("*", "Skeleton3D", true, false)[0]
		var hand := skeleton.find_bone("mixamorig_LeftHand")
		check(hand >= 0, "native hand bone found")
		var last_pose: Quaternion = skeleton.get_bone_pose_rotation(hand)
		var duration: float = maxf(clap.length * 3.2, player.get_animation("victory/VictoryPose").length + 2.0)
		print("CLIP length=", clap.length, " old_freeze=", player.get_animation("victory/VictoryPose").length, " observation=", duration)
		# AnimationPlayer advances in process time, not a fixed 60 rendered FPS.
		var observed_seconds := 0.0
		while observed_seconds < duration:
			await process_frame
			observed_seconds += root.get_process_delta_time()
			var pos := player.current_animation_position
			if pos < previous: wraps += 1
			previous = pos
			var pose := skeleton.get_bone_pose_rotation(hand)
			if pose.angle_to(last_pose) > 0.0001: moving += 1
			last_pose = pose
		check(wraps >= 3, "winner crosses three loop boundaries")
		check(player.is_playing() and player.current_animation == "victory/VictoryClap", "winner still claps after old freeze time")
		check(moving > 30, "evaluated hand continues moving")
		check(loser.player.is_playing(), "loser keeps clapping")
		check(screen.winner_frozen(), "looping winner satisfies settled result contract")
		print("LOOP attempt=", attempt, " wraps=", wraps, " moving_frames=", moving)
		if DisplayServer.get_name() != "headless" and OS.get_environment("VICTORY_CAPTURE_DIR") != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("VICTORY_CAPTURE_DIR") + "/turbo_clap_%d.png" % attempt)
		screen.clear()
		await process_frame
		check(not is_instance_valid(player) and screen.actors.is_empty() and not screen.visible, "exit frees actors and viewport")
	for id in ["doge_man", "witcheer", "teknium"]:
		screen.show_results([{"id": id}], [{"id": "turbofit"}], "RESULT")
		for f in 600: await process_frame
		var actor: Dictionary = screen.actors[0]
		check(screen.winner_frozen(), id + " settles")
		check(actor.player.is_playing() == (id == "teknium"), id + " preserves freeze/dance policy")
		check(screen.actors[1].player.is_playing(), "Turbo loser unaffected beside " + id)
		screen.clear()
		await process_frame
	screen.queue_free()
	await process_frame
	# Result fixtures use the production stock-elimination route, not direct UI spawn.
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var slots: Array = load("res://scripts/match_config.gd").default_slots()
	slots[0].character = "turbofit"
	slots[1].character = "doge_man"
	slots[1].kind = "human"
	slots[1].device = -2
	slots[2].kind = "empty"
	slots[3].kind = "empty"
	check(arena.start_match(slots, false), "ordinary match configured")
	for round_index in 2:
		arena._cancel_ready()
		for fighter in arena.fighters: fighter.set_physics_process(false)
		for stock in 3: arena.player_two._handle_blast_zone()
		await process_frame
		check(arena.match_over and arena.victory_screen.visible, "stock result shows victory")
		var result_actor: Dictionary = arena.victory_screen.actors[0]
		check(result_actor.id == "turbofit" and result_actor.get("clip") == "victory/VictoryClap", "ordinary winner routing selects Turbo clap")
		for f in 240: await process_frame
		check(result_actor.player.is_playing(), "ordinary result continues clapping")
		arena.result_panel.get_node("Rematch").pressed.emit()
		await process_frame
		check(not arena.match_over and not arena.victory_screen.visible and arena.player_one.stocks == 3, "Rematch clears result and resets stocks")
	arena.show_setup()
	check(arena.setup.visible and not arena.victory_screen.visible, "setup exit clears result")
	arena.queue_free()
	await process_frame
	print("TURBO_VICTORY_COMPLETE checks=", checks, " failures=", failures)
	print("TURBO_VICTORY_COMPLETE");quit(failures)

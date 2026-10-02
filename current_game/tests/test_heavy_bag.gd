extends SceneTree
# Heavy Bag mini-game: entry, scoring through real moves, stationary bag, no gameplay
# text for the bag, timer end -> results, best score save, retry, clean exit.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if ok: print("ok   " + msg)
	else: failures += 1; printerr("FAIL: " + msg)
func wait(n: int) -> void:
	for i in n: await physics_frame
func go(arena) -> void:
	while arena.ready_remaining > 0.0 or arena.go_remaining > 0.0: await physics_frame
func run() -> void:
	var test_save := "user://heavy_bag_best_TEST.json"
	if FileAccess.file_exists(test_save): DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena); await process_frame
	var button = arena.setup.find_child("HeavyBagButton", true, false)
	check(button != null, "setup has a Heavy Bag button")
	button.pressed.emit()
	await process_frame
	check(arena.story_panel.visible and arena.story_state == "bag_ready", "Heavy Bag intro panel opens")
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == "doge_man": arena.story_character.select(i)
	arena.story_action.pressed.emit()
	await process_frame
	var mode = arena.heavy_bag_mode
	check(is_instance_valid(mode) and arena.story_state == "bag_playing", "round starts")
	mode.save_path = test_save
	var bag = arena.player_two
	check(bag.has_method("is_heavy_bag") and arena.fighters.size() == 2, "opponent is the heavy bag (2 actors)")
	check(arena.player_one.character_id == "doge_man", "selected fighter is P1")
	await go(arena)
	var t0: float = mode.time_left
	await wait(30)
	check(mode.time_left < t0, "timer runs after GO")
	arena._process(0.0)
	check(arena.hud_labels[1].text == "", "no HUD text for the bag")
	check(not bag.get_node("PlayerLabel").visible, "no over-head label on the bag")
	var bag_x: float = bag.global_position.x
	# Real moves: Doge side basic and side special.
	var p = arena.player_one
	for spec in [["b", Vector2(1, 0)], ["s", Vector2(1, 0)], ["b", Vector2(0, 1)]]:
		p.reset_fighter(Vector3(bag_x - 1.15, 1.0, 0), false); p.facing = 1.0
		await wait(20)
		if spec[0] == "b": p.basic_attack(spec[1], false)
		else:
			p.start_special(spec[1]); await wait(12); p.release_special()
		await wait(90)
	check(mode.hits >= 3 and mode.score > 0, "real moves score on the bag (hits %d, score %d)" % [mode.hits, mode.score])
	check(absf(bag.global_position.x - bag_x) < 0.01 and bag.stocks > 0 and bag.damage_percent == 0.0, "bag stays put, takes no damage or stocks")
	# Combo multiplier: hits inside the window chain.
	var before: int = mode.score
	mode.since_hit = 99.0; mode.chain = 0
	for i in 5:
		bag.hit_source = p
		bag.receive_hit(5.0, Vector3.RIGHT, 1.0)
		await wait(3)
	check(mode.best_chain >= 5 and mode.score - before > 50, "fast hits chain into a combo multiplier (%d)" % (mode.score - before))
	var score: int = mode.score
	mode.time_left = 0.05
	await wait(10)
	check(arena.story_state == "bag_done" and arena.story_panel.visible and arena.match_over, "time up -> results screen")
	check(arena.story_detail.text.find("SCORE  %d" % score) >= 0, "results show the score")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(test_save))
	check(saved is Dictionary and int(saved.get("doge_man", 0)) == score, "best score saved per fighter")
	check(arena.story_title.text == "NEW BEST!", "first run is a new best")
	# Retry
	arena.story_action.pressed.emit()
	await process_frame
	check(arena.story_state == "bag_playing" and is_instance_valid(arena.heavy_bag_mode) and arena.heavy_bag_mode != mode, "TRY AGAIN starts a fresh round")
	arena.heavy_bag_mode.save_path = test_save
	await go(arena)
	arena.heavy_bag_mode.time_left = 0.05
	await wait(10)
	check(arena.story_title.text == "TIME!" and arena.story_detail.text.find("BEST  %d" % score) >= 0, "a lower score keeps the old best")
	# Breakable layers: big hits break shells, then shatter the core -> early finish with bonus.
	arena.story_action.pressed.emit()
	await process_frame
	var m3 = arena.heavy_bag_mode
	m3.save_path = test_save
	bag = arena.player_two
	p = arena.player_one
	await go(arena)
	check(bag.shell_index == 0 and bag.visible and bag.bag.visible, "fresh round starts with all layers")
	var r0: float = bag.body_mesh.top_radius
	var guard := 0
	while bag.shell_index == 0 and guard < 20:
		bag.hit_source = p; bag.receive_hit(20.0, Vector3.RIGHT, 8.0); guard += 1
		await wait(4)
	check(bag.shell_index == 1 and bag.body_mesh.top_radius < r0 and m3.layers_broken == 1, "outer layer breaks off (bag gets thinner)")
	guard = 0
	while not m3.shattered and guard < 40:
		bag.hit_source = p; bag.receive_hit(20.0, Vector3.RIGHT, 8.0); guard += 1
		await wait(4)
	check(m3.shattered and m3.layers_broken == 5 and m3.time_bonus > 0, "core shatters with a time bonus (%d)" % m3.time_bonus)
	check(arena.story_state == "bag_playing", "core burst plays before the results screen")
	await wait(110)
	check(arena.story_state == "bag_done" and arena.story_title.text.begins_with("SHATTERED!"), "shatter ends the round early -> results")
	check(arena.story_detail.text.find("Layers broken 5/5") >= 0, "results show layers broken")
	# Leave: back to setup, then a normal match has no bag.
	arena.story_back.pressed.emit()
	await process_frame
	check(arena.heavy_bag_mode == null and arena.setup.visible, "back to setup ends the mini-game")
	check(arena.start_match(load("res://scripts/match_config.gd").default_slots(), false), "normal match starts after the mini-game")
	var any_bag := false
	for f in arena.fighters: any_bag = any_bag or f.has_method("is_heavy_bag")
	check(not any_bag and arena.fighters.size() == 4, "normal match has no bag")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("HEAVY_BAG_TEST failures=%d" % failures)
	quit(1 if failures else 0)

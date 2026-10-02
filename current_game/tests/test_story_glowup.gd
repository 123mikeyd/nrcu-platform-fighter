extends SceneTree
# Story glow-up (Mike 2026-09-30): VS splash, locked-opponent silhouette reveal,
# Smash-style victory screen after Story wins, STORY COMPLETE? ending + credits.
const U = preload("res://scripts/unlocks.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize(): call_deferred("run")

func _force_result(arena, loser) -> void:
	loser.stocks = 0
	arena._on_fighter_eliminated(loser)

func run():
	var save := OS.get_user_data_dir().path_join("glowup_test_unlocks.json")
	if FileAccess.file_exists(save): DirAccess.remove_absolute(save)
	U.path_override = save     # real locks, scratch save
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.open_story()
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == "teknium": arena.story_character.select(i)
	arena.story_action.pressed.emit()
	await process_frame
	var vs = arena.story_vs
	check(arena.story_state == "playing" and vs.visible, "START ENCOUNTER loads the fight behind the VS splash")
	check(arena.ready_remaining > 3.0 and not arena.ready_label.visible, "READY waits behind the splash")
	check(vs.hero_id == "teknium" and vs.opponent_id == "bobo", "splash shows hero vs current opponent")
	check(vs.left_art.texture != null and vs.right_art.texture != null, "Teknium (Arts Bro) and Bobo (in-game picture) portraits load")
	check(U.is_locked("bobo") and vs.silhouette and vs.right_name.text == "???" and vs.right_art.modulate == Color(0, 0, 0, 1), "locked opponent arrives as a black ??? silhouette")
	check(not vs.left_art.flip_h and not vs.right_art.flip_h, "Teknium (drawn left) and Bobo (shot facing left) face inward unflipped")
	await create_timer(1.75).timeout
	check(vs.right_name.text == "BOBO" and vs.right_art.modulate.is_equal_approx(Color.WHITE), "silhouette revealed in color with name as VS lands")
	vs.skip()
	check(not vs.visible and arena.ready_remaining <= 1.35 and arena.ready_label.visible, "skip hands over to the normal READY")
	arena._cancel_ready()
	arena.player_two.controls_enabled = true
	arena.player_two.receive_hit(400, Vector3.RIGHT, 0)
	check(arena.story_state == "stage_complete" and arena.story_title.text == "TEKNIUM WINS!", "Story win title is TEKNIUM WINS!")
	check(arena.victory_screen.visible and arena.victory_screen.title.text == "TEKNIUM WINS!", "victory screen shows after a Story win")
	check(arena.story_panel.visible and arena.story_result_bar.visible and not arena.story_title.visible and arena.story_action.text == "NEXT ENCOUNTER", "compact bottom bar with NEXT ENCOUNTER over the victory screen")
	arena.story_action.pressed.emit()
	await process_frame
	check(not arena.victory_screen.visible and not arena.story_result_bar.visible and arena.story_title.visible, "next briefing returns to the full panel")
	check(arena.story_title.text == "STORY 02 / ICE MAGE", "briefing 2 is Ice Mage")
	arena.story_action.pressed.emit()
	await process_frame
	check(vs.visible and vs.right_art.texture == null and not vs.silhouette and vs.right_name.text == "ICE MAGE", "Ice Mage: no picture, name only")
	# Retry skips the splash
	vs.skip()
	arena._cancel_ready()
	for i in 3: arena.player_one._handle_blast_zone()
	check(arena.story_state == "lost" and arena.story_title.text == "TRY AGAIN" and not arena.victory_screen.visible, "loss keeps TRY AGAIN panel")
	arena.story_action.pressed.emit()
	await process_frame
	check(arena.story_state == "playing" and not vs.visible, "Retry goes straight in, no splash")
	# run to the final encounter
	while arena.story_encounter < arena.story_route.size() - 1:
		arena._cancel_ready()
		if arena.player_two.character_id == "bobo": arena.player_two.receive_hit(400, Vector3.RIGHT, 0)
		else: _force_result(arena, arena.player_two)
		arena.story_action.pressed.emit()
		await process_frame
		arena.story_action.pressed.emit()
		await process_frame
		vs.skip()
	check(arena.player_two.character_id == "mephisto", "last encounter is Mephisto")
	arena._cancel_ready()
	_force_result(arena, arena.player_two)
	var ending = arena.story_ending
	check(arena.story_state == "complete" and arena.story_title.text == "STORY COMPLETE?", "final clear: STORY COMPLETE?")
	check(arena.victory_screen.visible and arena.victory_screen.title.text == "STORY COMPLETE?" and ending.visible and not arena.story_panel.visible, "victory pose holds before the fade")
	check(ending.black.modulate.a < 0.05, "not black yet during the hold")
	await create_timer(ending.HOLD + ending.FADE + 0.4).timeout
	check(ending.black.modulate.a > 0.99 and ending.is_rolling(), "faded to black, credits rolling")
	var names := []
	for l in ending.roll.get_children(): names.append(l.text)
	check("Mike" in names and "Quark" in names and "Arts Bro" in names and "Hermes Agent" in names, "credits list Mike, Quark, Arts Bro, Hermes Agent")
	check(arena.challenger_screen.visible == false, "no challenger interrupts the credits")
	ending.skip()
	check(arena.story_panel.visible and arena.story_action.text == "RESTART RUN" and "STORY COMPLETE?" in arena.story_detail.text, "result panel after credits")
	check(not arena.victory_screen.visible, "victory screen cleared after credits")
	await create_timer(1.9).timeout
	check(arena.challenger_screen.visible and arena.challenger_screen.challenger_id == "witcheer", "Witcheer approaches after the credits")
	# Witcheer has Arts Bro art, silhouette on the approach screen
	check(arena.challenger_screen.portrait.visible and arena.challenger_screen.portrait.modulate == Color(0, 0, 0, 1), "approach silhouette")
	U.path_override = ""
	if FileAccess.file_exists(save): DirAccess.remove_absolute(save)
	print("%s story glowup (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

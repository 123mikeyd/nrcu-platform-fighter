extends SceneTree
# Fighter unlocks, challenger fights and the 7-encounter Story gauntlet.
# Uses a scratch save (never the player's real user://nrcu_unlocks.json).
# Match outcomes are FORCED fixtures (stocks set to 0 + production elimination
# handler); they prove routing/saves, not natural combat.
var failures := 0
var U = load("res://scripts/unlocks.gd")
const SAVE := "user://test_unlocks_gauntlet.json"
const BAG := "user://test_unlocks_bag.json"
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok   " + message)
func _initialize(): call_deferred("run")

func _wipe():
	for p in [SAVE, BAG]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _force_result(arena, loser) -> void:
	loser.stocks = 0
	arena._on_fighter_eliminated(loser)

func _option_ids(option: OptionButton) -> Dictionary:
	var out := {}
	for i in option.item_count:
		out[option.get_item_metadata(i)] = {"disabled": option.is_item_disabled(i), "text": option.get_item_text(i)}
	return out

func _versus(arena) -> void:
	var slots = arena.Config.default_slots()
	slots[0].character = "teknium"; slots[0].kind = "human"
	slots[1].character = "doge_man"; slots[1].kind = "bot"
	slots[2].kind = "empty"; slots[3].kind = "empty"
	arena.start_match(slots, false)
	await process_frame
	arena._cancel_ready()
	_force_result(arena, arena.player_two)

func run():
	U.path_override = SAVE
	U.bag_path_override = BAG
	_wipe()
	var dev = root.get_node("/root/DevMode")
	dev.enabled = false
	# ---- fresh save
	for id in ["teknium", "turbofit", "doge_man"]: check(U.is_playable(id), "starter %s playable on a fresh save" % id)
	for id in ["ggb", "bobo", "witcheer", "mephisto"]: check(U.is_locked(id), "%s locked on a fresh save" % id)
	check(not U.is_playable("ice_mage"), "Ice Mage never playable")
	check(U.next_challenger() == "", "no challenger on a fresh save")

	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.show_setup()
	await process_frame
	var row = arena.setup.rows[0]
	var ids := _option_ids(row.character)
	check(not ids.has("ice_mage"), "versus select has no Ice Mage")
	check(ids.get("ggb", {}).get("disabled", false) and ids.ggb.text == "??? (Locked)", "GGB shows ??? (Locked) in versus")
	check(not ids.get("teknium", {"disabled": true}).disabled, "Teknium selectable in versus")
	for r in arena.setup.rows:
		check(not r.character.is_item_disabled(r.character.selected), "default slot pick is unlocked (%s)" % r.character.get_selected_metadata())

	# ---- GGB: two versus matches -> challenger -> lose -> returns -> win
	await _versus(arena)
	check(U.versus_matches() == 1 and U.next_challenger() == "", "1 versus match: no challenger yet")
	arena.show_setup()
	await _versus(arena)
	check(U.versus_matches() == 2 and U.next_challenger() == "ggb", "2 versus matches: GGB condition met")
	await create_timer(1.9).timeout
	var cs = arena.challenger_screen
	check(cs.visible and cs.mode == "approach" and cs.title.text == "A NEW FIGHTER APPROACHES!", "approach screen appears after the result")
	check(not arena.result_panel.visible, "result panel hidden behind approach screen")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame
	check(arena.story_state == "challenger" and arena.player_two.character_id == "ggb" and arena.player_one.character_id == "teknium", "FIGHT starts P1's fighter vs GGB")
	arena._cancel_ready()
	_force_result(arena, arena.player_one)
	check(cs.visible and cs.mode == "escaped" and U.is_locked("ggb"), "losing the challenger: GOT AWAY, still locked")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame
	check(arena.setup.visible, "continue returns to setup")
	await _versus(arena)
	await create_timer(1.9).timeout
	check(cs.visible and cs.challenger_id == "ggb", "GGB challenges again after the next match")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame
	arena._cancel_ready()
	_force_result(arena, arena.player_two)
	check(cs.mode == "joined" and cs.title.text == "GGB JOINS THE BATTLE!" and U.is_playable("ggb"), "beating GGB unlocks him")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame
	ids = _option_ids(arena.setup.rows[0].character)
	check(not ids.ggb.disabled and ids.ggb.text == "GGB", "GGB selectable in versus after unlock")

	# ---- Later button
	var f := FileAccess.open(BAG, FileAccess.WRITE); f.store_string(JSON.stringify({"doge_man": U.BOBO_SCORE - 1})); f.close()
	check(U.next_challenger() == "", "bag score below %d: no Bobo challenger" % U.BOBO_SCORE)
	f = FileAccess.open(BAG, FileAccess.WRITE); f.store_string(JSON.stringify({"doge_man": U.BOBO_SCORE})); f.close()
	check(U.next_challenger() == "bobo", "bag score %d: Bobo condition met" % U.BOBO_SCORE)
	await _versus(arena)
	await create_timer(1.9).timeout
	check(cs.visible and cs.challenger_id == "bobo", "Bobo approaches")
	await create_timer(1.0).timeout
	cs.secondary.pressed.emit()
	await process_frame
	check(arena.setup.visible and U.is_locked("bobo"), "LATER returns to setup; Bobo still locked")
	await _versus(arena)
	await create_timer(1.9).timeout
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame
	check(arena.player_two.get_script() == load("res://scripts/bobo_fighter.gd") and arena.bobo_health_bar.visible, "Bobo challenger is the 400 HP Bobo")
	arena._cancel_ready()
	arena.player_two.controls_enabled = true
	arena.player_two.receive_hit(400, Vector3.RIGHT, 0)
	check(U.is_playable("bobo") and cs.mode == "joined", "beating Bobo (HP) unlocks him")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame

	# ---- Story gauntlet (Teknium)
	arena.open_story()
	var story_ids := _option_ids(arena.story_character)
	check(story_ids.has("ggb") and not story_ids.ggb.disabled, "unlocked GGB is a Story hero")
	check(story_ids.get("witcheer", {}).get("disabled", false) and story_ids.get("mephisto", {}).get("disabled", false), "Witcheer/Mephisto locked in Story select")
	check(not story_ids.has("ice_mage") and not story_ids.has("bobo"), "Ice Mage/Bobo not Story heroes")
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == "teknium": arena.story_character.select(i)
	arena.story_action.pressed.emit()
	await process_frame
	check(arena.story_route == ["bobo", "ice_mage", "witcheer", "ggb", "turbofit", "doge_man", "mephisto"], "Teknium route skips Teknium, 7 encounters, Mephisto last")
	for n in arena.story_route.size():
		var opp: String = arena.story_route[n]
		check(arena.story_state == "playing" and arena.player_two.character_id == opp, "encounter %d vs %s" % [n + 1, opp])
		if opp == "mephisto":
			check(arena.player_two.get_script().resource_path == "res://story_boss/scripts/fighter.gd", "Mephisto encounter uses preserved Story boss")
		arena._cancel_ready()
		if opp == "bobo":
			arena.player_two.controls_enabled = true
			arena.player_two.receive_hit(400, Vector3.RIGHT, 0)
		else:
			_force_result(arena, arena.player_two)
		if n < arena.story_route.size() - 1:
			check(arena.story_state == "stage_complete" and arena.story_action.text == "NEXT ENCOUNTER", "win %d offers NEXT ENCOUNTER" % (n + 1))
			arena.story_action.pressed.emit()
			await process_frame
			check(arena.story_title.text.begins_with("STORY %02d /" % (n + 2)), "briefing %d shown (%s)" % [n + 2, arena.story_title.text])
			arena.story_action.pressed.emit()
			await process_frame
	check(arena.story_state == "complete" and "STORY COMPLETE" in arena.story_detail.text, "final win completes Story")
	check(U.story_clears() == 1 and "teknium" in U.story_heroes(), "Story clear saved with hero")
	check(arena.story_title.text == "STORY COMPLETE?" and arena.story_ending.visible and not arena.story_panel.visible, "final win plays STORY COMPLETE? ending before the result panel")
	arena.story_ending.skip()   # credits: skip to the result panel
	check(arena.story_panel.visible, "result panel after the credits")
	await create_timer(1.9).timeout
	check(cs.visible and cs.challenger_id == "witcheer", "Witcheer approaches after Story complete")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame
	check(arena.player_one.character_id == "teknium" and arena.player_two.character_id == "witcheer", "Story hero fights Witcheer")
	arena._cancel_ready()
	_force_result(arena, arena.player_two)
	check(U.is_playable("witcheer"), "Witcheer unlocked")
	await create_timer(1.0).timeout
	cs.primary.pressed.emit()
	await process_frame

	# ---- Story loss retries the current encounter
	arena.open_story()
	arena.story_action.pressed.emit()
	await process_frame
	arena._cancel_ready()
	arena.player_two.controls_enabled = true
	arena.player_two.receive_hit(400, Vector3.RIGHT, 0)
	arena.story_action.pressed.emit(); await process_frame
	arena.story_action.pressed.emit(); await process_frame
	arena._cancel_ready()
	_force_result(arena, arena.player_one)
	check(arena.story_state == "lost" and arena.story_action.text == "RETRY", "loss offers RETRY")
	arena.story_action.pressed.emit(); await process_frame
	check(arena.story_encounter == 1 and arena.player_two.character_id == "ice_mage", "retry keeps the current encounter")

	# ---- Mephisto hardest gate
	check(U.next_challenger() == "" and not U.condition_met("mephisto"), "Mephisto gated: only Teknium has cleared Story")
	U.record_story_clear("turbofit")
	check(not U.condition_met("mephisto"), "Mephisto still gated without Doge Man's clear")
	U.record_story_clear("doge_man")
	check(U.condition_met("mephisto") and U.next_challenger() == "mephisto", "all 3 starters cleared + GGB/Bobo/Witcheer unlocked: Mephisto approaches")
	check(U.CHALLENGER_DIFFICULTY.mephisto == "hard", "Mephisto challenger is a Hard bot")

	# ---- Dev Mode
	_wipe()
	dev.enabled = true
	check(U.is_playable("mephisto") and U.is_playable("ggb") and not U.is_playable("ice_mage"), "Dev Mode unlocks all except Ice Mage")
	check(U.next_challenger() == "", "no challengers in Dev Mode")
	dev.enabled = false
	arena.queue_free()
	await process_frame
	_wipe()
	print("UNLOCKS_GAUNTLET failures=", failures)
	quit(1 if failures else 0)

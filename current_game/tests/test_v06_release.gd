extends SceneTree
# v0.6 public release contract for the nested current_game project.
# Story / challenger / Heavy Bag outcomes below are FORCED production fixtures
# (stocks set to 0 + the real elimination handler, Bobo health API, Heavy Bag
# finish()). They prove routing, saves and screens, not natural campaign clears.
# Unlock saves use scratch paths, never the player's real user:// files.
const U = preload("res://scripts/unlocks.gd")
const SAVE := "user://v06_release_unlocks.json"
const BAG := "user://v06_release_bag.json"
const BAG_BEST := "user://v06_release_bag_best.json"
var arena
var failures: Array = []
var checks := 0

func _initialize(): call_deferred("run_suite")

func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures.append(description)
		print("FAIL ", description)

func frames(n: int):
	for i in n: await physics_frame

func key(code: int, down: bool):
	var e := InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down
	Input.parse_input_event(e)

func wipe():
	for p in [SAVE, BAG, BAG_BEST]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func force_result(loser):
	loser.stocks = 0
	arena._on_fighter_eliminated(loser)

func new_arena(entry := ""):
	if is_instance_valid(arena):
		arena.show_setup()
		root.remove_child(arena); arena.queue_free(); await frames(2)
	if entry != "": set_meta("nrcu_entry", entry)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	await frames(2)

func select_story_hero(id: String):
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == id: arena.story_character.select(i)

func freeplay(p1: String, p2: String, p2_kind := "human") -> bool:
	var slots = arena.Config.default_slots()
	slots[0].character = p1; slots[0].kind = "human"
	slots[1].character = p2; slots[1].kind = p2_kind
	slots[2].kind = "empty"; slots[3].kind = "empty"
	return arena.start_match(slots, false)

func run_suite():
	U.path_override = SAVE
	U.bag_path_override = BAG
	wipe()
	var dev = root.get_node("/root/DevMode")
	# ---- Home front door (public presentation, rewired to the live game)
	var home = load("res://scenes/home.tscn").instantiate(); root.add_child(home); current_scene = home
	await frames(2)
	check(home.state == "opening", "home opens on the opening page")
	home.show_page("title"); check(home.buttons.has("start"), "title Press Start")
	home.show_page("home")
	for id in ["story", "play", "bag", "help", "quit"]: check(home.buttons.has(id), "home button " + id)
	check(not home.buttons.has("lab"), "v0.5 Battle Lab retired from home")
	root.remove_child(home); home.queue_free(); await frames(1)

	# ---- Home -> Story / Heavy Bag entry routes
	await new_arena("story")
	check(arena.story_panel.visible and arena.story_state == "ready" and not arena.setup.visible, "home Story Mode opens the Story briefing")
	await new_arena("heavy_bag")
	check(arena.story_panel.visible and arena.story_state == "bag_ready", "home Heavy Bag opens the Heavy Bag panel")
	await new_arena()
	check(arena.setup.visible, "home Local Match opens match setup")
	check(arena.get_script().resource_path == "res://scripts/main.gd", "battle scene owns the live main.gd router")
	check(not FileAccess.file_exists("res://scripts/v05_main.gd") and not FileAccess.file_exists("res://scripts/story_gauntlet.gd"), "v0.5 board router retired")

	# ---- Stages: Fortress (+ Tek infiltration cameo), Weaver, Toy, freeplay worlds
	var fortress = null
	for c in arena.get_children():
		if c.get_script() and c.get_script().resource_path == "res://scripts/fortress_shootout_stage.gd": fortress = c
	check(fortress != null, "Fortress stage loads")
	check(fortress != null and is_instance_valid(fortress.cameo) and fortress.cameo.get_script().resource_path.ends_with("fortress_tek_infiltration.gd"), "Fortress Tek infiltration cameo present")
	check(arena.has_node("KainanTerminal") or arena.find_children("*", "Node3D", false, false).any(func(n): return n.get_script() and n.get_script().resource_path.ends_with("kainan_terminal.gd")), "Kainan terminal retained")
	check(arena.SetupScript.LEVEL_IDS == ["debug", "toy_room", "weaver", "hall", "meadow"], "stage list: Fortress, Toy, Weaver, Hall, Meadow (no Sky)")
	arena.setup.level.select(arena.SetupScript.LEVEL_IDS.find("weaver"))
	check(freeplay("teknium", "doge_man"), "Weaver freeplay starts"); await frames(3)
	check(arena.active_level == "weaver" and is_instance_valid(arena.stage_theme) and arena.stage_theme.get_script().resource_path.ends_with("weaver_stage.gd"), "Hermes Weaver stage loads")
	arena.setup.level.select(arena.SetupScript.LEVEL_IDS.find("toy_room"))
	check(freeplay("teknium", "doge_man"), "Toy freeplay starts"); await frames(3)
	check(arena.active_level == "toy_room", "Toy stage loads after Weaver")
	for w in ["hall", "meadow"]:
		arena.setup.level.select(arena.SetupScript.LEVEL_IDS.find(w))
		check(freeplay("turbofit", "doge_man"), "freeplay world starts " + w)
		await frames(100)
		check(arena.active_level == w and is_instance_valid(arena.world) and arena.world.moving is AnimatableBody3D, "freeplay world built " + w)
		check(arena.player_one.is_on_floor() and arena.player_one.stocks == 3, "fighter lands on world floor " + w)
	arena.setup.level.select(0)
	check(freeplay("teknium", "doge_man"), "Fortress after worlds"); await frames(3)
	check(arena.active_level == "debug" and not is_instance_valid(arena.world) and arena.get_node("MainPlatform").collision_layer == 1, "Fortress restores base collision after worlds")

	# ---- Every hero actor: current freeplay factories (headless legacy roster = all playable)
	U.path_override = ""
	for id in load("res://scripts/roster.gd").ids():
		arena.show_setup()
		check(freeplay(id, "teknium"), "freeplay start " + id); await frames(2)
		check(arena.player_one.character_id == id, "actor created " + id)
		check(arena.player_one.get_script().resource_path == ("res://scripts/bobo_player.gd" if id == "bobo" else "res://scripts/fighter.gd"), "current factory " + id)
		check((arena.player_one.ledge_grab != null) == (id in ["teknium", "doge_man", "turbofit"]) if id != "bobo" else true, "ledge component only for Tek/Doge/Turbo " + id)
		if id == "turbofit": check(arena.player_one.turbofit_snapline != null, "TurboFit Snapline installed")
		if id == "mephisto": check(arena.player_one.mephisto_moves != null and arena.player_one.mephisto_moves.grasp() != null and arena.player_one.mephisto_moves.grasp().get_script().resource_path == "res://scripts/mephisto_dream_grasp.gd", "Mephisto Dream Grasp installed")
	U.path_override = SAVE
	check(load("res://scripts/ggb_wing_gust.gd") != null and load("res://scripts/mephisto_dream_grasp.gd") != null and load("res://scripts/turbofit_snapline.gd") != null and load("res://scripts/air_cushion_fx.gd") != null, "new move scripts load")

	# ---- Pause (Esc menu) + Options Dev Mode toggle exists
	arena.show_setup(); freeplay("teknium", "doge_man"); await frames(100)
	check(arena.match_active(), "freeplay match active after READY")
	arena.pause_match()
	check(arena.pause_menu.visible and paused, "pause menu opens and pauses")
	check(arena.pause_menu.find_child("OptionsButton", true, false) != null, "pause menu has Options")
	arena.resume_match()
	check(not arena.pause_menu.visible and not paused, "resume closes the pause")
	var mobile = root.get_node_or_null("/root/MobileTouch")
	check(mobile != null and arena.has_method("match_active") and arena.has_method("pause_match"), "MobileTouch arena contract (match_active / pause_match)")

	# ---- Ordinary input: move, jump (passive opponent) and basic damage vs live Bobo
	arena.show_setup(); freeplay("turbofit", "doge_man"); await frames(120)
	var start: Vector3 = arena.player_one.position
	key(KEY_D, true); await frames(12); key(KEY_D, false); await frames(2)
	check(arena.player_one.position.x > start.x + 0.2, "ordinary move input")
	var y: float = arena.player_one.position.y
	key(KEY_SPACE, true); await frames(8); key(KEY_SPACE, false); await frames(2)
	check(arena.player_one.position.y > y + 0.3, "ordinary jump input")

	# ---- Story: every hero through the encounter run to the ending + credits
	dev.enabled = true   # all heroes selectable for the route check
	var heroes: Array = arena._story_playable_ids()
	check(heroes.size() == 6 and not "bobo" in heroes and not "ice_mage" in heroes, "six Story heroes")
	var clears_before := U.story_clears()
	for hero in heroes:
		arena.open_story(); select_story_hero(hero)
		arena.story_action.pressed.emit(); await process_frame
		check(arena.story_hero == hero and arena.story_route.size() == 7 and not hero in arena.story_route, "route skips hero " + hero)
		check(arena.story_route[-1] == ("teknium" if hero == "mephisto" else "mephisto"), "final opponent " + hero)
		while true:
			arena.story_vs.skip(); arena._cancel_ready()
			var opp: String = arena.story_opponent()
			check(arena.story_state == "playing" and arena.player_one.character_id == hero and arena.player_two.character_id == opp, "real actors %s vs %s" % [hero, opp])
			if opp == "mephisto": check(arena.player_two.get_script().resource_path == "res://story_boss/scripts/fighter.gd", "Story Mephisto uses the story_boss fighter")
			if hero == "mephisto": check(arena.player_one.get_script().resource_path == "res://scripts/fighter.gd", "playable Mephisto independent of story boss")
			if arena.story_encounter == 0 and hero == heroes[0]:
				arena.player_one.stocks = 1; arena.player_one._handle_blast_zone()
				check(arena.story_state == "lost" and arena.story_action.text == "RETRY", "loss keeps the encounter (RETRY)")
				arena.story_action.pressed.emit(); await process_frame
				arena.story_vs.skip(); arena._cancel_ready()
			if opp == "bobo":
				arena.player_two.controls_enabled = true; arena.player_two.receive_hit(400, Vector3.RIGHT, 0)
			else:
				force_result(arena.player_two)
			if arena.story_state == "complete": break
			check(arena.story_state == "stage_complete" and arena.victory_screen.visible, "victory screen after Story win " + opp)
			arena.story_action.pressed.emit(); await process_frame
			arena.story_action.pressed.emit(); await process_frame
		check(arena.story_ending.visible and arena.story_title.text == "STORY COMPLETE?", "ending plays after final win " + hero)
		arena.story_ending.skip()
		check(arena.story_panel.visible and arena.story_action.text == "RESTART RUN", "credits -> result panel " + hero)
	check(U.story_clears() == clears_before + heroes.size(), "Story clears recorded")
	dev.enabled = false

	# ---- Unlock / challenger path (real locks, scratch save)
	wipe(); await new_arena()
	for id in ["teknium", "turbofit", "doge_man"]: check(U.is_playable(id), "starter playable " + id)
	for id in ["ggb", "bobo", "witcheer", "mephisto"]: check(U.is_locked(id), "locked on fresh save " + id)
	U.record_versus_match(); U.record_versus_match()
	check(U.next_challenger() == "ggb", "GGB challenger after two versus matches")
	arena.challenger_hero = "teknium"; arena.start_challenger("ggb"); await process_frame
	check(arena.story_state == "challenger" and arena.player_two.character_id == "ggb", "GGB challenger fight starts")
	arena._cancel_ready(); force_result(arena.player_one)
	check(U.is_locked("ggb") and arena.challenger_screen.visible, "losing the challenger keeps GGB locked")
	arena.show_setup(); arena.start_challenger("ggb"); await process_frame
	arena._cancel_ready(); force_result(arena.player_two)
	check(U.is_playable("ggb") and arena.challenger_screen.visible and arena.challenger_screen.challenger_id == "ggb", "beating the challenger unlocks GGB")
	U.record_story_clear("teknium")
	check(U.next_challenger() == "witcheer", "Witcheer challenger after a Story clear")

	# ---- Heavy Bag start / finish
	await new_arena("heavy_bag")
	select_story_hero("teknium")
	arena.story_action.pressed.emit(); await process_frame
	check(arena.story_state == "bag_playing" and is_instance_valid(arena.heavy_bag_mode) and arena.player_two.has_method("is_heavy_bag"), "Heavy Bag round starts with the bag")
	check(arena.active_level != "hall" and arena.active_level != "meadow", "Heavy Bag never uses a freeplay world")
	arena.heavy_bag_mode.save_path = BAG_BEST
	arena.heavy_bag_mode.score = 1234
	arena.heavy_bag_mode.finish(); await process_frame
	check(arena.story_state == "bag_done" and "1234" in arena.story_detail.text and arena.story_action.text == "TRY AGAIN", "Heavy Bag finishes with the score screen")

	# ---- Story on a freeplay world falls back to Fortress
	arena.show_setup(); arena.setup.level.select(arena.SetupScript.LEVEL_IDS.find("meadow"))
	dev.enabled = true
	arena.open_story(); select_story_hero("turbofit"); arena.story_action.pressed.emit(); await process_frame
	check(arena.active_level == "debug", "Story started from Meadow selection plays on Fortress")
	dev.enabled = false
	arena.story_vs.skip()

	# ---- Rights / cleanup guards
	arena.show_setup()
	root.remove_child(arena); arena.queue_free(); await frames(3)
	U.path_override = ""; U.bag_path_override = ""
	wipe()
	print("V06 checks=", checks, " failures=", failures.size(), "; Story/challenger/bag outcomes are forced fixtures, not natural clears")
	if failures.is_empty(): print("V06_RELEASE_COMPLETE")
	quit(0 if failures.is_empty() else 1)

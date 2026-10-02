extends SceneTree
# v0.6 lethal-contact lifecycle on the live Story router (replaces the v0.5 board
# version). Real keyboard input and real contact/physics dispatch; health/stock/
# position fixtures only shorten the fight. Guards the "never tear down actors inside
# the elimination signal" rule (v0.5 Windows crash).
var arena
var failures: Array = []
var checks := 0
var observed := false
var contact_stack: Array = []
func _initialize(): call_deferred("run_test")
func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures.append(description); print("FAIL ", description)
func frames(n: int):
	for i in n: await physics_frame
func key(code: int, down: bool):
	var e := InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down
	Input.parse_input_event(e)
func start_story(hero := "turbofit"):
	arena.show_setup(); arena.open_story()
	for i in arena.story_character.item_count:
		if arena.story_character.get_item_metadata(i) == hero: arena.story_character.select(i)
	arena.story_action.pressed.emit(); await frames(2)
	arena.story_vs.skip(); await frames(125)
func watch_contact(hero, target, kind: String):
	observed = false
	target.eliminated.connect(func(_loser):
		if observed: return
		observed = true; contact_stack = get_stack()
		check(hero.is_inside_tree() and target.is_inside_tree(), kind + " actors attached inside lethal callback")
		arena._on_fighter_eliminated(target)   # re-entrant call must not double-resolve
	)
func run_test():
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); current_scene = arena
	await frames(2)
	print("STEP 1")
	# 1) Ordinary melee kills live Bobo (health fixture 1 HP).
	await start_story()
	print("STEP 1b started")
	var hero = arena.player_one; var target = arena.player_two
	check(target.character_id == "bobo", "encounter 1 is Bobo")
	hero.reset_fighter(Vector3(-1, 0.2, 0), true); hero.controls_enabled = true; hero.facing = 1
	await frames(30)
	target.health = 1; watch_contact(hero, target, "melee")
	for swing in 4:
		key(KEY_F, true); await frames(8); key(KEY_F, false); await frames(40)
		if observed: break
	print("STEP 1c killed")
	check(observed, "ordinary melee causes lethal contact")
	check(str(contact_stack).contains("_physics_process"), "melee elimination comes from live physics")
	check(arena.story_state == "stage_complete" and arena.story_encounter == 0 and arena.match_over, "melee win resolves exactly once")
	await frames(30)
	check(is_instance_valid(hero) and is_instance_valid(target) and arena.story_state == "stage_complete", "actors survive the callback; no auto-advance")
	check(get_nodes_in_group("projectiles").is_empty(), "result clears projectiles")
	print("STEP 2")
	# 2) Next encounter needs explicit Start; physics blast-zone loss keeps the encounter.
	arena.story_action.pressed.emit(); await frames(1)
	check(arena.story_state == "ready" and arena.story_title.text == "STORY 02 / ICE MAGE", "next briefing requires Start")
	arena.story_action.pressed.emit(); await frames(2); arena.story_vs.skip(); await frames(125)
	check(arena.player_two.character_id == "ice_mage" and arena.player_one.character_id == "turbofit", "Ice Mage starts with retained hero")
	arena.player_one.stocks = 1; arena.player_one.global_position = Vector3(0, -40, 0)
	await frames(4)
	check(arena.story_state == "lost" and arena.story_encounter == 1, "physics last-stock loss keeps the encounter")
	arena.story_action.pressed.emit(); await frames(125)
	check(arena.player_one.stocks == 3 and arena.player_two.stocks == 3, "retry gives fresh stocks")
	arena.player_two.global_position = Vector3(0, -40, 0); await frames(4)
	check(arena.story_state == "playing" and arena.player_two.stocks == 2 and not arena.match_over, "non-final stock revives without a result")
	arena.player_two.reset_fighter(Vector3(0, -40, 0), false); arena.player_two.stocks = 1; await frames(4)
	check(arena.story_state == "stage_complete" and arena.story_encounter == 1, "physics enemy last stock resolves once")
	print("STEP 3")
	# 3) TurboFit side special: real swept sound-wave projectile kills Bobo.
	await start_story()
	hero = arena.player_one; target = arena.player_two
	hero.reset_fighter(Vector3(-3, 0.2, 0), true); hero.controls_enabled = true; hero.facing = 1
	await frames(30)
	target.health = 1; watch_contact(hero, target, "projectile")
	for shot in 4:
		key(KEY_D, true); key(KEY_G, true); await frames(8); key(KEY_G, false); key(KEY_D, false); await frames(50)
		if observed: break
	check(observed, "ordinary projectile causes lethal contact")
	check(arena.story_state == "stage_complete", "projectile win resolves once")
	await frames(10)
	check(get_nodes_in_group("projectiles").is_empty(), "lethal projectile cleaned after dispatch")
	print("STEP 4")
	# 4) Leaving mid-result (setup) then a fresh freeplay match is clean.
	arena.show_setup()
	var slots = arena.Config.default_slots(); slots[0].character = "teknium"; slots[1].character = "doge_man"; slots[1].kind = "human"; slots[2].kind = "empty"; slots[3].kind = "empty"
	check(arena.start_match(slots, false), "freeplay after Story starts"); await frames(5)
	check(arena.story_state == "" and arena.fighters.size() == 2, "Story state cleared for freeplay")
	print("STEP teardown")
	arena.show_setup(); root.remove_child(arena); arena.queue_free(); await frames(3)
	print("V06_CONTACT checks=", checks, " failures=", failures.size())
	if failures.is_empty(): print("V06_CONTACT_COMPLETE")
	quit(0 if failures.is_empty() else 1)

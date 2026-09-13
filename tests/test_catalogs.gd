extends SceneTree
# WP-0 catalog consistency test — corrective package Doc 02 §8 "Catalogs"
# and §10.1 (migration step 1: add catalogs without changing behavior);
# ledger Q-033 "Production catalogs need consistency tests".
#
# This test pins the ADDITIVE catalogs to the actual current production sources:
#   - fighter ids/names/portraits vs roster.gd + portrait_data.gd;
#   - Story eligibility vs main.gd _story_playable_ids();
#   - stage ids vs match_setup.LEVEL_IDS, thumbnails on disk, SSS label rule;
#   - encounter 01 copy vs story_briefing.gd (exact literals) + bobo_fighter MAX_HEALTH;
#   - input profiles vs how_to_play.gd PROFILES/BINDINGS and the legacy
#     demo_style CONTROLS text.
# It also asserts catalog purity: every read returns fresh, equal data and
# mutating a returned copy never leaks back into the catalog.

const FIGHTER_CATALOG := "res://scripts/catalogs/fighter_catalog.gd"
const STAGE_CATALOG := "res://scripts/catalogs/stage_catalog.gd"
const ENCOUNTER_CATALOG := "res://scripts/catalogs/story_encounter_catalog.gd"
const INPUT_CATALOG := "res://scripts/catalogs/input_profile_catalog.gd"

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_fighter_catalog()
	_stage_catalog()
	_encounter_catalog()
	_input_profile_catalog()
	if failures == 0:
		print("PASS: four additive catalogs match the current production sources and stay pure")
	quit(1 if failures else 0)

# --- shared ---------------------------------------------------------------
func _source(path: String) -> String:
	check(FileAccess.file_exists(path), "source exists: " + path)
	return FileAccess.get_file_as_string(path)

func _constants(path: String) -> Dictionary:
	var script = load(path)
	check(script != null, "script loads: " + path)
	if script == null:
		return {}
	return script.get_script_constant_map()

func _purity(catalog, label: String) -> void:
	check(catalog != null, label + ": catalog loads")
	if catalog == null:
		return
	var first: Array = catalog.all()
	var second: Array = catalog.all()
	check(not first.is_empty(), label + ": has entries")
	check(first == second, label + ": repeated reads return equal data")
	if first.is_empty():
		return
	var snapshot: Array = catalog.all()
	first[0]["__purity_probe__"] = true
	check(not catalog.all()[0].has("__purity_probe__"), label + ": mutating a returned copy does not reach the catalog")
	check(catalog.all() == snapshot, label + ": later reads are unchanged after a returned copy was mutated")
	var id_list: Array = catalog.ids()
	var size_before: int = id_list.size()
	id_list.append("__probe__")
	check(catalog.ids().size() == size_before, label + ": ids() returns a fresh array each call")

# --- FighterCatalog -------------------------------------------------------
func _fighter_catalog() -> void:
	var roster = load("res://scripts/roster.gd")
	var portraits = load("res://scripts/frontend/portrait_data.gd")
	var catalog = load(FIGHTER_CATALOG)
	_purity(catalog, "FighterCatalog")
	var ids: Array = catalog.ids()
	check(ids == roster.ids(), "fighter ids equal roster.ids() exactly, same order")
	check(catalog.ids().size() == 7, "seven roster fighters")
	var fighter_ids: Array = roster.ids()
	var expected_story: Array = []
	for id in fighter_ids:
		if str(id) != "ice_mage":
			expected_story.append(str(id))
	check(catalog.story_playable_ids() == expected_story, "story_playable_ids equals the main.gd ice_mage exclusion")
	check(not catalog.is_story_playable("ice_mage"), "ice_mage is not story playable")
	check(not catalog.is_story_playable("bobo"), "bobo is not a roster fighter")
	check(catalog.display_name("nonexistent") == "Unknown", "unknown fighter id keeps the roster fallback")
	var fighter_source := _source("res://scripts/fighter.gd")
	for id in fighter_ids:
		var key := str(id)
		var entry: Dictionary = catalog.by_id(key)
		check(not entry.is_empty(), "entry exists: " + key)
		if entry.is_empty():
			continue
		check(str(entry["display_name"]) == roster.display_name(key), "display name matches roster: " + key)
		check(str(entry["portrait_path"]) == portraits.portrait_path(key), "portrait path matches portrait_data: " + key)
		check(str(entry["portrait_path"]) == "res://assets/portraits/" + key + ".png", "portrait path policy: " + key)
		check(FileAccess.file_exists(str(entry["portrait_path"])), "portrait file exists on disk: " + key)
		var presentation: Dictionary = entry["presentation"]
		check(str(presentation["key"]) == key, "presentation key is the fighter id: " + key)
		check(FileAccess.file_exists(str(presentation["visual_module"])), "presentation module exists on disk: " + key)
		check(fighter_source.contains(str(presentation["visual_module"])), "presentation module is the module fighter.gd installs: " + key)
		check(not presentation["frame_override_profiles"].is_empty(), "frame override profiles recorded: " + key)
		var help: Dictionary = entry["help_definition"]
		check(FileAccess.file_exists(str(help["source"].split("#")[0])), "help source exists: " + key)
		var policy: Dictionary = entry["palette_policy"]
		var base_hue: float = float(policy["base_hue"])
		check(roster.palette(key, 0).is_equal_approx(Color.from_hsv(fposmod(base_hue, 1.0), float(policy["saturation"]), float(policy["value"]))), "palette slot 0 matches roster: " + key)
		check(roster.palette(key, 1).is_equal_approx(Color.from_hsv(fposmod(base_hue + float(policy["slot_step"]), 1.0), float(policy["saturation"]), float(policy["value"]))), "palette slot 1 matches roster: " + key)
	var help_map: Dictionary = _constants("res://scripts/frontend/how_to_play.gd")
	var move_lists: Dictionary = help_map.get("MOVE_LISTS", {})
	# Duplicate-source drift check (G-040): where match_config.NAMES disagrees with
	# roster.display_name, the catalog must record the drift instead of hiding it.
	var config_map: Dictionary = _constants("res://scripts/match_config.gd")
	var config_names: Array = config_map.get("NAMES", [])
	var config_ids: Array = config_map.get("CHARACTERS", [])
	check(config_ids == fighter_ids, "match_config.CHARACTERS still mirrors roster ids")
	for id in fighter_ids:
		var key := str(id)
		var entry: Dictionary = catalog.by_id(key)
		if entry.is_empty():
			continue
		var config_index: int = config_ids.find(key)
		var config_name := str(config_names[config_index]) if config_index >= 0 else ""
		if config_name != str(roster.display_name(key)):
			check(str(entry.get("display_name_drift", "")) == config_name, "recorded MatchConfig name drift: " + key)
		else:
			check(not entry.has("display_name_drift"), "no false drift recorded: " + key)
	for id in fighter_ids:
		var entry: Dictionary = catalog.by_id(str(id))
		if entry.is_empty():
			continue
		check(bool(entry["help_definition"]["curated"]) == move_lists.has(str(id)), "curated help matches MOVE_LISTS: " + str(id))
	check(bool(catalog.by_id("ggb")["help_definition"]["curated"]), "GGB has a curated move list")
	check(bool(catalog.by_id("ggb")["palette_policy"]["preserves_painted_materials"]), "GGB keeps the painted-material palette rule")
	check(not bool(catalog.by_id("mephisto")["help_definition"]["curated"]), "Mephisto has no curated move list")
	var main_source := _source("res://scripts/main.gd")
	check(main_source.contains('ids.erase("ice_mage")'), "Story eligibility still comes from the main.gd exclusion")
	check(main_source.contains('load("res://scripts/roster.gd").ids()'), "roster.gd is still the id source")

# --- StageCatalog ---------------------------------------------------------
func _stage_catalog() -> void:
	var catalog = load(STAGE_CATALOG)
	_purity(catalog, "StageCatalog")
	var setup_map: Dictionary = _constants("res://scripts/match_setup.gd")
	check(catalog.ids() == setup_map.get("LEVEL_IDS", []), "stage ids equal match_setup.LEVEL_IDS exactly, same order")
	check(catalog.selectable_ids() == catalog.ids(), "all current stages are selectable")
	check(catalog.display_name("nonexistent") == "Unknown", "unknown stage id fallback")
	var setup_source := _source("res://scripts/match_setup.gd")
	var main_source := _source("res://scripts/main.gd")
	check(main_source.contains('"res://assets/menu/stage_" + SetupScript.LEVEL_IDS[i] + ".png"'), "production SSS thumbnail path rule unchanged")
	for entry in catalog.all():
		var id := str(entry["id"])
		check(str(entry["display_name"]) == str(entry["dropdown_text"]).split(" (")[0].to_upper(), "SSS display name derives from the setup option text: " + id)
		check(FileAccess.file_exists(str(entry["thumbnail"])), "thumbnail exists on disk: " + id)
		check(str(entry["thumbnail"]) == "res://assets/menu/stage_" + id + ".png", "thumbnail path policy: " + id)
		check(setup_source.contains('"%s"' % str(entry["dropdown_text"])), "setup dropdown text still present: " + id)
		check(setup_source.contains('"%s"' % str(entry["caption"])), "setup caption still present: " + id)
		var gameplay: Dictionary = entry["gameplay"]
		check(str(gameplay["stage_id"]) == id, "gameplay stage id resolves to the entry id: " + id)
		check(FileAccess.file_exists(str(gameplay["theme_script"])), "gameplay theme script exists: " + id)
		check(bool(gameplay["debug_visuals"]) == (id == "debug"), "debug visuals flag matches apply_level: " + id)
		if id == "debug":
			check(str(gameplay["details_level"]) == "", "debug stage has no StageTheme/StageDetails level: " + id)
		else:
			check(str(gameplay["details_level"]) == id, "themed stage mounts StageDetails with its level id: " + id)
	check(catalog.has("toy_room") and catalog.has("sky"), "toy_room and sky are present")
	check(FileAccess.file_exists("res://scripts/stage_details.gd"), "stage details script exists")
	check(load("res://scripts/stage_details.gd") != null, "stage details script loads")

# --- StoryEncounterCatalog ------------------------------------------------
func _encounter_catalog() -> void:
	var catalog = load(ENCOUNTER_CATALOG)
	_purity(catalog, "StoryEncounterCatalog")
	var stage_catalog = load(STAGE_CATALOG)
	var fighter_catalog = load(FIGHTER_CATALOG)
	var roster = load("res://scripts/roster.gd")
	check(catalog.ids() == ["story_01"], "exactly one encounter (01) today")
	var e: Dictionary = catalog.encounter_01()
	check(not e.is_empty(), "encounter 01 exists")
	check(str(e["label"]) == "STORY 01" and str(e["encounter_label"]) == "ENCOUNTER 01", "encounter labels match STORY 01 / ENCOUNTER 01")
	check(str(e["enemy_id"]) == "bobo" and str(e["enemy_display_name"]) == "BOBO", "encounter enemy is Bobo")
	var bobo_map: Dictionary = _constants("res://scripts/bobo_fighter.gd")
	check(absf(float(bobo_map.get("MAX_HEALTH", 0.0)) - 400.0) < 0.001, "bobo_fighter MAX_HEALTH is still 400")
	check(int(e["enemy_hp"]) == 400, "encounter 01 records 400 HP")
	check(int(e["hud_health_bar_max"]) == 400, "encounter health bar max is 400")
	check(stage_catalog.has(str(e["stage_id"])), "encounter stage resolves through the StageCatalog")
	check(str(e["stage_mode"]) == "host_selected", "encounter 01 does not pin a stage (host selection wins)")
	var briefing_source := _source("res://scripts/frontend/story_briefing.gd")
	check(str(e["objective"]) == "Defeat Bobo.", "objective matches the briefing exactly")
	check(e["rules"] == ["You have 3 stocks.", "Bobo does not attack."], "rules match the briefing exactly")
	check(str(e["flavor"]) == "A big goofball, and a very sturdy punching bag.", "flavor matches the briefing exactly")
	check(briefing_source.contains('"%s"' % str(e["objective"])), "objective literal still in story_briefing.gd")
	for rule in e["rules"]:
		check(briefing_source.contains('"%s"' % str(rule)), "rule literal still in story_briefing.gd: " + str(rule))
	check(briefing_source.contains('"%s"' % str(e["flavor"])), "flavor literal still in story_briefing.gd")
	check(_source("res://scenes/story_briefing.tscn").contains('text = "ENCOUNTER 01"'), "briefing scene still shows ENCOUNTER 01")
	var expected_allowed: Array = []
	for id in roster.ids():
		if str(id) != "ice_mage":
			expected_allowed.append(str(id))
	check(catalog.allowed_fighter_ids("story_01") == expected_allowed, "allowed fighters equal the story playable roster")
	check(not catalog.allowed_fighter_ids("story_01").has("ice_mage"), "ice_mage is excluded from the encounter")
	for id in catalog.allowed_fighter_ids("story_01"):
		check(fighter_catalog.has(str(id)), "allowed fighter resolves in the FighterCatalog: " + str(id))
	var player: Dictionary = e["player_slot"]
	check(str(player["kind"]) == "human" and int(player["device"]) == -1, "P1 is human keyboard (device -1)")
	var enemy: Dictionary = e["enemy_slot"]
	check(str(enemy["kind"]) == "bot" and str(enemy["difficulty"]) == "normal", "Bobo is a normal-difficulty bot")
	check(int(e["empty_slots"]) == 2, "encounter fills exactly two slots")
	check(not bool(e["teams_enabled"]), "encounter has no teams")
	check(int(e["player_stocks"]) == 3, "encounter gives the player 3 stocks")
	var main_source := _source("res://scripts/main.gd")
	check(Vector3(e["player_spawn"]) == Vector3(-4.0, 1.0, 0.0), "player spawn is p1_spawn")
	check(main_source.contains("var p1_spawn := Vector3(-4.0, 1.0, 0.0)"), "p1_spawn literal unchanged in main.gd")
	check(Vector3(e["enemy_spawn"]) == Vector3(0.6, 1.0, 0.0), "enemy spawn matches start_story")
	check(main_source.contains("player_two.reset_fighter(Vector3(0.6, 1.0, 0.0), true)"), "enemy spawn placement unchanged in main.gd")
	check(float(e["player_facing"]) == 1.0 and float(e["enemy_facing"]) == -1.0, "encounter facings match start_story")
	check(str(e["hud_title_template"]) == "STORY 01 — %s VS BOBO", "encounter HUD title template matches main.gd")
	check(main_source.contains('hud_title.text = "STORY 01 — %s VS BOBO"'), "HUD title template still in main.gd")
	check(main_source.contains("start_match(slots, false, true)"), "start_story launches the encounter without pinning a level")
	check(main_source.contains('slots[1].character = "bobo"'), "slot 1 is Bobo in start_story")
	check(main_source.contains("bobo_health_bar.max_value = 400"), "encounter health bar max still 400 in main.gd")
	var locked: Dictionary = e["result_copy"]
	check(str(locked["win_title"]) == "YOU'RE PRETTY COOL", "locked win title is the package copy")
	check(str(locked["win_detail"]) == "BOBO DEFEATED", "locked win detail is the package copy")
	check(str(locked["loss_title"]) == "TRY AGAIN", "locked loss title is the package copy")
	check(str(locked["loss_detail"]) == "Out of stocks. Bobo is still standing.", "locked loss detail is the package copy")
	check(locked["actions"] == ["REPLAY / RETRY", "CHANGE FIGHTER", "MAIN MENU"], "locked result actions are the package set")
	var shipped: Dictionary = e["shipped_copy"]
	check(str(shipped["win_title"]) == "your pretty cool", "shipped win literal recorded as-is")
	check(briefing_source.contains('"your pretty cool"'), "shipped win literal still in story_briefing.gd")
	check(str(shipped["win_detail"]) == "BOBO DEFEATED" and str(shipped["loss_title"]) == "TRY AGAIN", "shipped loss/win details recorded")
	check(str(shipped["loss_detail"]) == "Out of stocks. Bobo is still standing.", "shipped loss detail recorded")
	check(shipped["wired_actions"] == ["REPLAY / RETRY", "MAIN MENU"], "shipped actions are the two wired today")

# --- InputProfileCatalog --------------------------------------------------
func _input_profile_catalog() -> void:
	var catalog = load(INPUT_CATALOG)
	_purity(catalog, "InputProfileCatalog")
	var help_map: Dictionary = _constants("res://scripts/frontend/how_to_play.gd")
	check(catalog.ids() == help_map.get("PROFILES", []), "profile ids equal how_to_play.PROFILES exactly, same order")
	check(catalog.ids() == ["P1_KEYBOARD", "P2_KEYBOARD", "CONTROLLER"], "the three player-facing profiles")
	var bindings: Dictionary = help_map.get("BINDINGS", {})
	var how_to_play_scene := _source("res://scenes/how_to_play.tscn")
	var legacy_map: Dictionary = _constants("res://scripts/demo_style.gd")
	var legacy_controls := str(legacy_map.get("CONTROLS", ""))
	check(not legacy_controls.is_empty(), "legacy demo_style CONTROLS is still present")
	var expected_labels := {"P1_KEYBOARD": "P1 KEYBOARD", "P2_KEYBOARD": "P2 KEYBOARD", "CONTROLLER": "CONTROLLER"}
	for entry in catalog.all():
		var id := str(entry["id"])
		check(str(entry["label"]) == expected_labels[id], "profile label is the authored button text: " + id)
		check(how_to_play_scene.contains('text = "%s"' % str(entry["label"])), "profile label still authored in how_to_play.tscn: " + id)
		var entry_bindings: Dictionary = entry["bindings"]
		check(entry_bindings == bindings.get(id, {}), "bindings equal how_to_play.BINDINGS for " + id)
		check(entry_bindings.size() >= 6, "profile has a full binding set: " + id)
		var non_empty := true
		for row_id in entry_bindings.keys():
			if str(entry_bindings[row_id]).is_empty():
				non_empty = false
		check(non_empty, "every binding label is non-empty: " + id)
		var mentions: Array = entry["legacy_mentions"]
		check(not mentions.is_empty(), "legacy mention fragments recorded: " + id)
		for fragment in mentions:
			check(legacy_controls.contains(str(fragment)), "legacy CONTROLS still says \"%s\"" % str(fragment))
	check(FileAccess.file_exists(str(catalog.legacy_source().split("#")[0])), "legacy source file exists")
	check(str(catalog.by_id("P2_KEYBOARD")["bindings"]["special"]) == "L", "P2 keyboard special is L today")
	check(str(catalog.by_id("CONTROLLER")["bindings"]["jump"]) == "A", "controller jump is A today")

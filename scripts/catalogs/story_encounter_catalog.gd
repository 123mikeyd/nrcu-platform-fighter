extends RefCounted
# StoryEncounterCatalog — corrective package Doc 02 §8 (Catalogs), ledger G-041 / Q-033.
#
# ADDITIVE WP-0 migration step ONLY (Doc 02 §10.1: "Add catalogs without
# changing behavior"): pure, static data seeded from and verified against the
# CURRENT production sources. No runtime caller uses it yet; the Story Briefing,
# the Story Fighter Select route and the encounter launch migrate onto it in
# later work packages.
#
# Provenance of every field (current source of truth):
#   label / briefing copy  res://scripts/frontend/story_briefing.gd _build_enemy()
#                          + res://scenes/story_briefing.tscn ("ENCOUNTER 01")
#   enemy_id / enemy_hp    res://scripts/bobo_fighter.gd (MAX_HEALTH := 400.0),
#                          main.gd HUD "Bobo: 400 HP" and the 400-max health bar
#   allowed_fighter_ids    main.gd _story_playable_ids() (roster ids minus ice_mage)
#   slot / spawn metadata  main.gd start_story()
#   result copy            package Doc 01 §9 and Doc 05 "Story Result" (LOCKED wording);
#                          the current story_briefing.gd literals are recorded
#                          separately as shipped_copy because they differ today.
#
# Contract: static functions only, no scene access, no side effects, and every
# read returns fresh data (the catalog is never shared mutable state).

const BRIEFING_SOURCE := "res://scripts/frontend/story_briefing.gd#_build_enemy"
const BRIEFING_SCENE := "res://scenes/story_briefing.tscn"
const ENEMY_SOURCE := "res://scripts/bobo_fighter.gd#MAX_HEALTH"
const HOST_SOURCE := "res://scripts/main.gd#start_story"

const ENCOUNTER_IDS: Array[String] = ["story_01"]

static func entries() -> Array:
	return [
		{
			"id": "story_01",
			"label": "STORY 01",
			"encounter_label": "ENCOUNTER 01",
			"enemy_id": "bobo",
			"enemy_display_name": "BOBO",
			"enemy_hp": 400,
			"enemy_hp_source": ENEMY_SOURCE,
			# The encounter does not pin a stage today: the shipped story launch
			# left the level to the host default, and the effective default is the
			# first StageCatalog entry ("debug"). Recorded here as the effective
			# default, not as an authored encounter stage.
			"stage_mode": "host_selected",
			"stage_id": "debug",
			"objective": "Defeat Bobo.",
			"rules": ["You have 3 stocks.", "Bobo does not attack."],
			"flavor": "A big goofball, and a very sturdy punching bag.",
			"allowed_fighter_ids": ["teknium", "doge_man", "ggb", "turbofit", "witcheer", "mephisto"],
			"teams_enabled": false,
			"player_slot": {"kind": "human", "device": -1, "team": 0},
			"enemy_slot": {"kind": "bot", "device": -1, "difficulty": "normal", "team": 1},
			"empty_slots": 2,
			"player_stocks": 3,
			"player_spawn": Vector3(-4.0, 1.0, 0.0),
			"enemy_spawn": Vector3(0.6, 1.0, 0.0),
			"player_facing": 1.0,
			"enemy_facing": -1.0,
			"hud_title_template": "STORY 01 — %s VS BOBO",
			"hud_controls_source": HOST_SOURCE,
			"result_copy": {
				# Package-locked wording (Doc 01 §9 / Doc 05); supersedes the
				# lowercase shipped literal below once a later WP consumes it.
				"win_title": "YOU'RE PRETTY COOL",
				"win_detail": "BOBO DEFEATED",
				"loss_title": "TRY AGAIN",
				"loss_detail": "Out of stocks. Bobo is still standing.",
				"actions": ["REPLAY / RETRY", "CHANGE FIGHTER", "MAIN MENU"],
				"source": "package Doc 01 §9 / Doc 05",
			},
			"shipped_copy": {
				# Literal strings still emitted by story_briefing.gd show_result()
				# at this commit (kept for traceability, not as the target).
				"win_title": "your pretty cool",
				"win_detail": "BOBO DEFEATED",
				"loss_title": "TRY AGAIN",
				"loss_detail": "Out of stocks. Bobo is still standing.",
				"wired_actions": ["REPLAY / RETRY", "MAIN MENU"],
				"source": BRIEFING_SOURCE,
			},
			"hud_health_bar_max": 400,
		},
	]

static func ids() -> Array[String]:
	var out: Array[String] = ENCOUNTER_IDS.duplicate()
	return out

static func all() -> Array:
	return entries()

static func by_id(id: String) -> Dictionary:
	for entry in entries():
		if str(entry["id"]) == id:
			return entry
	return {}

static func has(id: String) -> bool:
	return not by_id(id).is_empty()

static func encounter_01() -> Dictionary:
	return by_id("story_01")

static func enemy_hp(id: String) -> int:
	var entry := by_id(id)
	return int(entry["enemy_hp"]) if not entry.is_empty() else 0

static func allowed_fighter_ids(id: String) -> Array[String]:
	var out: Array[String] = []
	var entry := by_id(id)
	if entry.is_empty():
		return out
	for fighter_id in entry["allowed_fighter_ids"]:
		out.append(str(fighter_id))
	return out

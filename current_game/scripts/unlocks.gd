extends RefCounted
# Local fighter unlocks (Mike 2026-09-30). Smash-style: meet a condition, then a
# "A NEW FIGHTER APPROACHES" challenger fight; beat them to unlock them.
#   Starters: Teknium, TurboFit, Doge Man.
#   GGB      - finish two versus matches.
#   Bobo     - heavy bag high score (BOBO_SCORE, best of any fighter).
#   Witcheer - clear Story mode once.
#   Mephisto - hardest gate: clear Story with all three starters AND unlock
#              GGB, Bobo and Witcheer.
# Ice Mage is a Story-only NPC and never playable. Dev Mode unlocks everything.
# Save: user://nrcu_unlocks.json (keeps the older "story_clears" count).
const PATH := "user://nrcu_unlocks.json"
const BAG_PATH := "user://heavy_bag_best.json"
const STARTERS := ["teknium", "turbofit", "doge_man"]
const CHALLENGERS := ["ggb", "bobo", "witcheer", "mephisto"]   # check order
const NEVER_PLAYABLE := ["ice_mage"]
const GGB_MATCHES := 2
# Scripted key-mash runs (2026-09-28) scored Tek 3865, Doge 1008, Turbo 4000.
# 4500 means shattering the core quickly - better than plain mashing.
const BOBO_SCORE := 4500
const CHALLENGER_DIFFICULTY := {"ggb": "normal", "bobo": "normal", "witcheer": "normal", "mephisto": "hard"}

# Tests point these at scratch files; headless runs never touch the real save.
static var path_override := ""
static var bag_path_override := ""

static func _path() -> String:
	return path_override if path_override != "" else PATH

static func _load() -> Dictionary:
	var p := _path()
	if not FileAccess.file_exists(p): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Dictionary else {}

static func _save(data: Dictionary) -> void:
	if path_override == "" and (DisplayServer.get_name() == "headless" or review_launcher()): return
	var file := FileAccess.open(_path(), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data, "\t"))

## Review launchers (tools/play_*.gd) open locked fighters and never save progress.
static func review_launcher() -> bool:
	var args := OS.get_cmdline_args()
	var i := args.find("--script")
	return i >= 0 and i + 1 < args.size() and args[i + 1].begins_with("res://tools/")

## Older headless tests (no scratch save) see the full roster, like Dev Mode.
## Unlock tests opt in to real locks by setting path_override.
static func legacy_headless() -> bool:
	return path_override == "" and DisplayServer.get_name() == "headless"

static func _dev_on() -> bool:
	if review_launcher() or legacy_headless(): return true
	var tree = Engine.get_main_loop()
	if not tree is SceneTree: return false
	var dev = tree.root.get_node_or_null("/root/DevMode")
	return dev != null and dev.enabled

# ------------------------------------------------------------------ queries
static func story_clears() -> int:
	return int(_load().get("story_clears", 0))

static func story_heroes() -> Array:
	return _load().get("story_heroes", [])

static func versus_matches() -> int:
	return int(_load().get("versus_matches", 0))

static func best_bag_score() -> int:
	var p := bag_path_override if bag_path_override != "" else BAG_PATH
	if not FileAccess.file_exists(p): return 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	var best := 0
	if parsed is Dictionary:
		for v in parsed.values(): best = maxi(best, int(v))
	return best

static func earned(id: String) -> bool:
	return id in STARTERS or id in _load().get("unlocked", [])

## Real play hides Story-only NPCs; review launchers and older tests keep them.
static func hide_npcs() -> bool:
	return not (review_launcher() or legacy_headless())

static func is_playable(id: String) -> bool:
	if id in NEVER_PLAYABLE: return not hide_npcs()
	return _dev_on() or earned(id)

static func is_locked(id: String) -> bool:
	return not is_playable(id)

static func condition_met(id: String) -> bool:
	match id:
		"ggb": return versus_matches() >= GGB_MATCHES
		"bobo": return best_bag_score() >= BOBO_SCORE
		"witcheer": return story_clears() >= 1
		"mephisto":
			var heroes := story_heroes()
			for s in STARTERS:
				if s not in heroes: return false
			return earned("ggb") and earned("bobo") and earned("witcheer")
	return false

## Next fighter waiting to challenge the player, or "" (never in Dev Mode).
static func next_challenger() -> String:
	if _dev_on(): return ""
	for id in CHALLENGERS:
		if not earned(id) and condition_met(id): return id
	return ""

# Back-compat for older callers.
static func mephisto_unlocked() -> bool:
	return is_playable("mephisto")

# ------------------------------------------------------------------ records
static func record_versus_match() -> void:
	var data := _load()
	data["versus_matches"] = int(data.get("versus_matches", 0)) + 1
	_save(data)

static func record_story_clear(hero: String = "") -> void:
	var data := _load()
	data["story_clears"] = int(data.get("story_clears", 0)) + 1
	var heroes: Array = data.get("story_heroes", [])
	if hero != "" and hero not in heroes: heroes.append(hero)
	data["story_heroes"] = heroes
	_save(data)

static func record_unlock(id: String) -> void:
	var data := _load()
	var unlocked: Array = data.get("unlocked", [])
	if id not in unlocked: unlocked.append(id)
	data["unlocked"] = unlocked
	_save(data)

# ------------------------------------------------------------------ UI
static func locked_text() -> String:
	return "??? (Locked)"

## Grey out locked fighters in an OptionButton. Item metadata (String id) wins;
## otherwise index i maps to ids[i]. names[i] (if given) is the unlocked label,
## else the roster display name. Never leaves a locked fighter selected.
static func apply_to_option(option: OptionButton, ids: Array, names: Array = []) -> void:
	var roster = load("res://scripts/roster.gd")
	for i in option.item_count:
		var meta = option.get_item_metadata(i)
		var id: String = meta if meta is String else (ids[i] if i < ids.size() else "")
		if id == "" or option.is_item_separator(i): continue
		var locked := is_locked(id)
		option.set_item_disabled(i, locked)
		option.set_item_text(i, locked_text() if locked else (names[i] if i < names.size() else roster.display_name(id)))
	if option.item_count > 0 and option.selected >= 0 and option.is_item_disabled(option.selected):
		for i in option.item_count:
			if not option.is_item_disabled(i) and not option.is_item_separator(i):
				option.select(i)
				break

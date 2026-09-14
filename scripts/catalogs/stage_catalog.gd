extends RefCounted
# StageCatalog — corrective package Doc 02 §8 (Catalogs), ledger G-039 / SS-010 / Q-033.
#
# ADDITIVE WP-0 migration step ONLY (Doc 02 §10.1: "Add catalogs without
# changing behavior"): pure, static data seeded from and verified against the
# CURRENT production sources. No runtime caller uses it yet; production SSS and
# Debug Match Setup both migrate onto it in later work packages.
#
# Provenance of every field (current source of truth):
#   id              the stage id list itself (superseded match_setup.LEVEL_IDS
#                   in WP-0 step 8: this catalog is now the only source and the
#                   debug setup consumes it directly)
#   display_name    res://scripts/main.gd _build_stage_panel(): the production SSS
#                   label is the setup option text up to " (" uppercased
#   caption         res://scripts/match_setup.gd stage-card captions
#   dropdown_text   res://scripts/match_setup.gd level OptionButton item texts
#   thumbnail       res://assets/menu/stage_<id>.png (production SSS slot "tex")
#   gameplay        main.gd apply_level(): "debug" shows debug visuals; any other
#                   id builds stage_theme.gd with level_id, which mounts
#                   stage_details.gd (toy_room -> room(), everything else -> sky())
#   selectable      all three levels are selectable today (no hidden stage)
#
# Contract: static functions only, no scene access, no side effects, and every
# read returns fresh data (the catalog is never shared mutable state).

const THEME_SCRIPT := "res://scripts/stage_theme.gd"
const DETAILS_SCRIPT := "res://scripts/stage_details.gd"
const THUMBNAIL_DIR := "res://assets/menu/"
const SETUP_SOURCE := "res://scripts/match_setup.gd#_level_texts"
const SSS_SOURCE := "res://scripts/match_flow.gd#_stage_slots"

static func entries() -> Array:
	# Fresh dictionaries on every call; order is the shipped stage order.
	return [
		{
			"id": "debug",
			"display_name": "DEBUG ARENA",
			"caption": "Debug Arena",
			"dropdown_text": "Debug Arena (original)",
			"thumbnail": THUMBNAIL_DIR + "stage_debug.png",
			"selectable": true,
			"gameplay": {
				"stage_id": "debug",
				"theme_script": THEME_SCRIPT,
				"details_level": "",
				"debug_visuals": true,
			},
		},
		{
			"id": "toy_room",
			"display_name": "TOY SHELF / BEDROOM",
			"caption": "Toy Shelf",
			"dropdown_text": "Toy Shelf / Bedroom",
			"thumbnail": THUMBNAIL_DIR + "stage_toy_room.png",
			"selectable": true,
			"gameplay": {
				"stage_id": "toy_room",
				"theme_script": THEME_SCRIPT,
				"details_level": "toy_room",
				"debug_visuals": false,
			},
		},
		{
			"id": "sky",
			"display_name": "SKY SANCTUARY",
			"caption": "Sky Sanctuary",
			"dropdown_text": "Sky Sanctuary",
			"thumbnail": THUMBNAIL_DIR + "stage_sky.png",
			"selectable": true,
			"gameplay": {
				"stage_id": "sky",
				"theme_script": THEME_SCRIPT,
				"details_level": "sky",
				"debug_visuals": false,
			},
		},
	]

static func ids() -> Array[String]:
	var out: Array[String] = []
	for entry in entries():
		out.append(str(entry["id"]))
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

static func display_name(id: String) -> String:
	var entry := by_id(id)
	return str(entry["display_name"]) if not entry.is_empty() else "Unknown"

static func name_for(id: String) -> String:
	return display_name(id)

static func thumbnail(id: String) -> String:
	var entry := by_id(id)
	return str(entry["thumbnail"]) if not entry.is_empty() else ""

static func is_selectable(id: String) -> bool:
	var entry := by_id(id)
	return bool(entry["selectable"]) if not entry.is_empty() else false

static func selectable_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in entries():
		if bool(entry["selectable"]):
			out.append(str(entry["id"]))
	return out

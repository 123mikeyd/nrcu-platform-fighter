extends RefCounted
# FighterCatalog — corrective package Doc 02 §8 (Catalogs), ledger G-040 / Q-033.
#
# ADDITIVE WP-0 migration step ONLY (Doc 02 §10.1: "Add catalogs without
# changing behavior"): this module is pure, static data seeded from and
# verified against the CURRENT production sources. No runtime caller uses it
# yet; flipping callers over (CL-005, MatchConfig de-duplication, Story Fighter
# Select) happens in later work packages.
#
# Provenance of every field (current source of truth):
#   id / display_name   res://scripts/roster.gd (ids(), display_name())
#   portrait_path       res://scripts/frontend/portrait_data.gd (DIR + id + ".png")
#   story_playable      res://scripts/main.gd _story_playable_ids()  (roster minus ice_mage)
#   presentation        res://scripts/fighter.gd _build_visuals() per-id visual module;
#                       key also indexes stage_theme.gd MODELS and
#                       fighter_presentation_factory.gd FRAME_OVERRIDES (WP-3:
#                       per-fighter windows are derived from each fighter's
#                       measured silhouette; this table holds only the authored
#                       overrides a rendered silhouette proved necessary)
#   help_definition     res://scripts/frontend/how_to_play.gd MOVE_LISTS / GENERIC_MOVES
#   palette_policy      res://scripts/roster.gd palette() hue table and slot policy
#
# Contract: static functions only, no scene access, no side effects, and every
# read returns fresh data (the catalog is never shared mutable state).

const PORTRAIT_DIR := "res://assets/portraits/"
const ROSTER_NAME_FALLBACK := "Unknown"

const PRESENTATION_SOURCE := "res://scripts/fighter.gd#_build_visuals"
const MODELS_SOURCE := "res://scripts/stage_theme.gd#MODELS"
const RENDER_VIEW_SOURCE := "res://scripts/frontend/fighter_presentation_factory.gd#FRAME_OVERRIDES"
const HELP_SOURCE := "res://scripts/frontend/how_to_play.gd#MOVE_LISTS"
const HELP_FALLBACK := "GENERIC_MOVES"
const PALETTE_SOURCE := "res://scripts/roster.gd#palette"
const PALETTE_SLOT_VARIANTS := 4
const PALETTE_SLOT_STEP := 0.18
const PALETTE_SATURATION := 0.76
const PALETTE_VALUE := 0.95

static func entries() -> Array:
	# Fresh dictionaries on every call; order is roster.gd ids() order.
	return [
		{
			"id": "teknium",
			"display_name": "Teknium",
			"portrait_path": PORTRAIT_DIR + "teknium.png",
			"story_playable": true,
			"presentation": {
				"key": "teknium",
				"visual_module": "res://scripts/teknium_visual.gd",
				"frame_override_profiles": ["PORTRAIT"],
			},
			"help_definition": {"source": HELP_SOURCE, "moves_key": "teknium", "curated": true, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.36, "base_hue_explicit": true,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				"preserves_painted_materials": false,
			},
		},
		{
			"id": "doge_man",
			"display_name": "Doge Man",
			"portrait_path": PORTRAIT_DIR + "doge_man.png",
			"story_playable": true,
			"presentation": {
				"key": "doge_man",
				"visual_module": "res://scripts/doge_visual.gd",
				"frame_override_profiles": ["PORTRAIT"],
			},
			"help_definition": {"source": HELP_SOURCE, "moves_key": "doge_man", "curated": true, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.09, "base_hue_explicit": true,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				"preserves_painted_materials": false,
			},
		},
		{
			"id": "ggb",
			"display_name": "GGB",
			"portrait_path": PORTRAIT_DIR + "ggb.png",
			"story_playable": true,
			"presentation": {
				"key": "ggb",
				"visual_module": "res://scripts/ggb_visual.gd",
				"frame_override_profiles": ["PORTRAIT", "PLAYER_BAY", "RESULTS_HERO", "RESULTS_TEAM"],
			},
			"help_definition": {"source": HELP_SOURCE, "moves_key": "ggb", "curated": true, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.60, "base_hue_explicit": true,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				# roster.gd: "GGB preserves original painted materials."
				"preserves_painted_materials": true,
			},
		},
		{
			"id": "turbofit",
			# roster.gd is the identity source the runtime renders (HUD/fighter_name).
			# match_config.gd NAMES spells it "TurboFit": a live duplicate-source drift
			# (G-040) recorded here instead of silently normalizing either side.
			"display_name": "Turbofit",
			"display_name_drift": "TurboFit",
			"display_name_drift_source": "res://scripts/match_config.gd#NAMES",
			"portrait_path": PORTRAIT_DIR + "turbofit.png",
			"story_playable": true,
			"presentation": {
				"key": "turbofit",
				"visual_module": "res://scripts/turbofit_visual.gd",
				"frame_override_profiles": ["PORTRAIT"],
			},
			"help_definition": {"source": HELP_SOURCE, "moves_key": "turbofit", "curated": true, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.94, "base_hue_explicit": true,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				"preserves_painted_materials": false,
			},
		},
		{
			"id": "ice_mage",
			"display_name": "Ice Mage",
			"portrait_path": PORTRAIT_DIR + "ice_mage.png",
			# main.gd _story_playable_ids() removes ice_mage from Story P1.
			"story_playable": false,
			"presentation": {
				"key": "ice_mage",
				"visual_module": "res://scripts/ice_mage_visual.gd",
				"frame_override_profiles": ["PORTRAIT"],
			},
			"help_definition": {"source": HELP_SOURCE, "moves_key": "ice_mage", "curated": true, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.57, "base_hue_explicit": true,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				"preserves_painted_materials": false,
			},
		},
		{
			"id": "witcheer",
			"display_name": "Witcheer",
			"portrait_path": PORTRAIT_DIR + "witcheer.png",
			"story_playable": true,
			"presentation": {
				"key": "witcheer",
				"visual_module": "res://scripts/witcheer_visual.gd",
				"frame_override_profiles": ["PORTRAIT"],
			},
			"help_definition": {"source": HELP_SOURCE, "moves_key": "witcheer", "curated": true, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.36, "base_hue_explicit": false,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				"preserves_painted_materials": false,
			},
		},
		{
			"id": "mephisto",
			"display_name": "Mephisto",
			"portrait_path": PORTRAIT_DIR + "mephisto.png",
			"story_playable": true,
			"presentation": {
				"key": "mephisto",
				"visual_module": "res://scripts/mephisto_visual.gd",
				"frame_override_profiles": ["PORTRAIT"],
			},
			# how_to_play.gd has no curated MOVE_LISTS entry: GENERIC_MOVES apply.
			"help_definition": {"source": HELP_SOURCE, "moves_key": "mephisto", "curated": false, "fallback": HELP_FALLBACK},
			"palette_policy": {
				"source": PALETTE_SOURCE, "base_hue": 0.065, "base_hue_explicit": true,
				"slot_variants": PALETTE_SLOT_VARIANTS, "slot_step": PALETTE_SLOT_STEP,
				"saturation": PALETTE_SATURATION, "value": PALETTE_VALUE,
				"preserves_painted_materials": false,
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
	return str(entry["display_name"]) if not entry.is_empty() else ROSTER_NAME_FALLBACK

static func name_for(id: String) -> String:
	return display_name(id)

static func portrait_path(id: String) -> String:
	return PORTRAIT_DIR + id + ".png"

static func is_story_playable(id: String) -> bool:
	var entry := by_id(id)
	return bool(entry["story_playable"]) if not entry.is_empty() else false

static func story_playable_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in entries():
		if bool(entry["story_playable"]):
			out.append(str(entry["id"]))
	return out

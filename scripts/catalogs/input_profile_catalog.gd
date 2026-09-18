extends RefCounted
# InputProfileCatalog — corrective package Doc 02 §8 (Catalogs), ledger G-042 / Q-033.
#
# ADDITIVE WP-0 migration step ONLY (Doc 02 §10.1: "Add catalogs without
# changing behavior"): pure, static data seeded from and verified against the
# CURRENT production sources. No runtime caller uses it yet; How to Play and any
# retained HUD help migrate onto it in later work packages.
#
# Provenance of every field (current source of truth):
#   profiles / bindings  res://scripts/frontend/how_to_play.gd (PROFILES, BINDINGS)
#   label                res://scenes/how_to_play.tscn (ProfileP1/P2/Ctrl button text)
#   legacy_mentions      res://scripts/demo_style.gd CONTROLS (legacy help page,
#                        still present at this commit; kept as a reference, not
#                        copied wholesale)
#
# Contract: static functions only, no scene access, no side effects, and every
# read returns fresh data (the catalog is never shared mutable state).

const SOURCE := "res://scripts/frontend/how_to_play.gd#BINDINGS"
const LABEL_SOURCE := "res://scenes/how_to_play.tscn#ProfileControl"
const LEGACY_SOURCE := "res://scripts/demo_style.gd#CONTROLS"

static func entries() -> Array:
	# Fresh dictionaries on every call; order is how_to_play.PROFILES order.
	return [
		{
			"id": "P1_KEYBOARD",
			"label": "P1 KEYBOARD",
			"bindings": {
				"move": "WASD", "jump": "SPACE / W", "basic": "F", "special": "G",
				"shield": "E", "drop": "S", "none": "—",
			},
			"legacy_mentions": [
				"WASD move / aim", "Space or W jump", "F basic", "G special", "E shield",
			],
			"source": SOURCE,
			"label_source": LABEL_SOURCE,
			"legacy_source": LEGACY_SOURCE,
		},
		{
			"id": "P2_KEYBOARD",
			"label": "P2 KEYBOARD",
			"bindings": {
				"move": "ARROWS", "jump": "ENTER / UP", "basic": "K", "special": "L",
				"shield": "O", "drop": "DOWN", "none": "—",
			},
			"legacy_mentions": [
				"Arrows move / aim", "Enter or Up jump", "K basic", "L special", "O shield",
			],
			"source": SOURCE,
			"label_source": LABEL_SOURCE,
			"legacy_source": LEGACY_SOURCE,
		},
		{
			"id": "CONTROLLER",
			"label": "CONTROLLER",
			"bindings": {
				"move": "STICK / D-PAD", "jump": "A", "basic": "X", "special": "B",
				"shield": "SHOULDER", "drop": "DOWN", "none": "—",
			},
			"legacy_mentions": [
				"Stick / D-pad aim", "A jump", "X basic", "B special", "shoulder shield",
			],
			"source": SOURCE,
			"label_source": LABEL_SOURCE,
			"legacy_source": LEGACY_SOURCE,
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

static func label_for(id: String) -> String:
	var entry := by_id(id)
	return str(entry["label"]) if not entry.is_empty() else ""

static func bindings_for(id: String) -> Dictionary:
	var entry := by_id(id)
	return entry["bindings"] if not entry.is_empty() else {}

static func legacy_source() -> String:
	return LEGACY_SOURCE

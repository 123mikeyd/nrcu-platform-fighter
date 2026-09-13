class_name MatchLaunchConfig
extends RefCounted
# MatchLaunchConfig — the immutable launch snapshot (corrective package Doc 02 §3).
#
# ADDITIVE WP-0 migration step 2 (Doc 02 §10.2 "Add typed MatchFlowState +
# adapters"). Nothing existing references this file yet; making Gameplay accept
# it is migration step 5, and the router is what hands it over.
#
# What it is: the frozen result of a VALIDATED MatchFlowState — mode, resolved
# slots, the launch stage, and the Story encounter payload when the state is a
# Story state. What it is not: it holds no screen, node, Control or OptionButton
# reference and nothing it contains can reach back into Character Select, Stage
# Select, the Debug Setup model or any other live UI (Doc 02 §3: "Gameplay
# receives an immutable snapshot. It does not reach back into CSS, hidden
# OptionButtons, Debug Setup, or screen nodes").
#
# Construction goes through build(), which runs the ONE validation authority
# (MatchFlowState.validate_for_launch) before freezing anything. An invalid
# state never produces a payload: build() returns a config that reports
# is_valid() == false and carries validation_error() instead of slots/stage. It
# never returns null, so callers cannot forget a null check — but they must
# still check is_valid() before launching.
#
# Immutability: state fields are private and every read accessor returns a fresh
# deep copy, so a config cannot be changed by the state it came from, by a
# consumer that mutates what it read, or (by convention) by a caller writing the
# underscore fields.

const SELF_PATH := "res://scripts/match_launch_config.gd"

const StateScript = preload("res://scripts/match_flow_state.gd")
const EncounterCatalog = preload("res://scripts/catalogs/story_encounter_catalog.gd")

const MESSAGE_FLOW_REQUIRED := "MatchLaunchConfig needs a MatchFlowState to snapshot."

var _valid := false
var _error := ""
var _mode := 0                 # MatchFlowState.Mode
var _stage_id := ""
var _story_encounter_id := ""
var _story: Dictionary = {}
var _slots: Array = []         # frozen dictionaries, see build()

static func _blank() -> RefCounted:
	return (load(SELF_PATH) as GDScript).new()

static func build(flow: StateScript, for_stage_id: String = "") -> RefCounted:
	# `flow` must be a MatchFlowState; `for_stage_id` is the Stage Select
	# selection being launched with (Stage Select owns it). Empty means "use the
	# stage the state already records".
	var config = _blank()
	if flow == null:
		config._valid = false
		config._error = MESSAGE_FLOW_REQUIRED
		return config
	var error: String = flow.validate_for_launch(for_stage_id)
	config._error = error
	if error != "":
		config._valid = false
		return config
	config._valid = true
	config._mode = int(flow.mode)
	config._stage_id = str(for_stage_id) if str(for_stage_id) != "" else str(flow.stage_id)
	config._story_encounter_id = str(flow.story_encounter_id)
	if config._story_encounter_id != "":
		# The encounter payload gameplay/post-match needs, deep-copied out of the
		# catalog so the snapshot owns its own data.
		config._story = EncounterCatalog.by_id(config._story_encounter_id).duplicate(true)
	var frozen: Array = []
	var index := 0
	for entry in flow.slots:
		frozen.append({
			"index": index,
			"kind": int(entry.kind),                    # MatchFlowState.Kind
			"fighter_id": str(entry.fighter_id),
			"difficulty": str(entry.difficulty),
			"team_id": int(entry.team_id),
			"input_source": entry.input_source.duplicate(true) if entry.input_source is Dictionary else {},
			"palette_index": int(entry.palette_index),
		})
		index += 1
	config._slots = frozen
	return config

# --- reads (every one returns a fresh copy) --------------------------------

func is_valid() -> bool:
	return _valid

func validation_error() -> String:
	return _error

func mode() -> int:
	return _mode

func stage_id() -> String:
	return _stage_id

func story_encounter_id() -> String:
	return _story_encounter_id

func has_story() -> bool:
	return _story_encounter_id != ""

func story_payload() -> Dictionary:
	return _story.duplicate(true)

func slot_count() -> int:
	return _slots.size()

func slots() -> Array:
	return _slots.duplicate(true)

func slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {}
	var entry = _slots[index]
	return entry.duplicate(true) if entry is Dictionary else {}

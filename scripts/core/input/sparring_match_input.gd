extends "res://scripts/core/input/repo_ai_match_input.gd"
## Our P2-only Sparring / Easy wrapper. No lab/UI default changes.
## Reuses the reviewed value-observation/clock owner, NOT Mikey decision logic.
## Switching owners requires the caller's full match + input reset transaction.
const Sparring = preload("res://scripts/core/input/sparring_input_source.gd")
const LABEL = "Sparring / Easy (ours)"

func _init() -> void:
	ai = Sparring.new()

func configure(entity_id: int, use_ai: bool, difficulty_value: String = "easy") -> bool:
	if entity_id != 2 or difficulty_value != "easy": return false
	enabled = use_ai
	ai.configure("easy")
	reset()
	return true

func _copy_frames(frames: Dictionary) -> Dictionary:
	var result: Dictionary = super._copy_frames(frames)
	if enabled and result.has(2): result[2].source_id = "sparring_easy"
	return result

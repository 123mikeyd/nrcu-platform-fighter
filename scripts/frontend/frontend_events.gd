extends Node
# FrontendEvents — semantic UI events (Step 0 §23).
#
# Audio follows accepted semantic state change: input → validate → accepted
# transition → emit event → play sound. No sound assets exist yet, so this
# node is the hook layer only; a future FrontendAudio maps events to assets.
# Emit ONCE per accepted change — never from both a Button default and a
# screen controller for the same action.

signal nav_move(direction: Vector2)
signal confirm(action_id: String)
signal back(screen_id: String)
signal error(reason: String)
signal token_pickup(player_index: int)
signal token_place(player_index: int)
signal ready_state(valid: bool)
signal stage_confirm(stage_id: String)
signal results_reveal()

func emit_nav(direction: Vector2) -> void:
    nav_move.emit(direction)

func emit_confirm(action_id: String) -> void:
    confirm.emit(action_id)

func emit_back(screen_id: String) -> void:
    back.emit(screen_id)

func emit_error(reason: String) -> void:
    error.emit(reason)

func emit_token_pickup(player_index: int) -> void:
    token_pickup.emit(player_index)

func emit_token_place(player_index: int) -> void:
    token_place.emit(player_index)

func emit_ready(valid: bool) -> void:
    ready_state.emit(valid)

func emit_stage_confirm(stage_id: String) -> void:
    stage_confirm.emit(stage_id)

func emit_results_reveal() -> void:
    results_reveal.emit()

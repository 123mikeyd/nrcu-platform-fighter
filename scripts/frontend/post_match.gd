extends Control
# PostMatch — the standalone post-match frontend surface (corrective package
# Doc 02 §1 "POST-MATCH" box, §5 router verbs, §10.6 "Move multiplayer Results /
# Story result into PostMatch frontend").
#
# WHAT THIS IS
#   The MatchFlow host's PostMatch surface. It instantiates the SHIPPED
#   result_screen script (visuals unchanged — the Results semantics/redesign is
#   WP-5) and presents it over the immutable MatchResult payload the completed
#   match handed to the router. It owns the surface-level semantics that used to
#   live in the arena HUD (main.gd):
#     * the reveal/action lifecycle, delegated to result_screen.gd;
#     * Results cancel (Doc 01 §14): after the reveal safety, ui_cancel takes
#       the SAME semantic route as the visible MAIN MENU action, and the first
#       input that merely completes/skips the reveal never also leaves the
#       screen.
#
# WHAT THIS IS NOT
#   It does not own routes. The four visible actions are emitted as requests and
#   the router implements them (REMATCH -> LAUNCH from the preserved
#   MatchLaunchConfig, CHANGE FIGHTERS / CHANGE STAGE -> PUSH with origin
#   RESULTS, MAIN MENU -> clear the stack to Main). It never reads a live
#   fighter: the typed payload is the only end-state authority (Doc 02 §4).

signal rematch_requested
signal change_fighters_requested
signal change_stage_requested
signal menu_requested
signal exit_finished

const ResultScreenScript = preload("res://scripts/result_screen.gd")
const DemoStyle = preload("res://scripts/demo_style.gd")

var result_screen: Control = null
var outcome_label: Label = null

var _exiting := false

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    theme = DemoStyle.make()
    var shade := ColorRect.new()
    shade.name = "Shade"
    shade.color = Color("273a37")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(shade)
    result_screen = ResultScreenScript.new()
    result_screen.name = "ResultScreen"
    add_child(result_screen)
    outcome_label = result_screen.outcome_label
    result_screen.rematch_requested.connect(_on_action.bind("rematch"))
    result_screen.setup_requested.connect(_on_action.bind("change_fighters"))
    result_screen.stage_requested.connect(_on_action.bind("change_stage"))
    result_screen.menu_requested.connect(_on_action.bind("menu"))
    hide()

# --- presentation -----------------------------------------------------------
# The router drives the §7 lifecycle; the surface adapts to the shipped
# result_screen API.

func present(result, allow_stage_change: bool = true) -> void:
    # Fresh entry: the immutable payload starts the shipped reveal.
    _exiting = false
    show()
    result_screen.show_result(result, allow_stage_change)

func prepare_fresh() -> void:
    # §7 prepare_fresh_entry: authored baseline before a fresh presentation.
    _exiting = false
    modulate.a = 1.0

func prepare_return() -> void:
    # §7 prepare_return_entry (POP back from SSS): restore the authored frame
    # WITHOUT replaying the reveal — the revealed screen is kept as it was.
    _exiting = false
    modulate.a = 1.0

func play_exit() -> void:
    # Shipped Results exit is an immediate release (motion is WP-6); the host
    # hides the surface when the exit reports finished.
    if _exiting:
        return
    _exiting = true
    call_deferred("_finish_exit")

func _finish_exit() -> void:
    exit_finished.emit()

func is_exiting() -> bool:
    return _exiting

# --- actions ----------------------------------------------------------------

func _on_action(action_id: String) -> void:
    match action_id:
        "rematch":
            rematch_requested.emit()
        "change_fighters":
            change_fighters_requested.emit()
        "change_stage":
            change_stage_requested.emit()
        "menu":
            menu_requested.emit()

# --- cancel (Doc 01 §14) ----------------------------------------------------

func _input(event: InputEvent) -> void:
    # Runs before the GUI stage, mirroring result_screen.gd. The
    # is_visible_in_tree() guard is required: the host keeps the surface
    # mounted while it is not presented, and a hidden surface must neither
    # consume nor answer input.
    if not is_visible_in_tree() or result_screen == null:
        return
    if not _is_cancel_press(event):
        return
    if result_screen.is_revealing():
        if result_screen.reveal_tick() < ResultScreenScript.SAFETY_TICKS:
            # Carry-over window: ignored, exactly like the reveal-skip path.
            return
        # The input merely completes/skips the reveal. It is consumed and NEVER
        # also leaves the screen (one input, one action).
        result_screen.finish_reveal()
        get_viewport().set_input_as_handled()
        return
    if not result_screen.is_interactive():
        return
    # After reveal safety: same semantic route as the visible MAIN MENU action.
    get_viewport().set_input_as_handled()
    _on_action("menu")

func _is_cancel_press(event: InputEvent) -> bool:
    if event is InputEventKey:
        return event.pressed and not event.echo and event.keycode == KEY_ESCAPE
    if event is InputEventJoypadButton:
        # ui_cancel on this surface is the documented Back button (Doc 03 §11);
        # gameplay owns B as Special, the frontend does not.
        return event.pressed and InputMap.event_is_action(event, "ui_cancel")
    return false

# --- reads (tests / evidence) ----------------------------------------------

func is_interactive() -> bool:
    return result_screen != null and result_screen.is_interactive()

func is_revealing() -> bool:
    return result_screen != null and result_screen.is_revealing()

func is_outcome_revealed() -> bool:
    return result_screen != null and result_screen.is_outcome_revealed()

func get_result():
    return result_screen.get_result() if result_screen != null else null

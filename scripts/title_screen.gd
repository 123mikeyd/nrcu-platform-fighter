extends Control
# NRCU Title / Start screen — Step 1 (Doc 02), authored in scenes/title.tscn.
#
# The script owns: entry/exit state, release-arming, ambient time, background
# offset, prompt opacity and the semantic Start event. The fixed composition
# (background frame, title group, start region, build marker) lives in the
# scene; the ReferenceFrame keeps the core composition centered on expanded
# aspects.
#
# Background motion (Doc 02 §6/§7): NO animated scale. One constant
# cover/overscan scale plus a tiny derivative-continuous positional drift:
#   x(t) = 3.00*sin(TAU*t/31) + 0.75*sin(TAU*t/53 + 1.1)
#   y(t) = 1.35*sin(TAU*t/37 + 0.7) + 0.35*sin(TAU*t/61 + 2.0)
# The drift can never expose an edge because the background control is grown
# by OVERSCAN on every side.
#
# Start input (Doc 02 §10): release-arming, not an arbitrary timer. A fresh
# non-echo press is required (input held from before activation only produces
# echoes or a press that arrived while the entry guard was up), the event is
# latched, the semantic Start fires exactly once.

const Tokens = preload("res://scripts/ui_tokens.gd")

const MENU_SCENE := "res://scenes/home.tscn"
const PROMPT_TEXT := "CLICK OR PRESS ANY KEY"
const OVERSCAN := 48.0
const ENTRY_GUARD_SECONDS := 0.35
const ENTRY_SETTLE_PX := 10.0
const EXIT_SECONDS := 14.0 / 60.0
const PROMPT_PERIOD := 2.9
const PROMPT_MIN := 0.60
const PROMPT_MAX := 0.95
const PROMPT_ENTRY_DELAY := 10.0 / 60.0
const PROMPT_ENTRY_FADE := 10.0 / 60.0
const PROMPT_PRESS_SECONDS := 0.12

signal start_accepted()

@onready var _bg: TextureRect = $BackgroundFrame/ShelfBackground
@onready var _title_group: Control = $ReferenceFrame/TitleGroup
@onready var _accent: Panel = $ReferenceFrame/TitleGroup/AccentRule
@onready var _subtitle: Label = $ReferenceFrame/TitleGroup/Subtitle
@onready var _start_region: Control = $ReferenceFrame/StartRegion
@onready var _left_rule: Panel = $ReferenceFrame/StartRegion/LeftRule
@onready var _prompt: Label = $ReferenceFrame/StartRegion/Prompt
@onready var _right_rule: Panel = $ReferenceFrame/StartRegion/RightRule
@onready var _anchor: Control = $ReferenceFrame/StartRegion/CursorAnchor
@onready var _build: Label = $ReferenceFrame/BuildMarker

var _t := 0.0
var _drift := Vector2.ZERO
var _frozen := false
var _entry_guard_remaining := ENTRY_GUARD_SECONDS
var _arming_checked := false
var _blocked_by_held_input := false
var _armed := false
var _prompt_entry_elapsed := 0.0
var _prompt_press_remaining := 0.0
var _leaving := false
var _starts := 0

func _ready() -> void:
    Frontend.set_window_policy()
    theme = Tokens.make_theme()
    _style_nodes()
    _layout_start_region()
    _entry_animation()
    _update_prompt_alpha()
    var cursor := get_node_or_null("/root/Cursor")
    if cursor != null and cursor.hand != null:
        var hand = cursor.hand
        hand.begin_screen("title")
        # In focus mode the hand settles at the authored prompt anchor.
        if hand.mode == 1:
            hand.set_focus_target(_anchor)

func _style_nodes() -> void:
    _title_group.add_theme_color_override("font_color", Tokens.CREAM)
    $ReferenceFrame/TitleGroup/NRCUTitle.add_theme_color_override("font_color", Tokens.CREAM)
    _accent.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _subtitle.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    _prompt.add_theme_color_override("font_color", Tokens.CREAM)
    _left_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _right_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _left_rule.modulate.a = 0.55
    _right_rule.modulate.a = 0.55
    _left_rule.size.y = 3.0
    _right_rule.size.y = 3.0
    _build.add_theme_color_override("font_color", Tokens.CREAM_DIM)

func _layout_start_region() -> void:
    # Rules frame the prompt without enclosing it; lengths derive from the
    # real font metrics. The focus anchor sits below-left so the pointing hand
    # never covers a glyph (Doc 02 §4).
    var font := _prompt.get_theme_font("font")
    var fs := _prompt.get_theme_font_size("font_size")
    var text_w := 260.0
    if font != null:
        text_w = font.get_string_size(PROMPT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    var gap := Tokens.S12
    var rule_w := 44.0
    _left_rule.position = Vector2(0.0, 19.0)
    _left_rule.size = Vector2(rule_w, 3.0)
    _prompt.position = Vector2(rule_w + gap, 0.0)
    _prompt.size = Vector2(text_w, 40.0)
    _right_rule.position = Vector2(rule_w + gap + text_w + gap, 19.0)
    _right_rule.size = Vector2(rule_w, 3.0)
    _start_region.size = Vector2(rule_w * 2 + gap * 2 + text_w, 40.0)
    _anchor.place_at(Vector2(-30.0, 34.0))

func _entry_animation() -> void:
    _title_group.modulate.a = 0.0
    _title_group.position.y += ENTRY_SETTLE_PX
    var tween := create_tween().set_parallel()
    tween.tween_property(_title_group, "modulate:a", 1.0, 22.0 / 60.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(_title_group, "position:y", _title_group.position.y - ENTRY_SETTLE_PX, 22.0 / 60.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _left_rule.modulate.a = 0.0
    _right_rule.modulate.a = 0.0
    # Prompt opacity has one owner: _update_prompt_alpha(). The rules may use
    # their own entry tween because they have no idle pulse writer.
    var rules_tween := create_tween().set_parallel()
    rules_tween.tween_property(_left_rule, "modulate:a", 0.55, 10.0 / 60.0).set_delay(10.0 / 60.0)
    rules_tween.tween_property(_right_rule, "modulate:a", 0.55, 10.0 / 60.0).set_delay(10.0 / 60.0)

func _process(delta: float) -> void:
    var vp := get_viewport_rect().size
    if _entry_guard_remaining > 0.0:
        _entry_guard_remaining = maxf(_entry_guard_remaining - delta, 0.0)
    if not _armed:
        _update_start_arming()
    if not _frozen:
        _t += delta
        _drift = Vector2(
            3.00 * sin(TAU * _t / 31.0) + 0.75 * sin(TAU * _t / 53.0 + 1.1),
            1.35 * sin(TAU * _t / 37.0 + 0.7) + 0.35 * sin(TAU * _t / 61.0 + 2.0))
    # Constant overscan: the background control is grown past the viewport on
    # every side, so the bounded drift can never expose an edge. Its scale is
    # constant — no per-frame rescaling, no shimmer.
    _bg.position = Vector2(-OVERSCAN, -OVERSCAN) + _drift
    _bg.size = vp + Vector2(OVERSCAN, OVERSCAN) * 2.0
    if _leaving:
        _prompt_press_remaining = maxf(_prompt_press_remaining - delta, 0.0)
    else:
        _prompt_entry_elapsed += delta
    _update_prompt_alpha()

func _update_start_arming() -> void:
    # The short entry guard protects the Title from the previous route's event,
    # but it is not the arming decision. Once the guard is over, a held input
    # blocks until the engine reports its actual release.
    if _entry_guard_remaining > 0.0:
        return
    if not _arming_checked:
        _arming_checked = true
        _blocked_by_held_input = _relevant_input_held()
        if not _blocked_by_held_input:
            _armed = true
    elif _blocked_by_held_input and not _relevant_input_held():
        _armed = true

func _relevant_input_held() -> bool:
    # Input.is_anything_pressed() covers keyboard and controller buttons; the
    # explicit mouse query keeps the accepted left-click path deterministic on
    # render backends that do not include mouse buttons in that aggregate.
    return Input.is_anything_pressed() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _update_prompt_alpha() -> void:
    # This is the sole writer of the prompt's opacity. Entry reveal owns the
    # base alpha first; only after it completes does the idle pulse participate.
    if _leaving:
        _prompt.modulate.a = clampf(_prompt_press_remaining / PROMPT_PRESS_SECONDS, 0.0, 1.0)
        return
    if _prompt_entry_elapsed < PROMPT_ENTRY_DELAY:
        _prompt.modulate.a = 0.0
        return
    var reveal := clampf((_prompt_entry_elapsed - PROMPT_ENTRY_DELAY) / PROMPT_ENTRY_FADE, 0.0, 1.0)
    if reveal < 1.0:
        _prompt.modulate.a = PROMPT_MIN * reveal
        return
    var wave := 0.5 + 0.5 * sin(TAU * _t / PROMPT_PERIOD)
    _prompt.modulate.a = PROMPT_MIN + (PROMPT_MAX - PROMPT_MIN) * wave

# --- input ---------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
    if not _armed or _leaving:
        return
    if _is_fresh_start(event):
        get_viewport().set_input_as_handled()
        begin()

func _is_fresh_start(event: InputEvent) -> bool:
    if event is InputEventKey:
        var key := event as InputEventKey
        if not key.pressed or key.echo or key.keycode == KEY_NONE:
            return false
        # The copy promises ANY KEY, but a modifier by itself is not a Start.
        return key.keycode not in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META] \
            and key.physical_keycode not in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
    if event is InputEventMouseButton:
        return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
    if event is InputEventJoypadButton:
        var button := event as InputEventJoypadButton
        return button.pressed and (button.button_index == JOY_BUTTON_A or button.button_index == JOY_BUTTON_START)
    return false

func begin() -> void:
    # Single semantic activation: latch, fire once, ignore repeats.
    if _leaving:
        return
    _leaving = true
    _starts += 1
    _frozen = true                       # hold the current background offset
    FrontendEvents.emit_confirm("title_start")
    start_accepted.emit()
    # Prompt: tiny immediate press response, then fade.
    _prompt_press_remaining = PROMPT_PRESS_SECONDS
    var press := create_tween()
    press.parallel().tween_property(_start_region, "scale", Vector2(0.98, 0.96), 0.10)
    # Title group exits as one unit over ~12-18 frames.
    var exit := create_tween().set_parallel()
    exit.tween_property(_title_group, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    exit.tween_property(_title_group, "position:x", _title_group.position.x - 8.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    _go_to_menu()

func _go_to_menu() -> void:
    await get_tree().create_timer(EXIT_SECONDS).timeout
    # Persistent transition layer: hold the shelf frame and let Main release it
    # (crossfade, never a black cut).
    await Frontend.hold_frame()
    get_tree().change_scene_to_file(MENU_SCENE)

# --- test surface --------------------------------------------------------
func is_armed() -> bool:
    return _armed

func current_drift() -> Vector2:
    return _drift

func background_scale() -> Vector2:
    # Always constant: the background is never rescaled (Doc 02 §7).
    return Vector2.ONE

func prompt_alpha() -> float:
    return _prompt.modulate.a

func start_count() -> int:
    return _starts

func cursor_anchor() -> Control:
    return _anchor

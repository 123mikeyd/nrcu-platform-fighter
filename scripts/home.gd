extends Control
# NRCU Main Menu — Doc 03 "Selection Rail" (design locked, 1280x720 reference).
#
# The composition is AUTHORED: scenes/home.tscn holds the abstract dark field,
# the small header and four MenuRow components (scenes/components/MenuRow.tscn:
# HitArea / ActivePlate / Label / QuietRail / ActiveRail / CursorAnchor).
# This script owns only what Doc 03 §23 assigns it — destination data, the
# selected index, navigation, semantic confirm, row-state orchestration and the
# screen transition event. It never builds the fixed visual tree, never scales
# the page in, never pulses anything during idle and never moves the physical
# mouse.
#
# Selection is immediate and interruptible: every accepted change retargets
# that row's tweens (outgoing plate/rail retract over ~10 frames, incoming rail
# draws over ~12, label settles over ~9) with overlap and no input gating, so
# rapid navigation can never queue animations or block the player.
#
# Navigation: the authored CursorAnchors decide where the focus hand settles;
# mouse hover only drives selection after genuine pointer motion (the cursor
# service arms hover per screen), so a freshly entered screen never inherits
# stale hover. Quit is an in-place modal over the still-mounted Main (Doc 07
# §9-10); OS close_requested takes the same confirmation path.

const Tokens = preload("res://scripts/ui_tokens.gd")
const AppStateScript = preload("res://scripts/app_state.gd")

const MATCH_SCENE := "res://scenes/main.tscn"
# WP-0 step 3 route switch (Doc 02 §1/§10.3): the player-facing VS route enters
# the MatchFlow host — CSS/SSS live outside gameplay now, and the arena is only
# constructed by the router's LAUNCH handshake.
const MATCH_FLOW_SCENE := "res://scenes/match_flow.tscn"

# Destination data (Doc 03 §2) in authored visual order.
const DESTINATIONS: Array = [
    {"id": "play", "label": "PLAY", "event": "main_play"},
    {"id": "story", "label": "STORY MODE", "event": "main_story"},
    {"id": "help", "label": "HOW TO PLAY", "event": "main_help"},
    {"id": "quit", "label": "QUIT", "event": "main_quit"},
]
const ROW_NODES: Array = ["MenuRow_Play", "MenuRow_Story", "MenuRow_Help", "MenuRow_Quit"]

# The rail's authored length (832 px: x 112 -> 944 at 1280x720) is read from
# the MenuRow component; home.gd never decides composition geometry.
const RAIL_LEAD := 72.0          # exit-transition lead extension (reach 1016)
const QUIET_ALPHA := 0.55
const LABEL_SHIFT := 9.0
const ACTIVE_SIZE := 36
const INACTIVE_SIZE := 26

# Motion grammar in frames @60 (Doc 03 §13 / §14).
const OUT_FRAMES := 10
const RAIL_FRAMES := 12
const PLATE_FRAMES := 10
const LABEL_FRAMES := 9
const ENTRY_FRAMES := 10
const ENTRY_STAGGER := 3
const OVERLAY_FRAMES := 8
const EXIT_FRAMES := 10
const FADE_FRAMES := 12

# Lightweight selection memory: returning from a subpage (How to Play, the
# Quit confirmation, a match) restores the destination that was selected.
static var _last_selected := 0

var state := "home"
var buttons: Dictionary = {}

var _rows: Array = []
var _selected := 0
var _modal_open := false
var _exiting := false
var _help_page: Control = null
var _row_tweens: Dictionary = {}

@onready var _header: Control = $ReferenceFrame/Header
@onready var _nav: Control = $ReferenceFrame/Navigation
@onready var _page_layer: Control = $ReferenceFrame/PageLayer
@onready var _overlay: Control = $ReferenceFrame/QuitOverlay
@onready var _plate: Panel = $ReferenceFrame/QuitOverlay/Plate
@onready var _action_stay: Button = $ReferenceFrame/QuitOverlay/Plate/ActionStay
@onready var _action_quit: Button = $ReferenceFrame/QuitOverlay/Plate/ActionQuit
@onready var _stay_rail: Panel = $ReferenceFrame/QuitOverlay/Plate/StayRail
@onready var _quit_rail: Panel = $ReferenceFrame/QuitOverlay/Plate/QuitRail
@onready var _anchor_stay: Control = $ReferenceFrame/QuitOverlay/Plate/AnchorStay

func _ready() -> void:
    get_window().title = "NRCU — Friend Demo"
    theme = Tokens.make_theme()
    get_tree().auto_accept_quit = false
    get_window().close_requested.connect(_open_quit_modal)
    _collect_rows()
    _style_nodes()
    _wire_modal()
    show_page("home")
    var hand = _hand()
    if hand != null:
        hand.begin_screen("main")
        if not hand.hover_changed.is_connected(_on_hover_changed):
            hand.hover_changed.connect(_on_hover_changed)
        if hand.mode == 1:
            hand.set_focus_target(_rows[_selected]["anchor"])
        if not hand.modality_changed.is_connected(_on_modality_changed):
            hand.modality_changed.connect(_on_modality_changed)
    _entry()
    # Title -> Main continuity: the held Title frame fades out over the fresh
    # composition on the persistent Frontend layer, never a cut to black.
    Frontend.release(0.28)

# --- fixed composition (authored in home.tscn; colors resolved from tokens) --
func _collect_rows() -> void:
    _rows.clear()
    buttons.clear()
    for i in ROW_NODES.size():
        var row: Control = _nav.get_node(str(ROW_NODES[i]))
        var entry := {
            "root": row,
            "hit": row.get_node("HitArea"),
            "plate": row.get_node("ActivePlate"),
            "label": row.get_node("Label"),
            "quiet": row.get_node("QuietRail"),
            "rail": row.get_node("ActiveRail"),
            "anchor": row.get_node("CursorAnchor"),
            "label_x": row.get_node("Label").position.x,
            "rail_w": (row.get_node("ActiveRail") as Panel).size.x,
        }
        (entry["label"] as Label).text = str(DESTINATIONS[i]["label"])
        var hit: Button = entry["hit"]
        hit.pressed.connect(_confirm_index.bind(i))
        hit.focus_entered.connect(_on_row_focus.bind(i))
        var next_hit: Button = _nav.get_node(str(ROW_NODES[(i + 1) % ROW_NODES.size()])).get_node("HitArea")
        var prev_hit: Button = _nav.get_node(str(ROW_NODES[(i - 1 + ROW_NODES.size()) % ROW_NODES.size()])).get_node("HitArea")
        hit.focus_neighbor_bottom = hit.get_path_to(next_hit)
        hit.focus_neighbor_top = hit.get_path_to(prev_hit)
        _rows.append(entry)
        buttons[str(DESTINATIONS[i]["id"])] = hit

func _style_nodes() -> void:
    # Abstract dark field: BASE + one broad, low-contrast tonal asymmetry.
    $FullBleed.color = Tokens.BASE
    $ReferenceFrame/Field.color = Tokens.BASE
    $ReferenceFrame/ToneBand.color = Color(Tokens.BG_DEEP, 0.5)
    $ReferenceFrame/Header/NRCU.add_theme_color_override("font_color", Tokens.CREAM)
    $ReferenceFrame/Header/HeaderRule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
    $ReferenceFrame/Header/MainMenuLabel.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    for entry in _rows:
        var hit: Button = entry["hit"]
        # No row chrome of any kind: the plate/rail/label ARE the state, and
        # the cursor itself carries the input affordance (Doc 03 §17/§26).
        Tokens.apply_styles(hit, {
            "normal": Tokens.flat(Color(0, 0, 0, 0)),
            "hover": Tokens.flat(Color(0, 0, 0, 0)),
            "pressed": Tokens.flat(Color(0, 0, 0, 0)),
            "focus": Tokens.flat(Color(0, 0, 0, 0)),
            "disabled": Tokens.flat(Color(0, 0, 0, 0)),
        })
        var plate: Panel = entry["plate"]
        plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_2, Color(0, 0, 0, 0), 0, Tokens.RADIUS_PLATE))
        (entry["plate"].get_node("TopRule") as Panel).add_theme_stylebox_override("panel", Tokens.flat(Color(Tokens.ACCENT, 0.28)))
        plate.modulate.a = 0.0
        var label: Label = entry["label"]
        label.add_theme_font_size_override("font_size", INACTIVE_SIZE)
        label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
        var quiet: Panel = entry["quiet"]
        quiet.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
        quiet.modulate.a = QUIET_ALPHA
        (entry["rail"] as Panel).add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FLAT))
    $ReferenceFrame/QuitOverlay/Plate/QuitTitle.add_theme_color_override("font_color", Tokens.CREAM)
    for action in [_action_stay, _action_quit]:
        Tokens.apply_styles(action, {
            "normal": Tokens.flat(Color(0, 0, 0, 0)),
            "hover": Tokens.flat(Color(0, 0, 0, 0)),
            "pressed": Tokens.flat(Color(0, 0, 0, 0)),
            "focus": Tokens.flat(Color(0, 0, 0, 0)),
        })
        action.add_theme_font_override("font", Tokens.font("medium"))
    _stay_rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _quit_rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _set_modal_focus(true)

# --- pages (compatibility surface: "home" | "help" | "quit") ---------------
func show_page(next: String) -> void:
    match next:
        "help":
            _open_help()
        "quit":
            _open_quit_modal()
        _:
            _open_home()

func _open_home() -> void:
    if _exiting:
        return
    state = "home"
    _close_modal()
    _close_help()
    _nav.visible = true
    _nav.modulate.a = 1.0
    _set_rows_focusable(true)
    _refresh_targets()
    select_row(_last_selected, true)
    if _rows.size() > 0:
        var hit: Button = _rows[_selected]["hit"]
        if hit.focus_mode != Control.FOCUS_NONE:
            hit.grab_focus()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_rows[_selected]["anchor"])

func _on_modality_changed(is_mouse: bool) -> void:
    # Mouse -> focus switch: seed the logical selection (Doc 00 §12.3) so the
    # first keyboard/controller confirm activates the selected row.
    if is_mouse or not is_visible_in_tree():
        return
    var vp := get_viewport()
    if vp != null and vp.gui_get_focus_owner() != null:
        return  # focus is already established — never stomp it
    if _rows.is_empty():
        return
    var hit: Button = _rows[_selected]["hit"]
    if hit.focus_mode != Control.FOCUS_NONE:
        hit.grab_focus()
    var hand = _hand()
    if hand != null:
        hand.set_focus_target(_rows[_selected]["anchor"])

func _open_help() -> void:
    # Doc 07 §3-8: the structured How to Play screen (BASICS/FIGHTERS manual)
    # replaces the legacy demo_style wall-of-text page.
    if _exiting:
        return
    state = "help"
    _close_modal()
    _nav.visible = false
    _set_rows_focusable(false)
    if _help_page == null or not is_instance_valid(_help_page):
        _help_page = (load("res://scenes/how_to_play.tscn") as PackedScene).instantiate()
        _help_page.name = "HowToPlay"
        _page_layer.add_child(_help_page)
        _help_page.connect("closed", func() -> void: show_page("home"))
    _refresh_targets()
    var hand = _hand()
    if hand != null and hand.mode == 1 and _help_page != null:
        var back := _help_page.find_child("HelpBack", true, false)
        if back != null:
            hand.set_focus_target(back)

func _close_help() -> void:
    if _help_page != null and is_instance_valid(_help_page):
        _help_page.queue_free()
    _help_page = null

# --- quit confirmation (in-place modal, Doc 07 §9-10) ----------------------
func _wire_modal() -> void:
    _action_stay.pressed.connect(_dismiss_modal)
    _action_quit.pressed.connect(func() -> void: get_tree().quit())
    _action_stay.focus_entered.connect(_set_modal_focus.bind(true))
    _action_quit.focus_entered.connect(_set_modal_focus.bind(false))

func _open_quit_modal() -> void:
    if _exiting or _modal_open:
        return
    if state == "help":
        show_page("home")
    _modal_open = true
    state = "quit"
    _set_rows_focusable(false)
    _set_modal_focus(true)
    _overlay.show()
    _overlay.modulate.a = 0.0
    var fade := create_tween()
    fade.tween_property(_overlay, "modulate:a", 1.0, _sec(OVERLAY_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _refresh_targets()
    _action_stay.grab_focus()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_anchor_stay)

func _dismiss_modal() -> void:
    if not _modal_open:
        return
    _close_modal()
    FrontendEvents.emit_back("main")
    state = "home"
    _set_rows_focusable(true)
    _refresh_targets()
    if _rows.size() > 0:
        _rows[_selected]["hit"].grab_focus()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_rows[_selected]["anchor"])

func _close_modal() -> void:
    if not _modal_open:
        _overlay.hide()
        return
    _modal_open = false
    var fade := create_tween()
    fade.tween_property(_overlay, "modulate:a", 0.0, _sec(OVERLAY_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    fade.tween_callback(_overlay.hide)

func _set_modal_focus(stay_focused: bool) -> void:
    _stay_rail.visible = stay_focused
    _quit_rail.visible = not stay_focused
    _action_stay.add_theme_color_override("font_color", Tokens.CREAM if stay_focused else Tokens.CREAM_DIM)
    _action_quit.add_theme_color_override("font_color", Tokens.CREAM if not stay_focused else Tokens.CREAM_DIM)

func _set_rows_focusable(enabled: bool) -> void:
    for entry in _rows:
        (entry["hit"] as Button).focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

# --- selection -------------------------------------------------------------
func selected_index() -> int:
    return _selected

func menu_rows() -> Array:
    var out: Array = []
    for entry in _rows:
        out.append(entry["root"])
    return out

func is_quit_modal_open() -> bool:
    return _modal_open

func quit_modal_rect() -> Rect2:
    return _plate.get_global_rect()

func select_row(index: int, force := false) -> void:
    if _exiting or index < 0 or index >= _rows.size():
        return
    if index == _selected and not force:
        return
    _selected = index
    _last_selected = index
    for i in _rows.size():
        _reflect_row_state(i, i == index)

func _reflect_row_state(index: int, active: bool) -> void:
    # Retarget, never queue: this row's running tweens are killed and rebuilt
    # from the current presentation values.
    _kill_row_tweens(index)
    var entry: Dictionary = _rows[index]
    var label: Label = entry["label"]
    var plate: Panel = entry["plate"]
    var rail: Panel = entry["rail"]
    var quiet: Panel = entry["quiet"]
    var base_x: float = entry["label_x"]
    var tweens: Array = []
    if active:
        label.add_theme_font_size_override("font_size", ACTIVE_SIZE)
        label.add_theme_font_override("font", Tokens.font("medium"))
        label.add_theme_color_override("font_color", Tokens.CREAM)
        tweens.append(_tween_prop(label, "position:x", base_x + LABEL_SHIFT, LABEL_FRAMES))
        quiet.hide()
        plate.show()
        tweens.append(_tween_prop(plate, "modulate:a", 1.0, PLATE_FRAMES))
        rail.show()
        tweens.append(_tween_prop(rail, "size:x", entry["rail_w"], RAIL_FRAMES))
    else:
        label.add_theme_font_size_override("font_size", INACTIVE_SIZE)
        label.add_theme_font_override("font", Tokens.font("regular"))
        label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
        tweens.append(_tween_prop(label, "position:x", base_x, LABEL_FRAMES))
        if rail.visible:
            var retract := create_tween()
            retract.tween_property(rail, "size:x", 0.0, _sec(OUT_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
            retract.tween_callback(rail.hide)
            tweens.append(retract)
        if plate.visible:
            var dim := create_tween()
            dim.tween_property(plate, "modulate:a", 0.0, _sec(OUT_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
            dim.tween_callback(plate.hide)
            tweens.append(dim)
        quiet.modulate.a = QUIET_ALPHA
        quiet.show()
    _row_tweens[index] = tweens

func _tween_prop(node: Object, property: String, value, frames: int) -> Tween:
    var tween := create_tween()
    tween.tween_property(node, property, value, _sec(frames)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    return tween

func _kill_row_tweens(index: int) -> void:
    for tween in _row_tweens.get(index, []):
        if tween != null and tween.is_valid():
            tween.kill()
    _row_tweens.erase(index)

func _on_row_focus(index: int) -> void:
    if _modal_open or state != "home" or index < 0 or index >= _rows.size():
        return
    select_row(index)
    var hand = _hand()
    # Keyboard/pad focus moves the hand to the authored anchor; a mouse click
    # that happens to focus the row must never hijack the pointer modality.
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_rows[index]["anchor"])

func _on_hover_changed(target: Control) -> void:
    if target == null:
        return
    if _modal_open:
        if target == _action_stay:
            _action_stay.grab_focus()
        elif target == _action_quit:
            _action_quit.grab_focus()
        return
    if state != "home":
        return
    for i in _rows.size():
        if _rows[i]["hit"] == target:
            select_row(i)
            return

func _confirm_index(index: int) -> void:
    if _exiting or _modal_open or state != "home" or index < 0 or index >= _rows.size():
        return
    select_row(index)
    var destination: Dictionary = DESTINATIONS[index]
    FrontendEvents.emit_confirm(str(destination["event"]))
    match str(destination["id"]):
        "play":
            _leave_to_match("vs")
        "story":
            _leave_to_match("story")
        "help":
            _open_help()
        "quit":
            _open_quit_modal()

func _refresh_targets() -> void:
    var hand = _hand()
    if hand == null:
        return
    hand.drop_targets()
    if _modal_open:
        hand.add_target(_action_stay)
        hand.add_target(_action_quit)
    elif state == "help":
        if _help_page != null and is_instance_valid(_help_page):
            var back := _help_page.find_child("HelpBack", true, false)
            if back != null:
                hand.add_target(back)
    elif _nav.visible:
        for entry in _rows:
            hand.add_target(entry["hit"])

# --- entry / exit choreography (screen-specific, no page scale-in) ---------
func _entry() -> void:
    _header.modulate.a = 0.0
    var head := create_tween()
    head.tween_property(_header, "modulate:a", 1.0, _sec(ENTRY_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    for i in _rows.size():
        for key in ["label", "quiet"]:
            if key == "quiet" and i == _selected:
                continue
            var node: Control = _rows[i][key]
            var target_alpha: float = node.modulate.a if node.modulate.a > 0.0 else (QUIET_ALPHA if key == "quiet" else 1.0)
            node.modulate.a = 0.0
            var tw := create_tween()
            tw.tween_property(node, "modulate:a", target_alpha, _sec(ENTRY_FRAMES)).set_delay(_sec(4 + ENTRY_STAGGER * i)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _leave_to_match(mode: String) -> void:
    if _exiting:
        return
    _exiting = true
    AppStateScript.enter_mode = mode
    get_tree().auto_accept_quit = true
    # Doc 03 §21: the selected warm rail leads the destination transition.
    if _rows.size() > 0:
        var rail: Panel = _rows[_selected]["rail"]
        rail.show()
        var lead := create_tween()
        lead.tween_property(rail, "size:x", minf(_rows[_selected]["rail_w"] + RAIL_LEAD, 1016.0), _sec(EXIT_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        lead.tween_callback(_fade_out_then_go.bind(mode))
    else:
        _fade_out_then_go(mode)

func _fade_out_then_go(mode: String) -> void:
    var fade := create_tween()
    fade.tween_property(self, "modulate:a", 0.0, _sec(FADE_FRAMES)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    fade.tween_callback(_go_to_match.bind(mode))

func _go_to_match(mode: String) -> void:
    await Frontend.hold_frame()
    get_tree().change_scene_to_file(_destination_scene(mode))

func _destination_scene(mode: String) -> String:
    # PLAY / STORY route decision (Doc 02 §10). VS configuration is not gameplay
    # and no longer loads the arena: it enters MatchFlow, which constructs the
    # arena only after a validated MatchLaunchConfig exists. Story Select /
    # Briefing move into MatchFlow in WP-0 step 4 and the F10 debug launcher
    # stays arena-side (Doc 02 §9), so those two still load main.tscn.
    if mode == "story" or mode == "debug":
        return MATCH_SCENE
    return MATCH_FLOW_SCENE

# --- input -----------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        get_viewport().set_input_as_handled()
        if _modal_open:
            _dismiss_modal()
        elif state == "help":
            FrontendEvents.emit_back("help")
            show_page("home")
        elif state == "home" and not _exiting:
            _open_quit_modal()
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 \
            and OS.is_debug_build() and state == "home" and not _modal_open and not _exiting:
        # Developer route: the legacy monolithic setup stays reachable.
        get_viewport().set_input_as_handled()
        _leave_to_match("debug")

# --- helpers ---------------------------------------------------------------
func _sec(frames: int) -> float:
    return FrontendClock.seconds(frames)

func _hand():
    var cursor = get_node_or_null("/root/Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand

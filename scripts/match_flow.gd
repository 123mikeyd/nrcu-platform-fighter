extends Control
# MatchFlow — the frontend host and route owner (corrective package Doc 02 §1
# boundary, §5 router verbs, §6 destination readiness, §7 screen lifecycle).
#
# WP-0 migration step 3 (Doc 02 §10.3): "Create MatchFlow scene/router and move
# the CSS/SSS production route into it." This file is that host.
#
# WHAT THIS IS
#   The single persistent frontend owner of the production setup surfaces.
#   Character Select and Stage Select are its CHILDREN, so the player-facing
#   route (Main -> CSS -> SSS -> confirm) runs entirely OUTSIDE gameplay: the
#   arena (main.tscn) is only constructed once a validated MatchLaunchConfig
#   exists (Doc 02 §1). This is the real route change of step 3 — Home's PLAY
#   enters MatchFlow instead of loading main.tscn directly.
#
#   It owns:
#     * the active frontend surface and the mount order ("one active surface");
#     * the route origin stack with the semantic verbs PUSH / POP / LAUNCH /
#       RETURN (Doc 02 §5);
#     * the transition state and the destination-readiness handshake (§6);
#     * the frontend input scope while the flow is active;
#     * the typed MatchFlowState (THE validation authority) plus the
#       screen-facing legacy selection mirror the existing screens edit.
#
# WHAT THIS IS NOT
#   Not a screen: it never builds CSS/SSS composition, never edits a screen's
#   internals and never validates a slot rule of its own. The host adapts to
#   each screen's EXISTING api (build / open_with / reopen / reset / play_exit)
#   through the §7 lifecycle hooks. It also does not own match rules or result
#   data — gameplay produces those (Doc 02 §4).
#
# LIFECYCLE MAPPING (§7 -> the shipped screen APIs)
#   prepare_fresh_entry(css)   restore presentation, then open_with(state)
#   prepare_return_entry(css)  restore presentation + reopen()  [the alpha-zero
#                              CSS return bug fix: play_exit leaves
#                              $ReferenceFrame.modulate.a at 0 and reopen()
#                              never restores it, so the host does]
#   prepare_fresh_entry(sss)   restore presentation + reset()
#   prepare_return_entry(sss)  restore presentation + reset()
#   play_entry / play_exit     the screen's own entry/exit choreography
#
# STEP SCOPE (what is deliberately left for later, per Doc 02 §10):
#   * Story Fighter Select/Briefing move in (step 4); the Story entry still
#     loads main.tscn directly.
#   * Multiplayer Results / Story Result become a PostMatch surface here in
#     step 6; today the shipped Results screen inside gameplay routes back into
#     MatchFlow for post-match configuration (main.gd _reenter_match_flow).
#   * Debug Match Setup stays gameplay-side (Doc 02 §9) and is not reachable
#     from this host yet.

signal route_changed(surface_name: String)
signal launch_requested(config)
signal launch_finished
signal presentation_ready_received

const StateScript = preload("res://scripts/match_flow_state.gd")
const LaunchConfigScript = preload("res://scripts/match_launch_config.gd")
const SelectionStateScript = preload("res://scripts/match_selection_state.gd")
const CssScene = preload("res://scenes/character_select.tscn")
const StageSelectScript = preload("res://scripts/stage_select.gd")
const StageCatalog = preload("res://scripts/catalogs/stage_catalog.gd")
const FighterCatalog = preload("res://scripts/catalogs/fighter_catalog.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const AppStateScript = preload("res://scripts/app_state.gd")

const GAMEPLAY_SCENE := "res://scenes/main.tscn"
const HOME_SCENE := "res://scenes/home.tscn"
const SELF_SCENE := "res://scenes/match_flow.tscn"

const SURFACE_CSS := "css"
const SURFACE_SSS := "sss"

# Route origins (Doc 02 §5): the surface a route was entered from.
const ORIGIN_MAIN := "main"
const ORIGIN_RESULTS := "results"
const ORIGIN_STAGE := "stage"

const INPUT_SCOPE_FRONTEND := "frontend"
const INPUT_SCOPE_GAMEPLAY := "gameplay"

# Launch handshake states (Doc 02 §6).
const LAUNCH_IDLE := "idle"
const LAUNCH_CONSTRUCTING := "constructing"
const LAUNCH_READY := "ready"
const LAUNCH_LAUNCHED := "launched"

# §6: the wait for a destination's presentation_ready is bounded so the frontend
# can never hang on a destination that fails to report. Timing out is recorded
# in handshake_report() instead of silently passing as a clean handshake.
const PRESENTATION_TIMEOUT := 2.0
# Authored LAUNCH transition: the frontend releases over the live destination.
const LAUNCH_FRAMES := 12

var flow                              # MatchFlowState — the typed authority
var selection_state = null            # the screen-facing legacy mirror
var pending_launch = null             # MatchLaunchConfig handed to gameplay

var _active_surface := ""             # the ONE active frontend surface
var _route_stack: Array = []
var _scope := INPUT_SCOPE_FRONTEND

var _css: Control = null
var _sss: Control = null
var _surfaces: Dictionary = {}
var _presented: Dictionary = {}
var _entered: Dictionary = {}
var _css_opened := false

var _transition_from := ""
var _transition_to := ""
var _return_context: Dictionary = {}
var _last_popped_origin := ""
var _last_route_error := ""

var _arena: Node = null
var _constructed_hidden := false
var _launch_state := LAUNCH_IDLE
var _readiness_received := false
var _readiness_timed_out := false
var _ready_wait := 0.0
var _frontend_exited := false
var _sss_confirmed := false
var _match_started := false

func _ready() -> void:
    _style_backdrop()
    _build_surfaces()
    var entry := _consume_entry()
    _open_vs(str(entry["origin"]))
    # The previous screen may be holding its frame (Main PLAY): reveal this host
    # underneath it — one continuous surface, never a cut to black.
    Frontend.release(0.28)

func _process(delta: float) -> void:
    if _launch_state != LAUNCH_CONSTRUCTING:
        return
    _ready_wait += delta
    if _ready_wait >= PRESENTATION_TIMEOUT and not _readiness_received:
        # Fail-open, bounded and recorded: the route continues after the
        # deadline instead of blocking the player on an unreported destination.
        _readiness_timed_out = true
        _launch_state = LAUNCH_READY
        _maybe_launch()

# ---------------------------------------------------------------------------
# Composition (the authored backdrop + the surface layer live in the scene)
# ---------------------------------------------------------------------------
func _style_backdrop() -> void:
    var backdrop := get_node_or_null("Backdrop") as Panel
    if backdrop != null:
        # Authored dark field: whatever a surface's own exit leaves behind, the
        # released frame is the composition's field — never black, never a
        # cursor-only screen (Doc 02 §6).
        backdrop.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))

func _build_surfaces() -> void:
    var layer := get_node_or_null("SurfaceLayer") as Control
    if layer == null:
        return
    _css = CssScene.instantiate()
    _css.name = "CharSelect"
    layer.add_child(_css)
    _css.build(_roster_cards())
    _css.ready_requested.connect(_on_css_ready)
    _css.back_requested.connect(_on_css_back)
    _css.exit_finished.connect(_on_surface_exit_finished.bind(SURFACE_CSS))
    _css.hide()

    _sss = StageSelectScript.new()
    _sss.name = "StageSelect"
    layer.add_child(_sss)
    _sss.build(_stage_slots())
    _sss.confirmed.connect(_on_sss_confirmed)
    _sss.exit_finished.connect(_on_surface_exit_finished.bind(SURFACE_SSS))
    _sss.hide()

    _surfaces = {SURFACE_CSS: _css, SURFACE_SSS: _sss}
    _presented = {SURFACE_CSS: false, SURFACE_SSS: false}

func _roster_cards() -> Array:
    # Roster data comes from the catalog (Doc 02 §8), never from a screen or a
    # hidden setup control.
    var cards: Array = []
    for id in FighterCatalog.ids():
        cards.append({"id": str(id), "name": FighterCatalog.display_name(str(id)).to_upper()})
    return cards

func _stage_slots() -> Array:
    # Production SSS consumes StageCatalog (Doc 02 §8: "Production SSS must not
    # read a hidden Debug Setup OptionButton").
    var slots: Array = []
    for entry in StageCatalog.entries():
        slots.append({
            "id": str(entry.get("id", "")),
            "name": str(entry.get("display_name", "")),
            "tex": str(entry.get("thumbnail", "")),
        })
    return slots

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
func _consume_entry() -> Dictionary:
    # The entry flag is consumed here (like main.gd did). Until the PostMatch
    # payload exists (step 6) the route origin rides the existing string:
    #   "vs"          fresh VS entry (Main -> PLAY)
    #   "vs:results"  Results -> Change Fighters
    #   "vs:stage"    Results -> Change Stage (PUSH the SSS with origin RESULTS)
    var raw := str(AppStateScript.enter_mode)
    AppStateScript.enter_mode = "debug"
    var parts := raw.split(":", false)
    var mode := str(parts[0]) if parts.size() > 0 else "debug"
    var origin := str(parts[1]) if parts.size() > 1 else ""
    return {"mode": mode, "origin": origin}

func open_vs(origin: String = "") -> void:
    _open_vs(origin)

func _open_vs(origin: String) -> void:
    # Fresh VS configuration: the typed state is built through the adapters from
    # the shipped selection state, so the shipped defaults (P1 Human + CPU
    # stations) and the produced MatchLaunchConfig stay identical to the old
    # path while the typed object becomes the authority.
    flow = StateScript.from_selection_state(SelectionStateScript.new())
    flow.origin = origin if origin != "" else ORIGIN_MAIN
    flow.push_return(flow.origin)
    selection_state = flow.to_selection_state()
    _route_stack = [SURFACE_CSS]
    _active_surface = SURFACE_CSS
    _entered = {}
    _entered[SURFACE_CSS] = true
    set_input_scope(INPUT_SCOPE_FRONTEND)
    prepare_fresh_entry(SURFACE_CSS)
    play_entry(SURFACE_CSS)
    if origin == ORIGIN_STAGE:
        # Results -> Change Stage (Doc 02 §5): PUSH with origin RESULTS.
        call_deferred("_push_stage_from_results")

func _push_stage_from_results() -> void:
    push_surface(SURFACE_SSS, ORIGIN_RESULTS)

# ---------------------------------------------------------------------------
# Router verbs (Doc 02 §5). Route state is updated by the verb; the screens'
# authored choreography completes the presentation transition.
# ---------------------------------------------------------------------------
func push_surface(surface_name: String, origin: String = "") -> bool:
    # PUSH: the current surface stays mounted below the incoming one.
    if _launch_state != LAUNCH_IDLE:
        return false
    if not _surfaces.has(surface_name) or surface_name == _active_surface:
        return false
    if _route_stack.has(surface_name):
        return false
    var outgoing := _active_surface
    _route_stack.append(surface_name)
    if origin != "" and flow != null:
        flow.push_return(str(origin))
    _active_surface = surface_name
    _transition_from = outgoing
    _transition_to = surface_name
    if outgoing != "" and is_surface_presented(outgoing):
        play_exit(outgoing, surface_name)
    else:
        _enter_surface(surface_name)
    return true

func pop_surface() -> String:
    # POP: leave the top surface and restore the one beneath it.
    if _launch_state != LAUNCH_IDLE:
        return ""
    if _route_stack.size() <= 1:
        return ""
    var left: String = _route_stack[_route_stack.size() - 1]
    var restored: String = _route_stack[_route_stack.size() - 2]
    _route_stack.resize(_route_stack.size() - 1)
    _last_popped_origin = _pop_origin()
    _active_surface = restored
    _return_context = {"from": left, "origin": _last_popped_origin}
    _transition_from = left
    _transition_to = restored
    if is_surface_presented(left):
        play_exit(left, restored)
    else:
        _enter_surface(restored)
    return restored

func launch_match() -> bool:
    # LAUNCH: build the immutable snapshot and hand the destination over (§6).
    if _launch_state != LAUNCH_IDLE or _active_surface != SURFACE_SSS:
        return false
    return _begin_launch(str(flow.stage_id))

func return_to_flow(origin: String = ORIGIN_RESULTS) -> void:
    # RETURN (gameplay end -> post-match configuration). Gameplay calls this
    # path; the completed arena is gone before the flow is re-entered.
    AppStateScript.enter_mode = "vs:" + str(origin)
    get_tree().change_scene_to_file(SELF_SCENE)

# --- internal transition completion ----------------------------------------
func _enter_surface(surface_name: String) -> void:
    _transition_from = ""
    _transition_to = ""
    if surface_name == "":
        return
    if _entered.has(surface_name):
        prepare_return_entry(surface_name, _return_context)
    else:
        _entered[surface_name] = true
        prepare_fresh_entry(surface_name, {})
    play_entry(surface_name)

func _on_surface_exit_finished(surface_name: String) -> void:
    _hide_surface(surface_name)
    if surface_name == SURFACE_SSS and _sss_confirmed:
        # The confirm exit belongs to the launch, not to a POP: hold here and
        # let the readiness handshake release the flow (§6).
        _frontend_exited = true
        _maybe_launch()
        return
    if _transition_to != "":
        _enter_surface(_transition_to)
        return
    if surface_name == SURFACE_SSS:
        # SSS Back with no router transition in flight: the screen played its
        # own exit, so finish the POP (Doc 02 §5: SSS Back -> CSS POP).
        pop_surface()

func _pop_origin() -> String:
    if flow == null:
        return ""
    return str(flow.pop_return())

# ---------------------------------------------------------------------------
# §7 lifecycle hooks. The host adapts to the screens; the screens are never
# rewritten. prepare_* restores the presentation baseline the screen's own exit
# choreography destroys.
# ---------------------------------------------------------------------------
func prepare_fresh_entry(surface_name: String, _context: Dictionary = {}) -> void:
    _restore_presentation(surface_name)
    if surface_name == SURFACE_SSS and _sss != null:
        _sss.reset()

func prepare_return_entry(surface_name: String, _context: Dictionary = {}) -> void:
    _restore_presentation(surface_name)
    if surface_name == SURFACE_CSS and _css != null:
        # Commits survive, transient carry does not (reopen's own contract);
        # the restored frame alpha is what fixes the alpha-zero return bug.
        _css.reopen()
    elif surface_name == SURFACE_SSS and _sss != null:
        _sss.reset()

func play_entry(surface_name: String, _context: Dictionary = {}) -> void:
    match surface_name:
        SURFACE_CSS:
            if _css == null:
                return
            _show_surface(SURFACE_CSS)
            if not _css_opened:
                _css_opened = true
                _css.open_with(selection_state)
        SURFACE_SSS:
            if _sss == null:
                return
            _show_surface(SURFACE_SSS)
            # Stage Select opens against the state's stage (the shipped
            # current/focus pair) — never a hidden setup control.
            _sss.open_with(str(flow.stage_id), str(flow.stage_id))
        _:
            return
    set_input_scope(INPUT_SCOPE_FRONTEND)
    route_changed.emit(surface_name)

func play_exit(surface_name: String, _destination: String = "") -> void:
    match surface_name:
        SURFACE_CSS:
            if _css != null:
                _css.play_exit()
        SURFACE_SSS:
            if _sss != null:
                _sss.play_exit()

func _restore_presentation(surface_name: String) -> void:
    # Doc 02 §7: root alpha = authored baseline. This is the CSS return fix.
    var screen := _surfaces.get(surface_name) as Control
    if screen != null:
        screen.modulate.a = 1.0
    var root := surface_root(surface_name)
    if root != null and root != screen:
        root.modulate.a = 1.0

func _show_surface(surface_name: String) -> void:
    var screen := _surfaces.get(surface_name) as Control
    if screen == null:
        return
    _presented[surface_name] = true
    screen.modulate.a = 1.0
    screen.show()

func _hide_surface(surface_name: String) -> void:
    _presented[surface_name] = false
    var screen := _surfaces.get(surface_name) as Control
    if screen != null:
        screen.hide()

# ---------------------------------------------------------------------------
# Screen callbacks
# ---------------------------------------------------------------------------
func _on_css_ready() -> void:
    # READY is re-validated through the ONE authority (Doc 02 §2) before the
    # route advances; an invalid setup never reaches Stage Select.
    _sync_flow_from_screen()
    var error: String = flow.validate_for_stage_select()
    _last_route_error = error
    if error != "":
        return
    push_surface(SURFACE_SSS)

func _on_css_back() -> void:
    _last_route_error = ""
    _leave_to_home()

func _on_sss_confirmed(id: String) -> void:
    _begin_launch(str(id))

func _begin_launch(stage_id: String) -> bool:
    # Stage confirm: the selection is written into the typed state AND the
    # screen mirror, then frozen into the immutable launch snapshot.
    _sync_flow_from_screen()
    flow.stage_id = str(stage_id)
    if selection_state != null:
        selection_state.set_stage(str(stage_id))
    var config = LaunchConfigScript.build(flow, str(stage_id))
    if not config.is_valid():
        _last_route_error = str(config.validation_error())
        return false
    _last_route_error = ""
    pending_launch = config
    _sss_confirmed = true
    _frontend_exited = false
    # §6: construct the destination NOW, while the SSS still owns the frame
    # (its confirm pose + exit choreography cover the construction window).
    _construct_gameplay(config)
    return true

func _sync_flow_from_screen() -> void:
    # Re-import the legacy mirror the screens edited into the typed authority.
    # The adapter is one-way for origin/return stack/story id, so the host
    # re-applies them around every re-import.
    if selection_state == null:
        return
    var origin := str(flow.origin) if flow != null else ""
    var stack: Array = flow.return_stack.duplicate() if flow != null else []
    var story_id := str(flow.story_encounter_id) if flow != null else ""
    flow = StateScript.from_selection_state(selection_state)
    flow.origin = origin
    flow.return_stack = stack
    flow.story_encounter_id = story_id

func _leave_to_home() -> void:
    set_input_scope(INPUT_SCOPE_FRONTEND)
    AppStateScript.enter_mode = "debug"
    get_tree().change_scene_to_file(HOME_SCENE)

# ---------------------------------------------------------------------------
# §6 destination readiness + LAUNCH handshake
# ---------------------------------------------------------------------------
func _construct_gameplay(config) -> void:
    _launch_state = LAUNCH_CONSTRUCTING
    _readiness_received = false
    _readiness_timed_out = false
    _ready_wait = 0.0
    _arena = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
    _arena.name = "MainArena"
    # The immutable snapshot is handed over BEFORE tree entry, so gameplay
    # constructs the configured match instead of running a screen entry route.
    _arena.launch_config = config
    if not _arena.presentation_ready.is_connected(_on_gameplay_presentation_ready):
        _arena.presentation_ready.connect(_on_gameplay_presentation_ready)
    get_tree().root.add_child(_arena)
    # Prewarmed, not presented: the destination exists and constructs while the
    # SSS remains presented (no black/cursor-only loading frame, §6).
    _constructed_hidden = true
    _present_arena(false)

func _present_arena(presented: bool) -> void:
    if _arena == null or not is_instance_valid(_arena):
        return
    _arena.visible = presented
    # Gameplay's own CanvasLayers (HUD/menu) are presentation: they join the
    # reveal with the 3D world, they never appear during construction.
    for child in _arena.get_children():
        if child is CanvasLayer:
            child.visible = presented

func _on_gameplay_presentation_ready() -> void:
    if _launch_state != LAUNCH_CONSTRUCTING:
        return
    _readiness_received = true
    _launch_state = LAUNCH_READY
    presentation_ready_received.emit()
    _maybe_launch()

func _maybe_launch() -> void:
    if not _sss_confirmed or not _frontend_exited:
        return
    if _launch_state != LAUNCH_READY:
        return
    _play_launch_transition()

func _play_launch_transition() -> void:
    if _launch_state == LAUNCH_LAUNCHED:
        return
    _launch_state = LAUNCH_LAUNCHED
    set_process(false)
    # 1. reveal the prewarmed destination behind the frontend: the outgoing
    #    frame is the live destination, never a loading screen.
    _present_arena(true)
    # 2. the match starts from the immutable snapshot (Doc 02 §3).
    _match_started = _arena.start_match_from_config(pending_launch)
    set_input_scope(INPUT_SCOPE_GAMEPLAY)
    launch_requested.emit(pending_launch)
    # 3. authored LAUNCH transition, then MatchFlow is released.
    var fade := create_tween()
    fade.tween_property(self, "modulate:a", 0.0, float(LAUNCH_FRAMES) / 60.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    fade.tween_callback(_release_flow)

func _release_flow() -> void:
    if _arena != null and is_instance_valid(_arena):
        get_tree().current_scene = _arena
    launch_finished.emit()
    queue_free()

# ---------------------------------------------------------------------------
# Input scope (Doc 02 §5: one owner knows the active surface and the scope)
# ---------------------------------------------------------------------------
func set_input_scope(scope: String) -> void:
    _scope = str(scope)

func input_scope() -> String:
    return _scope

# ---------------------------------------------------------------------------
# Reads (tests / evidence)
# ---------------------------------------------------------------------------
func active_surface() -> String:
    return _active_surface

func char_select() -> Control:
    return _css

func stage_select() -> Control:
    return _sss

func route_stack_names() -> Array:
    return _route_stack.duplicate()

func origin_stack_names() -> Array:
    return flow.return_stack.duplicate() if flow != null else []

func route_origin() -> String:
    return flow.return_target() if flow != null else ""

func last_popped_origin() -> String:
    return _last_popped_origin

func last_route_error() -> String:
    return _last_route_error

func is_surface_presented(surface_name: String) -> bool:
    return bool(_presented.get(surface_name, false))

func presented_surfaces() -> Array:
    var out: Array = []
    for name in _presented.keys():
        if bool(_presented[name]):
            out.append(str(name))
    out.sort()
    return out

func surface_root(surface_name: String) -> Control:
    # The authored node each surface's entry/exit choreography drives.
    var screen := _surfaces.get(surface_name) as Control
    if screen == null:
        return null
    if surface_name == SURFACE_CSS:
        return screen.get_node_or_null("ReferenceFrame") as Control
    if surface_name == SURFACE_SSS:
        return screen.get_node_or_null("StageContent") as Control
    return screen

func surface_root_alpha(surface_name: String) -> float:
    var screen := _surfaces.get(surface_name) as Control
    var root := surface_root(surface_name)
    if screen == null or root == null:
        return 0.0
    if root == screen:
        return screen.modulate.a
    return minf(screen.modulate.a, root.modulate.a)

func launch_state() -> String:
    return _launch_state

func pending_launch_config():
    return pending_launch

func gameplay_node() -> Node:
    return _arena

func handshake_report() -> Dictionary:
    # What the §6 handshake actually did this launch (evidence, not a claim).
    return {
        "gameplay_constructed": _arena != null and is_instance_valid(_arena),
        "constructed_hidden_while_frontend_up": _constructed_hidden,
        "presentation_ready_received": _readiness_received,
        "presentation_timed_out": _readiness_timed_out,
        "ready_wait_seconds": _ready_wait,
        "frontend_released_after_ready": _launch_state == LAUNCH_LAUNCHED and (_readiness_received or _readiness_timed_out),
        "match_started_from_config": _match_started,
    }

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
#   * WP-0 step 5 moved the multiplayer Results into the PostMatch surface this
#     host owns: gameplay produces the immutable MatchResult at match
#     resolution and RETURNs here with the typed payload (AppState.post_match);
#     the host presents the PostMatch surface over it and implements the route
#     actions (REMATCH -> LAUNCH from the preserved MatchLaunchConfig, CHANGE
#     FIGHTERS / CHANGE STAGE -> PUSH with origin RESULTS, MAIN MENU -> clear
#     the stack to Main). The Story outcome rides the same typed channel; its
#     presentation stays the shipped Story surface state (the standalone Story
#     Result redesign is WP-5).
#   * Story Fighter Select (the two-step split of Doc 01 §9) is WP-4: today the
#     host presents the shipped Encounter Briefing (roster strip included).
#   * Multiplayer Results VISUALS / resolution semantics (elimination batches,
#     ties, team ranking, hero framing) are WP-5; this host presents the shipped
#     result_screen unchanged.
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
const EncounterCatalog = preload("res://scripts/catalogs/story_encounter_catalog.gd")
const StoryBriefingScene = preload("res://scenes/story_briefing.tscn")
const PostMatchScript = preload("res://scripts/frontend/post_match.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const AppStateScript = preload("res://scripts/app_state.gd")

const GAMEPLAY_SCENE := "res://scenes/main.tscn"
const HOME_SCENE := "res://scenes/home.tscn"
const SELF_SCENE := "res://scenes/match_flow.tscn"

const SURFACE_CSS := "css"
const SURFACE_SSS := "sss"
const SURFACE_STORY := "story"
const SURFACE_POSTMATCH := "postmatch"

# Entry modes (AppState.enter_mode, the pre-PostMatch route channel). PLAIN
# modes only: the post-match route rides the typed payload below, never an
# origin suffix like "vs:results" (retired in WP-0 step 5).
const MODE_VS := "vs"
const MODE_STORY := "story"
const MODE_DEBUG := "debug"

# Route origins (Doc 02 §5): the surface a route was entered from. "results" is
# PostMatch's own origin label — CHANGE FIGHTERS / CHANGE STAGE PUSH with it and
# an SSS opened from Results POPs back to Results.
const ORIGIN_MAIN := "main"
const ORIGIN_RESULTS := "results"

const STORY_RESULT_WON := "won"
const STORY_RESULT_LOST := "lost"
# The shipped Story ready-screen default (main.gd _build_story_panel selected
# turbofit); an invalid model resolves to it, exactly as start_story() did.
const STORY_DEFAULT_FIGHTER := "turbofit"

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

var _mode := MODE_VS                  # the entry mode being hosted
var _active_surface := ""             # the ONE active frontend surface
var _route_stack: Array = []
var _scope := INPUT_SCOPE_FRONTEND

var _css: Control = null
var _sss: Control = null
var _briefing: Control = null         # Story Encounter Briefing (the Story surface)
var _post_match: Control = null       # PostMatch: the multiplayer Results surface
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
var _launch_confirmed := false
var _match_started := false

# PostMatch state (WP-0 step 5): the typed payload gameplay handed over, the
# immutable result it carries and the preserved launch snapshot REMATCH works
# from. Never a live fighter read (Doc 02 §4).
var _post_match_payload: Dictionary = {}
var _post_match_result = null
var _post_match_config = null
var _post_match_presented := false

func _ready() -> void:
    _style_backdrop()
    _build_surfaces()
    var payload: Dictionary = AppStateScript.take_post_match()
    if not payload.is_empty():
        # RETURN from gameplay (Doc 02 §5): the completed match handed over its
        # typed end-state payload; the frontend owns PostMatch.
        _open_post_match(payload)
    else:
        var mode := _consume_entry()
        if mode == MODE_STORY:
            _open_story("")
        else:
            _open_vs("")
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

    # Story (Doc 01 §9, Doc 07 §11-16): the Encounter Briefing is the Story
    # surface of this host. It is mounted here and inert until the Story route
    # opens it; the briefing's own visuals are unchanged (WP-4 owns the redesign).
    _briefing = StoryBriefingScene.instantiate()
    _briefing.name = "StoryBriefing"
    layer.add_child(_briefing)
    _briefing.build(_story_playable_fighters())
    _briefing.action_button().pressed.connect(_on_story_start)
    _briefing.back_button().pressed.connect(_on_story_back)
    _briefing.chosen.connect(_on_story_chosen)
    _briefing.exit_finished.connect(_on_story_exit_finished)
    _briefing.hide()

    # PostMatch (Doc 02 §1 POST-MATCH, §10.6): the multiplayer Results surface.
    # It presents the SHIPPED result_screen over the immutable MatchResult
    # payload gameplay hands over; the router owns the four route actions.
    _post_match = PostMatchScript.new()
    _post_match.name = "PostMatch"
    layer.add_child(_post_match)
    _post_match.rematch_requested.connect(_on_post_match_rematch)
    _post_match.change_fighters_requested.connect(_on_post_match_change_fighters)
    _post_match.change_stage_requested.connect(_on_post_match_change_stage)
    _post_match.menu_requested.connect(_on_post_match_menu)
    _post_match.exit_finished.connect(_on_surface_exit_finished.bind(SURFACE_POSTMATCH))
    _post_match.hide()

    _surfaces = {SURFACE_CSS: _css, SURFACE_SSS: _sss, SURFACE_STORY: _briefing, SURFACE_POSTMATCH: _post_match}
    _presented = {SURFACE_CSS: false, SURFACE_SSS: false, SURFACE_STORY: false, SURFACE_POSTMATCH: false}

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

# --- Story content (Doc 02 §8 StoryEncounterCatalog) ------------------------
func _current_encounter_id() -> String:
    # One encounter today; the catalog owns the list, so a second entry only
    # needs to appear there to be launchable later.
    var ids: Array = EncounterCatalog.ids()
    return str(ids[0]) if not ids.is_empty() else ""

func _story_playable_fighters() -> Array[String]:
    # The encounter's allowed fighters (the roster minus the prototype Ice
    # Mage) come from StoryEncounterCatalog, never from a screen or a hidden
    # OptionButton (Doc 10: the hidden production StoryCharacterSelect is
    # superseded by MatchFlowState + the catalogs).
    var out: Array[String] = []
    for id in EncounterCatalog.allowed_fighter_ids(_current_encounter_id()):
        if not out.has(id):
            out.append(id)
    return out

func _allowed_story_fighter(id: String) -> String:
    return id if id != "" and (id in _story_playable_fighters()) else ""

func _coerce_story_fighter() -> String:
    # The shipped fallback (main.gd start_story): an unknown or disallowed
    # Story selection resolves to the encounter default, and the STATE is
    # repaired, not just the launch, so an invalid model can never launch.
    var allowed := _story_playable_fighters()
    var chosen := story_selection_id()
    if _allowed_story_fighter(chosen) == "":
        chosen = STORY_DEFAULT_FIGHTER if allowed.has(STORY_DEFAULT_FIGHTER) else (str(allowed[0]) if not allowed.is_empty() else "")
    if flow != null and not flow.slots.is_empty():
        flow.slots[0].fighter_id = chosen
    AppStateScript.story_fighter_id = chosen
    return chosen

func story_stage_id() -> String:
    # The encounter's stage comes from the catalog (Doc 02 §8). The shipped
    # launch left the level to the Debug Setup default ("debug"), which is
    # exactly what the catalog records as the encounter's effective stage.
    var encounter: Dictionary = EncounterCatalog.by_id(_current_encounter_id())
    var id := str(encounter.get("stage_id", ""))
    if id != "" and StageCatalog.is_selectable(id):
        return id
    var selectable: Array = StageCatalog.selectable_ids()
    return str(selectable[0]) if not selectable.is_empty() else ""

func _apply_encounter_slots() -> void:
    # The encounter's slot metadata (Doc 02 §8). MatchFlowState.fresh_story()
    # already carries the enemy station; the player station's TEAM ID is applied
    # here because gameplay's shipped slot validator (match_config.validate)
    # rejects an active slot without team A/B while the typed state leaves an
    # FFA human at NO_TEAM. The catalog records the shipped layout
    # (player_slot team 0, enemy_slot team 1), so this is not a new decision.
    var encounter: Dictionary = EncounterCatalog.by_id(_current_encounter_id())
    if encounter.is_empty() or flow == null:
        return
    var player: Dictionary = encounter.get("player_slot", {})
    if not flow.slots.is_empty() and player.has("team"):
        flow.slots[0].team_id = int(player.get("team", StateScript.NO_TEAM))
    var enemy: Dictionary = encounter.get("enemy_slot", {})
    if flow.slots.size() > 1 and enemy.has("team"):
        flow.slots[1].team_id = int(enemy.get("team", StateScript.NO_TEAM))

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
func _consume_entry() -> String:
    # The entry flag is consumed here (like main.gd did) and resolved to a PLAIN
    # entry mode. Origin/result suffixes ("vs:results", "vs:stage",
    # "story:result:won") are RETIRED (WP-0 step 5): the post-match route is the
    # typed payload consumed in _ready(), and route origins are the router's own
    # typed stack (Doc 02 §5).
    var raw := str(AppStateScript.enter_mode)
    AppStateScript.enter_mode = "debug"
    if raw == MODE_STORY:
        return MODE_STORY
    if raw == MODE_VS:
        return MODE_VS
    return MODE_DEBUG

func open_vs(origin: String = "") -> void:
    _open_vs(origin)

func _open_vs(origin: String) -> void:
    # Fresh VS configuration: the typed state is built through the adapters from
    # the shipped selection state, so the shipped defaults (P1 Human + CPU
    # stations) and the produced MatchLaunchConfig stay identical to the old
    # path while the typed object becomes the authority.
    _mode = MODE_VS
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

func open_story(result: String = "") -> void:
    _open_story(result)

func _open_story(result: String = "") -> void:
    # Story route (Doc 01 §9): Main -> Story Fighter Select/Briefing ->
    # gameplay. The host owns the surface; the encounter metadata and the
    # playable roster come from StoryEncounterCatalog (Doc 02 §8) and the
    # selected fighter survives the route through AppState (the cross-scene
    # channel) — that is what keeps the choice when Back returns to Main and
    # when gameplay returns for the Story Result.
    _enter_story_surface(str(AppStateScript.story_fighter_id), _current_encounter_id())
    if result == STORY_RESULT_WON or result == STORY_RESULT_LOST:
        _show_story_result(result == STORY_RESULT_WON)

func _enter_story_surface(fighter_id: String, encounter_id: String) -> void:
    # Shared by the fresh Story entry and by the post-match Story outcome, so
    # the Story surface is mounted exactly one way.
    _mode = MODE_STORY
    var fighter := _allowed_story_fighter(str(fighter_id))
    if fighter == "":
        fighter = STORY_DEFAULT_FIGHTER
    flow = StateScript.fresh_story(str(encounter_id) if encounter_id != "" else _current_encounter_id(), fighter)
    AppStateScript.story_fighter_id = str(flow.slots[0].fighter_id)
    _apply_encounter_slots()
    flow.origin = ORIGIN_MAIN
    flow.push_return(flow.origin)
    # The Story route has no legacy VS screen mirror to keep in sync.
    selection_state = null
    _route_stack = [SURFACE_STORY]
    _active_surface = SURFACE_STORY
    _entered = {}
    _entered[SURFACE_STORY] = true
    set_input_scope(INPUT_SCOPE_FRONTEND)
    prepare_fresh_entry(SURFACE_STORY)
    play_entry(SURFACE_STORY)

# ---------------------------------------------------------------------------
# RETURN -> PostMatch (Doc 02 §5, §10.6). Gameplay hands the typed end-state
# payload over (AppState.post_match) and changes scene; the frontend owns the
# presentation and the route actions. No live fighter is ever read here: the
# payload is the authority (Doc 02 §4, Doc 06 §4).
# ---------------------------------------------------------------------------
func _open_post_match(payload: Dictionary) -> void:
    if str(payload.get("kind", "")) == AppStateScript.POST_MATCH_STORY:
        _open_story_outcome(payload)
        return
    _open_vs_outcome(payload)

func _open_vs_outcome(payload: Dictionary) -> void:
    # Multiplayer Results: PostMatch presents the shipped result_screen over the
    # immutable MatchResult snapshot.
    _mode = MODE_VS
    _post_match_payload = payload
    _post_match_result = payload.get("result", null)
    _post_match_config = payload.get("config", null)
    flow = _flow_from_post_match(payload)
    # The route was entered from post-match, so PostMatch is the origin the
    # next PUSH (CHANGE FIGHTERS / CHANGE STAGE) records (Doc 02 §5).
    flow.origin = ORIGIN_RESULTS
    flow.push_return(ORIGIN_RESULTS)
    selection_state = flow.to_selection_state()
    _route_stack = [SURFACE_POSTMATCH]
    _active_surface = SURFACE_POSTMATCH
    _entered = {}
    _entered[SURFACE_POSTMATCH] = true
    set_input_scope(INPUT_SCOPE_FRONTEND)
    prepare_fresh_entry(SURFACE_POSTMATCH)
    play_entry(SURFACE_POSTMATCH)

func _open_story_outcome(payload: Dictionary) -> void:
    # Story Result ownership move (Doc 02 §1): the typed StoryOutcome decides the
    # state; the SHIPPED Story result presentation stays on the Story surface
    # (the standalone Story Result redesign is WP-5).
    var config = payload.get("config", null)
    var encounter_id := str(payload.get("encounter_id", ""))
    var fighter := str(payload.get("fighter_id", ""))
    if config != null and config.is_valid():
        if encounter_id == "":
            encounter_id = str(config.story_encounter_id())
        if fighter == "" and config.slot_count() > 0:
            fighter = str(config.slot(0).get("fighter_id", ""))
        _post_match_config = config
    _post_match_payload = payload
    if fighter == "":
        fighter = str(AppStateScript.story_fighter_id)
    _enter_story_surface(fighter, encounter_id)
    _show_story_result(bool(payload.get("won", false)))

func _flow_from_post_match(payload: Dictionary):
    # Restore the setup state behind PostMatch (Doc 01 §2: returning from
    # Results restores MatchFlowState instead of reapplying defaults): the
    # preserved launch snapshot when the match came from this router, else the
    # resolution context the arena handed over (direct/debug arena start).
    var config = payload.get("config", null)
    if config != null and config.is_valid():
        return _flow_from_config(config)
    var state = SelectionStateScript.new()
    state.mode = int(payload.get("mode", 0))
    var stage := str(payload.get("stage", ""))
    if stage != "":
        state.stage = stage
    var slots = payload.get("slots", [])
    if slots is Array and not (slots as Array).is_empty():
        state.slots = (slots as Array).duplicate(true)
    return StateScript.from_selection_state(state)

func _flow_from_config(config):
    # The immutable launch snapshot holds everything the setup state needs; the
    # legacy vocabulary is produced through the SAME adapter statics the state
    # exposes, so no rule is duplicated here.
    var state = SelectionStateScript.new()
    state.mode = int(config.mode())
    state.stage = str(config.stage_id())
    var slots: Array = []
    for i in config.slot_count():
        var entry: Dictionary = config.slot(i)
        slots.append({
            "kind": StateScript.kind_to_legacy(int(entry.get("kind", StateScript.Kind.EMPTY))),
            "character": str(entry.get("fighter_id", "")),
            "team": int(entry.get("team_id", StateScript.NO_TEAM)),
            "difficulty": str(entry.get("difficulty", StateScript.DEFAULT_DIFFICULTY)),
            "device": StateScript.input_source_to_legacy_device(entry.get("input_source", {})),
        })
    state.slots = slots
    var restored = StateScript.from_selection_state(state)
    for i in mini(config.slot_count(), restored.slots.size()):
        # The resolved presentation variant is part of the snapshot (Doc 02 §4);
        # the legacy adapter cannot carry it, so it is re-applied here.
        restored.slots[i].palette_index = int(config.slot(i).get("palette_index", i))
    return restored

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

func rematch() -> bool:
    # LAUNCH from PostMatch (Doc 02 §5 REMATCH / Doc 06 §8): relaunch with the
    # PRESERVED MatchLaunchConfig — same fighters, palettes, teams, devices and
    # stage — never re-seeded defaults.
    if _launch_state != LAUNCH_IDLE or _active_surface != SURFACE_POSTMATCH:
        return false
    var config = rematch_config()
    if config == null:
        return false
    if not _begin_launch_with_config(config):
        return false
    if _post_match != null:
        # The shipped Results leaves immediately; its exit completes the launch
        # handshake (§6 hold).
        _post_match.play_exit()
    return true

func rematch_config():
    # The preserved launch snapshot when the match came from this router; a
    # direct/debug arena start has none, so the router REBUILDS one from the
    # handed-over resolution snapshot (mode/slots/stage) through the same
    # validation authority instead of falling back to fresh VS defaults.
    if _post_match_config != null and _post_match_config.is_valid():
        return _post_match_config
    if flow == null or _post_match_payload.is_empty() or str(_post_match_payload.get("kind", "")) != AppStateScript.POST_MATCH_VS:
        return null
    var rebuilt = LaunchConfigScript.build(flow, str(flow.stage_id))
    if not rebuilt.is_valid():
        _last_route_error = str(rebuilt.validation_error())
        return null
    _last_route_error = ""
    _post_match_config = rebuilt
    return rebuilt

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
    if _launch_confirmed:
        # The exit belongs to a LAUNCH, not to a POP: SSS confirm, Story START
        # and Results REMATCH all hold here and let the readiness handshake
        # release the flow (§6).
        _frontend_exited = true
        _maybe_launch()
        return
    if _transition_to != "":
        _enter_surface(_transition_to)
        return
    if surface_name == SURFACE_SSS:
        # SSS Back with no router transition in flight: the screen played its
        # own exit, so finish the POP (Doc 02 §5: SSS Back -> CSS POP, or back
        # to Results when the SSS was PUSHed from PostMatch).
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
    elif surface_name == SURFACE_STORY and _briefing != null:
        _briefing.reset()
    elif surface_name == SURFACE_POSTMATCH and _post_match != null:
        _post_match.prepare_fresh()

func prepare_return_entry(surface_name: String, _context: Dictionary = {}) -> void:
    _restore_presentation(surface_name)
    if surface_name == SURFACE_CSS and _css != null:
        # Commits survive, transient carry does not (reopen's own contract);
        # the restored frame alpha is what fixes the alpha-zero return bug.
        _css.reopen()
    elif surface_name == SURFACE_SSS and _sss != null:
        _sss.reset()
    elif surface_name == SURFACE_STORY and _briefing != null:
        _briefing.reset()
    elif surface_name == SURFACE_POSTMATCH and _post_match != null:
        # POP back from the SSS opened from Results: the revealed Results screen
        # is restored as it was (never re-revealed).
        _post_match.prepare_return()

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
        SURFACE_STORY:
            if _briefing == null:
                return
            _show_surface(SURFACE_STORY)
            # The briefing opens against the stored Story selection (the
            # encounter's player-facing copy comes from its own scene).
            _briefing.open(story_selection_id())
        SURFACE_POSTMATCH:
            if _post_match == null:
                return
            _show_surface(SURFACE_POSTMATCH)
            # Fresh entry: present the SHIPPED result_screen over the immutable
            # payload gameplay handed over. A return entry (POP back from SSS)
            # only restores the surface — the reveal is never replayed.
            if not _post_match_presented:
                _post_match_presented = true
                _post_match.present(_post_match_result, _post_match_result != null)
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
        SURFACE_STORY:
            if _briefing != null:
                _briefing.play_exit()
        SURFACE_POSTMATCH:
            if _post_match != null:
                _post_match.play_exit()

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

# --- PostMatch route actions (Doc 02 §5, Doc 06 §8) --------------------------
func _on_post_match_rematch() -> void:
    _last_route_error = ""
    rematch()

func _on_post_match_change_fighters() -> void:
    # CHANGE FIGHTERS -> PUSH the CSS with origin RESULTS. The PUSH keeps
    # PostMatch mounted beneath, so a CSS Back / ui_cancel route can restore it.
    _last_route_error = ""
    push_surface(SURFACE_CSS, ORIGIN_RESULTS)

func _on_post_match_change_stage() -> void:
    # CHANGE STAGE -> PUSH the SSS with origin RESULTS; its Back POPs back to
    # Results and a confirm LAUNCHes the new stage with the same roster.
    _last_route_error = ""
    push_surface(SURFACE_SSS, ORIGIN_RESULTS)

func _on_post_match_menu() -> void:
    # MAIN MENU (and the Results ui_cancel route, Doc 01 §14): clear the stack
    # to Main.
    clear_to_main()

func clear_to_main() -> void:
    _last_route_error = ""
    _route_stack.clear()
    _active_surface = ""
    for name in _presented:
        _presented[name] = false
    if flow != null:
        flow.return_stack.clear()
        flow.origin = ORIGIN_MAIN
    _leave_to_home()

# --- Story surface callbacks -------------------------------------------------
func _on_story_chosen(id: String) -> void:
    # The briefing's own selection path (tiles/pointer/keyboard) writes into the
    # typed authority; AppState carries the choice across the Main return and
    # the Story Result re-entry, so the selection is never lost with the scene.
    var fighter := _allowed_story_fighter(str(id))
    if fighter == "" or flow == null or flow.slots.is_empty():
        return
    flow.slots[0].fighter_id = fighter
    AppStateScript.story_fighter_id = fighter

func _on_story_start() -> void:
    # START ENCOUNTER: freeze the validated story state into an immutable
    # MatchLaunchConfig and launch exactly like the VS path (§6 handshake).
    if _launch_state != LAUNCH_IDLE or _mode != MODE_STORY:
        return
    if not _begin_story_launch():
        return
    if _briefing != null:
        # The briefing's own exit choreography covers the construction window.
        _briefing.play_exit()

func _begin_story_launch() -> bool:
    var selected := _coerce_story_fighter()
    if selected == "":
        _last_route_error = str(StateScript.MESSAGE_ENCOUNTER_FIGHTER)
        return false
    # Story launches the encounter's own stage (Doc 02 §8); Stage Select is not
    # part of the Story route.
    var stage_id := story_stage_id()
    flow.stage_id = str(stage_id)
    var config = LaunchConfigScript.build(flow, str(stage_id))
    if not config.is_valid():
        _last_route_error = str(config.validation_error())
        return false
    _last_route_error = ""
    pending_launch = config
    _launch_confirmed = true
    _frontend_exited = false
    # §6: construct the destination NOW, while the briefing still owns the
    # frame.
    _construct_gameplay(config)
    return true

func _on_story_back() -> void:
    # Story Back follows the player route Story -> Main (Doc 07 §15); the
    # authored exit runs first so the route is never a hard cut.
    _last_route_error = ""
    if _launch_state != LAUNCH_IDLE:
        return
    if _briefing != null:
        _briefing.play_exit()
    else:
        _leave_to_home()

func _on_story_exit_finished() -> void:
    _hide_surface(SURFACE_STORY)
    if _launch_confirmed:
        # The START exit belongs to the launch, not to a POP: hold here and let
        # the readiness handshake release the flow (§6).
        _frontend_exited = true
        _maybe_launch()
        return
    _leave_to_home()

func _show_story_result(won: bool) -> void:
    # The shipped Story result state stays on the briefing (Doc 07 §16: wording
    # + REPLAY/RETRY + MAIN MENU, never the multiplayer Results screen). WP-5
    # owns the standalone Story Result redesign.
    if _briefing == null:
        return
    _briefing.show_result(won)

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
    return _begin_launch_with_config(config)

func _begin_launch_with_config(config) -> bool:
    # The frozen snapshot starts the §6 handshake: construct the destination NOW,
    # while the outgoing surface still owns the frame (SSS confirm pose + exit
    # choreography, the Story START exit, or the Results REMATCH release).
    _last_route_error = ""
    pending_launch = config
    _launch_confirmed = true
    _frontend_exited = false
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
    if not _launch_confirmed or not _frontend_exited:
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
    # Doc 03 §9: ONE active scope, owned by the ONE semantic service. Every
    # centralized transition (stage confirm, story start, results rematch and
    # the returns) passes through this function, so the service can never
    # disagree with the router about who owns input.
    _scope = str(scope)
    FrontendInput.set_scope(_scope)

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

func story_briefing() -> Control:
    return _briefing

func entry_mode() -> String:
    return _mode

func is_story_mode() -> bool:
    return _mode == MODE_STORY

func story_encounter_id() -> String:
    return str(flow.story_encounter_id) if flow != null else ""

func story_selection_id() -> String:
    if flow == null or flow.slots.is_empty():
        return ""
    return str(flow.slots[0].fighter_id)

func story_playable_ids() -> Array:
    return _story_playable_fighters()

func story_stage() -> String:
    return story_stage_id()

func post_match() -> Control:
    return _post_match

func post_match_payload() -> Dictionary:
    return _post_match_payload

func post_match_result():
    return _post_match_result

func post_match_config():
    return _post_match_config

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
    if surface_name == SURFACE_STORY:
        return screen.get_node_or_null("ReferenceFrame") as Control
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

extends Node
# VS presentation orchestration adapter
# (NRCU_VS_FINAL_IMPLEMENTATION_HANDOFF_v2_0 §8-§10, generalized by the
#  NRCU_VS_MULTIPLAYER_FOLLOWUP_HANDOFF_v1_3 contract).
#
# WHY THIS FILE EXISTS
#   The VS overlay is a presentation module, the match start is the frontend
#   router's job, and neither should absorb the other. This adapter is the ONLY
#   place that knows both:
#     * it decides whether a launch CONFIG is a supported VS case: an ordered
#       list of 2-4 active fighter records (v1.3), every fighter in the
#       presentation roster AND the facing authority, and a route defined by
#       schema/match_presentation_contract.json;
#     * it builds the normalized presentation plan
#       (scripts/vs_presentation_request.gd), which preserves each fighter's
#       original player (P1-P4) identity and team id;
#     * it mounts the overlay above everything else and routes the launch:
#       - 2 active fighters  -> the approved DUEL_1V1 renderer through the
#         existing start(left_fighter_id, right_fighter_id, stage_id)
#         compatibility wrapper, so 1v1 output stays visually and temporally
#         identical;
#       - 3/4 active fighters -> the generalized multiplayer renderer
#         start_presentation(plan) (FFA_3/FFA_4/TEAM_2V2/TEAM_2V1/TEAM_3V1 and
#         the mirrored 1V2/1V3 variants);
#     * it forwards the match-readiness handoff and the cover handoff back to
#       the host.
#   The host (MatchFlow) keeps one narrow call site per direction, so gameplay
#   code carries no VS logic at all.
#
# BYPASS IS THE CONSERVATIVE DEFAULT
#   supported_reason() returns a NON-EMPTY reason string for anything the
#   handoff does not cover (invalid config, Story/Bobo encounters, an active
#   count outside 2-4, an unknown fighter, a team split with no supported
#   route), and the host then keeps its existing immediate match-start path. No
#   UI is invented for those cases (contract §10). The v1.3 handoff REPLACES
#   the old "not exactly two active fighters" bypass: 3/4-player configurations
#   with supported fighters now take the multiplayer route instead of the
#   immediate path; only the unsupported shapes above still bypass.
#
# LOADER SAFETY
#   The overlay is mounted on the tree ROOT, not under the host: the host
#   releases itself over the live destination (its authored LAUNCH fade frees
#   it), and the overlay must outlive the cover -> reveal handoff. The overlay
#   frees itself on exit_finished; the adapter dies with its host.
#
# Events exposed for tests/evidence:
#   bypassed(reason)   the VS presentation did not take this launch
#   started            the overlay began ENTRY
#   cover_reached      forwarded from the overlay at full cover
#   finished           forwarded after the reveal, when the overlay is freed

signal bypassed(reason: String)
signal started
signal cover_reached
signal finished

const VsScreenScene = preload("res://scenes/vs_screen.tscn")
const ScreenScript = preload("res://scripts/vs_screen.gd")
const RequestScript = preload("res://scripts/vs_presentation_request.gd")
const GameFxScript = preload("res://scripts/fx_vnext/game_binding.gd")

const REASON_INVALID_CONFIG := "invalid_config"
const REASON_STORY := "story_encounter"
# v1.3: the count reason replaces the old REASON_NOT_ONE_V_ONE — 2-4 active
# fighters are the presentation's input, anything outside that range bypasses.
const REASON_COUNT := "unsupported_active_fighter_count"
const REASON_ROUTE := "unsupported_presentation_route"
const REASON_UNKNOWN_FIGHTER := "unsupported_fighter"
const REASON_SCENE_UNAVAILABLE := "vs_scene_unavailable"
const REASON_PRODUCTION_UNAVAILABLE := "fx_production_unavailable"

var _host: Node = null
var _screen: CanvasLayer = null
var _started := false
var _ready_signalled := false
var _bypass_reason := ""
var _production_errors: Array = []
var _records: Array = []
var _plan: Dictionary = {}
var _route := ""
var _left_id := ""
var _right_id := ""
var _stage_id := ""

# --- support decision (pure; usable without an instance) --------------------

static func presentation_plan(config) -> Dictionary:
	# The normalized render plan for this launch (record contents included);
	# {"ok": false, "reason": ...} when the launch is not representable.
	if config == null or not config.is_valid():
		return {"ok": false, "reason": REASON_INVALID_CONFIG}
	if config.has_story():
		return {"ok": false, "reason": REASON_STORY}
	var records: Array = RequestScript.from_config(config)
	return RequestScript.plan(records, str(config.stage_id()),
		RequestScript.teams_enabled(config, records))

static func supported_reason(config) -> String:
	# "" when the VS presentation owns this launch, otherwise the bypass reason.
	if config == null or not config.is_valid():
		return REASON_INVALID_CONFIG
	if config.has_story():
		# Story/Bobo encounters keep the existing immediate path (contract §10).
		return REASON_STORY
	var records: Array = RequestScript.from_config(config)
	if records.size() < 2 or records.size() > 4:
		# The presentation consumes an ordered 2-4 record list; anything else
		# keeps the immediate match-start path.
		return REASON_COUNT
	for record in records:
		if not _record_supported(record):
			return REASON_UNKNOWN_FIGHTER
	var route_id := RequestScript.route(records, RequestScript.teams_enabled(config, records))
	if route_id == "":
		# A team split with no defined layout route (e.g. a team mode launch
		# whose fighters are not split 2+1 / 2+2 / 3+1) has no presentation.
		return REASON_ROUTE
	return ""

static func is_supported(config) -> bool:
	return supported_reason(config) == ""

static func _record_supported(record: Dictionary) -> bool:
	# Both authorities must accept the fighter: the presentation roster (the
	# three textures exist) and the optical facing profile (orientation rule).
	var fighter_id := str(record.get("fighter_id", ""))
	if fighter_id == "":
		return false
	return ScreenScript.supports_fighter(fighter_id) and RequestScript.supports_fighter(fighter_id)

# --- lifecycle --------------------------------------------------------------

func begin(config, host: Node = null) -> bool:
	# Mount the overlay for a supported launch. Returns false (after emitting
	# bypassed) whenever the host must use its immediate path instead.
	if _started:
		return true
	_production_errors.clear()
	var reason := supported_reason(config)
	if reason != "":
		_bypass_reason = reason
		bypassed.emit(reason)
		return false
	_host = host
	_records = RequestScript.from_config(config)
	_plan = RequestScript.plan(_records, str(config.stage_id()),
		RequestScript.teams_enabled(config, _records))
	_route = str(_plan.get("route", ""))
	_stage_id = str(_plan.get("stage_id", ""))
	var screen := VsScreenScene.instantiate() as CanvasLayer
	if screen == null:
		_bypass_reason = REASON_SCENE_UNAVAILABLE
		bypassed.emit(_bypass_reason)
		return false
	screen.name = "VsScreen"
	get_tree().root.add_child(screen)
	# Connect BEFORE start(): the overlay may reach its first handoff quickly.
	screen.transition_cover_reached.connect(_on_transition_cover_reached)
	screen.exit_finished.connect(_on_exit_finished)
	_screen = screen
	var prepared := false
	if _route == RequestScript.ROUTE_DUEL:
		# 2 active fighters: the approved 1v1 renderer, handed the plan's
		# player-ordered pair through the compatibility wrapper.
		var fighters: Array = _plan.get("fighters", [])
		_left_id = str(fighters[0]["fighter_id"])
		_right_id = str(fighters[1]["fighter_id"])
		if screen.has_method("set_duel_slots"):
			screen.set_duel_slots(int(fighters[0].get("index", 0)), int(fighters[1].get("index", 1)))
		prepared = screen.start(_left_id, _right_id, _stage_id)
	else:
		# 3/4 active fighters: the generalized multiplayer renderer.
		prepared = screen.start_presentation(_plan)
	if not prepared:
		_bypass_reason = REASON_ROUTE if _route != RequestScript.ROUTE_DUEL else REASON_UNKNOWN_FIGHTER
		_screen = null
		screen.queue_free()
		bypassed.emit(_bypass_reason)
		return false
	# FX owns neither the match-readiness handshake nor screen lifetime.
	var game_fx := GameFxScript.new()
	game_fx.name = "ProductionFx"
	screen.add_child(game_fx)
	var bind_result: Dictionary = game_fx.bind_started_screen(screen, "1v1" if _route == RequestScript.ROUTE_DUEL else _route, _stage_id)
	if not bool(bind_result.get("ok", false)):
		var raw_errors = bind_result.get("errors", [])
		_production_errors = raw_errors.duplicate(true) if raw_errors is Array else [str(raw_errors)]
		var missing_looks = bind_result.get("missing_looks", [])
		if missing_looks is Array:
			for look_id in missing_looks:
				_production_errors.append("missing production look: " + str(look_id))
		if _production_errors.is_empty():
			_production_errors.append("production reload failed")
		_bypass_reason = REASON_PRODUCTION_UNAVAILABLE
		_screen = null
		screen.queue_free()
		bypassed.emit(_bypass_reason)
		return false
	_started = true
	started.emit()
	return true

func signal_match_ready() -> void:
	# Forwarded by the host once the launch handshake is complete (validated
	# config + the outgoing frontend released + the destination ready, or the
	# destination's bounded readiness deadline passed).
	_ready_signalled = true
	if _screen != null and is_instance_valid(_screen):
		_screen.signal_match_ready()

func _on_transition_cover_reached() -> void:
	cover_reached.emit()
	if _host != null and is_instance_valid(_host) and _host.has_method("complete_launch_under_cover"):
		# Full cover: the host reveals gameplay and starts the existing
		# Ready/Go underneath it (contract §8/§9).
		_host.complete_launch_under_cover()

func _on_exit_finished() -> void:
	_screen = null
	finished.emit()

# --- reads (tests / evidence) ----------------------------------------------

func screen() -> CanvasLayer:
	return _screen

func host() -> Node:
	return _host

func has_started() -> bool:
	return _started

func ready_signalled() -> bool:
	return _ready_signalled

func bypass_reason() -> String:
	return _bypass_reason

func production_errors() -> Array:
	return _production_errors.duplicate(true)

func records() -> Array:
	# The ordered active fighter records (player/slot identity + team id).
	return _records.duplicate(true)

func plan() -> Dictionary:
	# The normalized presentation plan this launch was routed with.
	return _plan.duplicate(true)

func route_id() -> String:
	# The routing decision: DUEL_1V1 for a 2-fighter match, a family route
	# (FFA_3/FFA_4/TEAM_2V2/TEAM_2V1/TEAM_1V2/TEAM_3V1/TEAM_1V3) otherwise.
	return _route

func team_state() -> bool:
	return bool(_plan.get("teams_enabled", false))

func left_id() -> String:
	return _left_id

func right_id() -> String:
	return _right_id

func launch_stage_id() -> String:
	return _stage_id

func state() -> String:
	if _screen != null and is_instance_valid(_screen):
		return str(_screen.state())
	# Once started, the overlay is gone only after its own exit_finished.
	return "done" if _started else "idle"

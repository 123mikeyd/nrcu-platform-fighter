extends Node
## SSB64 feel pass - Batch 2 "Movement" (jump squat, short hop, fast fall, landing lag, jump arc).
## One instance per fighter (child "SSBMovement"); fighter.gd only calls the small hooks below:
##   step(delta, input)      replaces the ordinary per-tick gravity line (also squat/fast-fall/landing)
##   intercept_jump()        start of try_jump(): grounded jumps begin a jump squat instead
##   on_takeoff()            inside try_jump() after the base jump velocity is set
##   begin_authored_flight() ledge jump: keep the classic gravity its numbers were tuned for
##   reset()                 _clear_move_state()
##       [CAL]  = calibrated for NRCU's world (fighter pill 1.8 m, blast zone y>15, top platform 6.2 m).
## Every frame count is a 60 Hz physics tick (Godot default physics rate; project.godot does not override it).

# ---------------- Switches (one per feature, default ON) ----------------
static var JUMP_SQUAT_ENABLED := true
static var SHORT_HOP_ENABLED := true
static var FAST_FALL_ENABLED := true
static var LANDING_LAG_ENABLED := true
static var JUMP_ARC_ENABLED := true

static func set_all(on: bool) -> void:
	JUMP_SQUAT_ENABLED = on
	SHORT_HOP_ENABLED = on
	FAST_FALL_ENABLED = on
	LANDING_LAG_ENABLED = on
	JUMP_ARC_ENABLED = on

const TIC := 1.0 / 60.0

# ---------------- 1. Jump squat ----------------
const JUMP_SQUAT_FRAMES := 3  # [FACT] kneebend_anim_length 3 for Mario/Fox/Kirby/...; airborne on tick 3.
# Per-character exceptions (none active). [CAL proposal] Bobo, the heavy 2.6 m mech, could take 4
# (SSB64 heavies use 4-7: Falcon 4, Yoshi 5, DK 6) - left at 3 because Bobo's tests/notes ask for no
# pre-jump input lag. Add e.g. {"bobo": 4} here to try it.
const JUMP_SQUAT_FRAMES_BY_CHARACTER := {}

# ---------------- 2. Short hop ----------------
const SHORT_HOP_WINDOW_FRAMES := 3  # [FACT] FTCOMMON_KNEEBEND_SHORTHOP_FRAMES: button released on squat ticks 1..3.
const SHORT_HOP_RATIO := 0.72       # [FACT-derived] SSB64 short/full take-off speed 0.68-0.83 (Mario 57.5/79.9 = 0.72).

# ---------------- 3. Fast fall ----------------
const FAST_FALL_MULT := 1.6  # [FACT] tvel_fast / tvel_base = 1.58-1.60 across the cast; set instantly, no gravity.
# [CAL] Keyboard down is digital, so Down then F/G is how players input down-aerial / down-special.
# If F or G is pressed within this many ticks after a fast fall started, the fast fall is undone
# (previous vertical speed restored) so the down-aerial / down-special keeps its normal arc.
const FAST_FALL_CHORD_GRACE_FRAMES := 3

# ---------------- 4. Landing lag ----------------
const LANDING_LAG_FRAMES := 4            # [FACT] LandingLight interrupt begins at frame 4.
const LANDING_LAG_FAST_FALL_FRAMES := 8  # [FACT] LandingHeavy = same anim at 0.5 speed.
const GENTLE_LANDING_FRACTION := 20.0 / 44.0  # [FACT ratio] vel_y > -20 u/tic skips landing (Mario tvel 44).

# ---------------- 5. Jump arc ----------------
# Classic NRCU: JUMP_SPEED 10.5, GRAVITY 25, MAX_FALL 18 -> apex 2.2 m (1.2 bodies), max fall 1.7x jump speed.
# [CAL] Moderate SSB64-ward target, limited by NRCU's tight vertical room (top platform 6.2 m, blast y>15):
#   full hop apex 4.0 m (~2.2 bodies of 1.8 m), rise 0.45 s; max fall 0.56x jump speed (SSB64 ~0.55x).
const ARC_GRAVITY := 40.0        # [CAL] study's tempered value (Mario exact 48.6 m/s^2 at this scale).
const ARC_MAX_FALL := 10.0       # [CAL] 0.56x full-hop speed (SSB64 0.55x); fast fall = 16 m/s.
const ARC_FULL_HOP_HEIGHT := 4.0  # [CAL] metres; first jump (ground or walk-off).
const ARC_AIR_JUMP_HEIGHT_RATIO := 0.75  # [CAL] double jump height / full hop height (SSB64 Mario 0.85, cast 0.6-1.3).
# GGB keeps its five-jump identity: air jumps keep today's HEIGHTS (0.84^n chain), just snappier, so a
# full five-jump climb stays below the blast line from the top platform.
const ARC_HEIGHT_PRESERVING_AIR_JUMPS := ["ggb"]

var actor: Node
var squat_left := -1  # >= 0 while in jump squat (ticks until take-off)
var squat_elapsed := 0
var squat_button := false
var squat_short := false
var fast_falling := false
var _takeoff_now := false
var _short_takeoff := false
var _authored_flight := false
var _ff_age := 0
var _ff_prev_vy := 0.0
var _was_airborne := false
var _last_vy := 0.0
var _last_frame := -10
var _lag_owned := false
var _buffered := {}
var _held := {}
var _input_frame := -1
var _input: Dictionary = {}

func _ready() -> void:
	actor = get_parent()

static func squat_frames_for(character_id: String) -> int:
	return int(JUMP_SQUAT_FRAMES_BY_CHARACTER.get(character_id, JUMP_SQUAT_FRAMES))

## Ticks between an accepted grounded jump press and leaving the floor (0 when the switch is off).
static func jump_squat_delay(character_id: String) -> int:
	return squat_frames_for(character_id) if JUMP_SQUAT_ENABLED else 0

# ---- jump arc numbers ----
func arc_active() -> bool:
	if not JUMP_ARC_ENABLED or _authored_flight: return false
	return _free_air_state()

func gravity() -> float:
	return ARC_GRAVITY if arc_active() else float(actor.GRAVITY)

func max_fall() -> float:
	return ARC_MAX_FALL if arc_active() else float(actor.MAX_FALL_SPEED)

func fast_fall_speed() -> float:
	return FAST_FALL_MULT * max_fall()

static func arc_full_hop_speed() -> float:
	return sqrt(2.0 * ARC_GRAVITY * ARC_FULL_HOP_HEIGHT)

## Multiplier applied to the velocity try_jump() authored (keeps per-character ratios such as GGB 0.84^n).
func arc_scale(first_jump: bool) -> float:
	var classic: float = float(actor.JUMP_SPEED)
	if first_jump: return arc_full_hop_speed() / classic
	if actor.character_id in ARC_HEIGHT_PRESERVING_AIR_JUMPS:
		return sqrt(ARC_GRAVITY / float(actor.GRAVITY))
	return arc_full_hop_speed() * sqrt(ARC_AIR_JUMP_HEIGHT_RATIO) / classic

# Ordinary airborne control: not hit, no special/recovery/charge owning the body.
func _free_air_state() -> bool:
	var a = actor
	if a.hitstun > 0 or a.recovery_spent or a.charging or a.drop_committed: return false
	if a.tumble and a.tumble.active: return false
	if a._torpedo_committed(): return false
	if a.state_coordinator.control_lane() != "input": return false
	if a.doge_ground_rush and a.doge_ground_rush.phase != "idle": return false
	if a.mephisto_moves and not a.mephisto_moves.move.is_empty(): return false
	if a.teknium_magic and a.teknium_magic.phase != "idle": return false
	return true

func _aerial_attack_active() -> bool:
	var a = actor
	if a.attack_cooldown > 0: return true
	if not a.doge_attack_clip.is_empty() or not a.turbofit_attack_clip.is_empty() or not a.witcheer_clip.is_empty() or not a.ice_attack_clip.is_empty(): return true
	for n in ["humanoid_air_basic", "humanoid_air_side", "doge_air_drop", "ggb_basics", "ggb_air", "doge_cape_attack"]:
		var m = a.get(n)
		if m and m.get("active"): return true
	return false

# ---------------- per-tick hook (replaces the ordinary gravity line) ----------------
func step(delta: float, input: Dictionary) -> void:
	var a = actor
	var frame := Engine.get_physics_frames()
	# Ticks skipped by early returns (tumble, ledge, revival, hitstop) break continuity; repeated manual
	# _physics_process calls inside one engine frame (test harnesses) still count as continuous.
	var continuous := frame - _last_frame <= 1
	_last_frame = frame
	_input = input
	_input_frame = frame
	var edge := {}
	for k in ["down", "attack", "special", "jump", "up"]:
		edge[k] = bool(input.get(k, false)) and not bool(_held.get(k, false))
		_held[k] = bool(input.get(k, false))
	var attack_edge: bool = edge.attack or a._sample_short.has("attack")
	var special_edge: bool = edge.special or a._sample_short.has("special")
	var grounded: bool = a.is_grounded()
	var interrupted: bool = a.hitstun > 0 or (a.tumble and a.tumble.active) or not a.controls_enabled

	# --- 4. landing (detected on the first tick standing after an airborne tick) ---
	if continuous and _was_airborne and grounded and a.velocity.y <= 0.0:
		_on_landed()
	if grounded and a.velocity.y <= 0.0:
		_authored_flight = false
		if squat_left < 0: fast_falling = false
	if interrupted:
		fast_falling = false
		_cancel_squat()
		_authored_flight = false

	# --- landing-lag buffer: a press during OUR 4/8-tick lag fires when it ends ---
	if _lag_owned:
		if a.landing_lag > 0.0:
			var aim := Vector2(float(int(input.right) - int(input.left)), float(int(input.down) - int(input.up)))
			if attack_edge: _buffered = {"kind": "attack", "aim": a._sample_short.get("attack", aim)}
			elif special_edge: _buffered = {"kind": "special", "aim": a._sample_short.get("special", aim)}
			elif edge.jump or edge.up or a._sample_short.has("jump"): _buffered = {"kind": "jump"}
		else:
			_lag_owned = false
			if not _buffered.is_empty() and not interrupted:
				_replay(_buffered)
			_buffered = {}

	# --- 1. jump squat: F/G during the squat performs the grounded move instead (not eaten) ---
	if squat_left >= 0 and (attack_edge or special_edge):
		_cancel_squat()

	# --- 3. fast fall ---
	if fast_falling:
		_ff_age += 1
		if (attack_edge or special_edge) and _ff_age <= FAST_FALL_CHORD_GRACE_FRAMES:
			# Down was the first half of a down-aerial / down-special chord: undo, keep the move's arc.
			fast_falling = false
			a.velocity.y = _ff_prev_vy
		elif not _free_air_state():
			fast_falling = false
	elif FAST_FALL_ENABLED and edge.down and not attack_edge and not special_edge and not grounded and a.velocity.y <= 0.0 and not _aerial_attack_active() and _free_air_state():
		fast_falling = true
		_ff_age = 0
		_ff_prev_vy = a.velocity.y

	# --- gravity ---
	if fast_falling:
		a.velocity.y = -fast_fall_speed()  # [FACT] no gravity while fast falling
	else:
		var limit := max_fall()
		if a.velocity.y < -limit and arc_active():
			# Coming out of a classic-gravity state faster than the SSB terminal speed: ease down to it.
			a.velocity.y = move_toward(a.velocity.y, -limit, gravity() * delta)
		else:
			a.velocity.y = maxf(a.velocity.y - gravity() * delta, -limit)

	# --- 1/2. squat tick and take-off (after gravity, like the classic same-tick jump) ---
	if squat_left >= 0:
		squat_elapsed += 1
		if SHORT_HOP_ENABLED and squat_button and squat_elapsed <= SHORT_HOP_WINDOW_FRAMES and not bool(input.get("jump", false)):
			squat_short = true
		squat_left -= 1
		if squat_left <= 0:
			var short := squat_short
			_cancel_squat()
			_takeoff_now = true
			_short_takeoff = short
			a.try_jump()
			_takeoff_now = false
			_short_takeoff = false

	_was_airborne = not grounded or a.velocity.y > 0.0
	_last_vy = a.velocity.y

func _on_landed() -> void:
	var a = actor
	var heavy := fast_falling
	fast_falling = false
	if not LANDING_LAG_ENABLED: return
	if a.hitstun > 0 or (a.tumble and a.tumble.active) or not a.controls_enabled: return
	if a.revival and a.revival.phase != "idle": return
	if a.ledge_grab and a.ledge_grab.active(): return
	if a.state_coordinator.control_lane() != "input": return  # specials own their landings
	# [FACT] gentle touchdowns skip the landing entirely.
	var gentle: float = GENTLE_LANDING_FRACTION * (ARC_MAX_FALL if JUMP_ARC_ENABLED else float(a.MAX_FALL_SPEED))
	if _last_vy > -gentle and not heavy: return
	var frames := LANDING_LAG_FAST_FALL_FRAMES if heavy else LANDING_LAG_FRAMES
	# (frames - 0.5) ticks: landing_lag decrements before the next dispatch, so this blocks exactly `frames` ticks.
	var lag := (float(frames) - 0.5) * TIC
	if lag > a.landing_lag:  # never stack on a move's own (larger) landing lag
		a.landing_lag = lag
		_lag_owned = true
		_buffered = {}

func _replay(b: Dictionary) -> void:
	var a = actor
	match b.kind:
		"attack": a.basic_attack(b.aim, not a.is_grounded())
		"special": a.start_special(b.aim)
		"jump": a.try_jump()

# ---------------- try_jump hooks ----------------
## Called by try_jump() after its gates pass. True = a grounded jump became a jump squat.
func intercept_jump() -> bool:
	if _takeoff_now: return false
	if squat_left >= 0: return false  # already squatting: no second jump
	if not JUMP_SQUAT_ENABLED: return false
	var a = actor
	if not a.is_grounded() or a.velocity.y > 0.0: return false
	var frames := squat_frames_for(a.character_id)
	if frames <= 0: return false
	squat_left = frames
	squat_elapsed = 0
	squat_short = false
	# Only the jump BUTTON (Space / Enter / pad A) can short hop; tap-up (W / Up / stick) is always full [FACT].
	var fresh: bool = _input_frame == Engine.get_physics_frames()
	squat_button = fresh and (bool(_input.get("jump", false)) or a._sample_short.has("jump"))
	if squat_button and fresh and not bool(_input.get("jump", false)):
		squat_short = SHORT_HOP_ENABLED  # tapped and released between ticks
	return true

## Called by try_jump() right after it set the base jump velocity (jumps_used not yet incremented).
func on_takeoff() -> void:
	var a = actor
	fast_falling = false  # [FACT] any jump ends a fast fall
	_authored_flight = false
	if JUMP_ARC_ENABLED:
		a.velocity.y *= arc_scale(a.jumps_used == 0)
	if _short_takeoff and SHORT_HOP_ENABLED:
		a.velocity.y *= SHORT_HOP_RATIO

## True while the current landing_lag is this script's short 4/8-tick landing (presses get buffered).
func owns_landing_lag() -> bool:
	return _lag_owned and actor != null and actor.landing_lag > 0.0

func is_squatting() -> bool:
	return squat_left >= 0

func _cancel_squat() -> void:
	squat_left = -1
	squat_elapsed = 0
	squat_button = false
	squat_short = false

## Ledge jump etc.: velocities tuned for classic gravity keep it until landing / next jump / hit.
func begin_authored_flight() -> void:
	_authored_flight = true
	fast_falling = false

func reset() -> void:
	_cancel_squat()
	fast_falling = false
	_authored_flight = false
	_takeoff_now = false
	_short_takeoff = false
	_was_airborne = false
	_lag_owned = false
	_buffered = {}
	_held = {}
	_input = {}
	_input_frame = -1

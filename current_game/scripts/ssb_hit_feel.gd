extends RefCounted
## SSB64 "hit feel" (Batch 1). Shared rules for every fighter; kits keep their
## authored (damage, push, direction). Source study:
## [FACT] = value read in the SSB64 decomp. [CAL] = calibrated for NRCU here.
##
## One instance per fighter (fighter.hit_feel), created on the first hit.
## Each feature has its own switch. Default = ON. Turning one off restores the
## pre-SSB rule for that feature only.

# ---- switches -----------------------------------------------------------------
static var HITLAG_ENABLED := true          # attacker+victim freeze int(dmg/3+5) frames
static var SSB_KNOCKBACK_ENABLED := true   # SSB64 formula + per-character weight
static var LAUNCH_DECAY_ENABLED := true    # launch speed is a separate channel, linear decay
static var SSB_HITSTUN_ENABLED := true     # hitstun = kb/1.875 frames, flinch tiers, tumble at kb>=60
static var BUFFER_DURING_HITLAG := true   # quick presses during hitlag count on the first unfrozen frame
static var DEV_READOUT_ENABLED := true     # Dev Mode hit log shows kb/hitlag/hitstun/tier

# ---- SSB64 constants [FACT] ------------------------------------------------------
const LOGIC_HZ := 60.0                 # [FACT] macros.h:78 UPDATE_INTERVAL
const KB_CAP := 2500.0                 # [FACT] ftparam.c:1465
const HITSTUN_DIV := 1.875             # [FACT] ftparam.c:1507 frames = kb / 1.875
const FLINCH_TIERS := [12, 24, 32]     # [FACT] ftcommon.h:101-107, compared against hitstun frames
const KB_DECAY := 1.7                  # [FACT] ftmain.c:1776 units/frame^2 along launch vector
const HITLAG_BASE := 5.0               # [FACT] ftparam.c:1514 (US)
const HITLAG_DIV := 3.0                # [FACT] ftparam.c:1514
const SAKURAI_GROUND_KB_MIN := 32.0    # [FACT] ftcommon.h:96 weak grounded hits stay flat below this

# ---- NRCU calibration [CAL] ----------------------------------------------------------
# Metres per SSB knockback unit. kb 1 = 1 unit/frame = SSB_UNIT_M*60 m/s.
# Chosen so an 8%/3.8 basic at 0% keeps today's 5.3 m/s launch while getting
# ~18f (0.30 s) of hitstun (SSB tilt-like), and strong 14%/5.5 finishers KO a
# 1.00-weight fighter from centre stage at ~115-125%. Smaller than "Mario 320u
# = 2.2 m" (0.0069) because NRCU blast zones (|x|>16, y>15, y<-8) are ~3x tighter
# than SSB64 stages in body heights.
const SSB_UNIT_M := 0.0026
const KB_TO_MPS := SSB_UNIT_M * LOGIC_HZ                       # 0.156 (m/s) per kb
const DECAY_MPS2 := KB_DECAY * SSB_UNIT_M * LOGIC_HZ * LOGIC_HZ  # 15.9 m/s^2
# Move "push" (NRCU base_knockback, m/s) -> SSB knockback growth. Push is how
# designers already marked a move's launch intent: <=1 setup jab, 3.8 basic,
# 5.5-6 strong, 8-9 charged. Values are SSB-like (jab 50, smash 100-120). [CAL]
const KBG_BY_PUSH := [[0.0, 20.0], [1.0, 25.0], [2.0, 35.0], [3.8, 55.0], [5.5, 85.0], [6.0, 95.0], [8.0, 105.0], [9.0, 110.0]]
# NRCU damage numbers run higher than SSB64 (22-26% charged hits). The SSB term
# pct*dmg*0.05 would let those KO at ~35%; growth per % is normalised to a 12%
# hit for anything stronger (never boosted for weaker hits). [CAL]
const GROWTH_REF_DAMAGE := 12.0
# Low-% match: bkb is solved so a fresh hit (victim at 0%) launches at today's
# speed, capped at 9 m/s so charged moves don't KO at 70%. [CAL]
const LOW_PCT_MATCH_CAP := 9.0
# Synthetic huge hits (tests, story scripts doing 500%) would freeze for
# seconds; real NRCU hits top out ~26% = 13f. [CAL]
const HITLAG_MAX_FRAMES := 20
const RANGED_DISTANCE := 3.2   # [CAL] attacker farther than this = ranged hit, shooter not frozen
# One physics frame of gravity is 0.42 m/s; anything bigger is a move override. [CAL]
const OVERRIDE_TOLERANCE := 0.6
const MAX_FLIGHT := 4.5        # [CAL] safety cap on tumble flight (old cap 1.6 s)

# Per-character weight ("knockback multiplier", bigger flies further). SSB64
# range 0.84 (DK) .. 1.30 (Jigglypuff) [FACT]; which NRCU fighter gets which is
# a design call [CAL].
const WEIGHTS := {
	"teknium": 1.00,   # Mario baseline
	"doge_man": 0.96,  # Link / Falcon
	"turbofit": 0.93,  # Yoshi: muscular, sturdy
	"ggb": 1.16,       # Pikachu: small and floaty (5 jumps)
	"witcheer": 1.10,  # Ness: light
	"ice_mage": 1.05,
	"mephisto": 0.92,  # Samus; demon form keeps its own x0.8 on top
	"bobo": 0.84,      # DK: heavy stationary prototype
}

var actor
var knock := Vector3.ZERO        # remaining launch channel (m/s), decays linearly
var _knock_fresh := false
var _launch_v := Vector3.ZERO   # velocity right after the hit, to spot bespoke overrides
# Last hit, for Dev Mode and tests.
var last := {}

func _init(fighter = null) -> void:
	actor = fighter

static func weight_of(character_id: String) -> float:
	return float(WEIGHTS.get(character_id, 1.0))

static func kbg_for_push(push: float) -> float:
	var t: Array = KBG_BY_PUSH
	if push <= t[0][0]: return t[0][1]
	for i in range(1, t.size()):
		if push <= t[i][0]:
			return lerpf(t[i - 1][1], t[i][1], (push - t[i - 1][0]) / (t[i][0] - t[i - 1][0]))
	return t[-1][1]

## SSB64 ftParamGetCommonKnockback shape [FACT ftparam.c:1451]; post_pct = % after the hit.
static func ssb_knockback(post_pct: float, hit_damage: float, weight: float, kbg: float, bkb: float) -> float:
	return minf(((post_pct * 0.1 + post_pct * hit_damage * 0.05) * weight * 1.4 + 18.0) * kbg * 0.01 + bkb, KB_CAP)

static func legacy_speed(post_pct: float, hit_damage: float, push: float) -> float:
	return push + post_pct * 0.065 + hit_damage * 0.12

## (kbg, bkb) for an existing NRCU move (damage, push). Pure function of the
## move, so the same move launches the same way on every victim at 0%.
static func move_params(hit_damage: float, push: float) -> Vector2:
	var kbg := kbg_for_push(push) * minf(1.0, (0.1 + 0.05 * GROWTH_REF_DAMAGE) / (0.1 + 0.05 * maxf(hit_damage, 0.0)))
	var low_speed := minf(LOW_PCT_MATCH_CAP, legacy_speed(hit_damage, hit_damage, push))
	var bkb := maxf(0.0, low_speed / KB_TO_MPS - ssb_knockback(hit_damage, hit_damage, 1.0, kbg, 0.0))
	return Vector2(kbg, bkb)

static func hitstun_frames(kb: float) -> int:
	return maxi(1, int(kb / HITSTUN_DIV))

static func flinch_level(frames: int) -> int:
	if frames >= FLINCH_TIERS[2]: return 3
	if frames >= FLINCH_TIERS[1]: return 2
	if frames >= FLINCH_TIERS[0]: return 1
	return 0

static func hitlag_frames(hit_damage: float) -> int:
	return int(hit_damage / HITLAG_DIV + HITLAG_BASE)

# ---- per-hit resolution (called from Fighter.receive_hit) ---------------------
## Launch speed in m/s. Zero-damage pushes (Sound Orb) keep the legacy rule.
func launch_speed(post_pct: float, hit_damage: float, push: float) -> float:
	last = {"damage": hit_damage, "push": push, "pct": post_pct, "ssb": false}
	if not SSB_KNOCKBACK_ENABLED or hit_damage <= 0.0:
		return legacy_speed(post_pct, hit_damage, push)
	var p := move_params(hit_damage, push)
	var w := weight_of(str(actor.character_id)) if actor else 1.0
	var kb := ssb_knockback(post_pct, hit_damage, w, p.x, p.y)
	last.merge({"ssb": true, "kbg": p.x, "bkb": p.y, "weight": w, "kb_raw": kb}, true)
	return kb * KB_TO_MPS

## Hitstun seconds for the final launch speed (after armor/collateral caps).
func hitstun_for(speed: float, hit_damage: float) -> float:
	var kb := speed / KB_TO_MPS
	last["kb"] = kb
	last["speed"] = speed
	if not SSB_HITSTUN_ENABLED or hit_damage <= 0.0:
		last["hitstun_f"] = roundi((0.08 + speed * 0.025) * LOGIC_HZ)
		last["level"] = -1
		return 0.08 + speed * 0.025
	# Weak-hit floor [CAL]: never shorter than the pre-SSB hitstun, so light setup
	# jabs (Doge Tyson jab, Bobo thrust, <2.5 m/s) keep linking into their followups.
	var frames := maxi(hitstun_frames(kb), int(ceilf((0.08 + speed * 0.025) * LOGIC_HZ - 0.0001)))
	last["hitstun_f"] = frames
	last["level"] = flinch_level(frames)
	return frames / LOGIC_HZ

## True when the SSB tier decides tumble (instead of the old 12 m/s gate).
func tiers_active() -> bool:
	return SSB_HITSTUN_ENABLED and int(last.get("level", -1)) >= 0

func is_tumble() -> bool:
	return int(last.get("level", -1)) >= 3

## Weak grounded hits stay on the ground (SSB: kb < 32 on the ground -> 0 deg,
## slide). Only shallow authored directions (< ~25 deg up) are flattened, so
## kits' deliberate pops/uppercuts keep their direction.
func ground_direction(direction: Vector3, speed: float, hit_damage: float) -> Vector3:
	if not SSB_HITSTUN_ENABLED or hit_damage <= 0.0 or actor == null or not actor.is_grounded(): return direction
	if speed / KB_TO_MPS >= SAKURAI_GROUND_KB_MIN: return direction
	var d := direction.normalized()
	if d.y > 0.0 and d.y < 0.42 and absf(d.x) > 0.0:
		return Vector3(signf(d.x), 0, 0)
	return direction

## Store the launch as its own decaying channel. Call right after velocity is set.
func begin_launch(launch: Vector3, hit_damage: float) -> void:
	knock = launch if LAUNCH_DECAY_ENABLED and hit_damage > 0.0 else Vector3.ZERO
	_launch_v = launch
	_knock_fresh = true

## The shared tumble lift (launch_tumble.gd) adds own upward motion; not an override.
func rebase() -> void:
	_launch_v = actor.velocity

func clear() -> void:
	knock = Vector3.ZERO
	_knock_fresh = false

## Hitlag length for this hit. Zero when disabled, for zero-damage pushes and
## for (retired) shield blocks.
func prepare_hitlag(hit_damage: float) -> void:
	last["attacker_frozen"] = false
	last["hitlag_f"] = 0
	if not HITLAG_ENABLED or hit_damage <= 0.0 or actor == null or actor.shielding: return
	last["hitlag_f"] = mini(hitlag_frames(hit_damage), HITLAG_MAX_FRAMES)

## Hit-freeze both fighters, after the hit reaction is set up. Reuses the
## counter hitstop freeze path (physics and AnimationPlayers paused).
## Projectile / ranged hits only freeze the victim. [FACT wpprocess.c:125]
func apply_hitlag(source, collateral: bool) -> void:
	var frames := int(last.get("hitlag_f", 0))
	if frames <= 0 or actor == null: return
	var seconds := frames / LOGIC_HZ
	actor.begin_counter_hitstop(seconds)
	if BUFFER_DURING_HITLAG: actor.set_meta("ssb_hitlag", true)
	if collateral or not is_instance_valid(source) or source == actor: return
	if not source.has_method("begin_counter_hitstop") or not source.is_in_group("fighters"): return
	if _is_ranged(source): return
	source.begin_counter_hitstop(seconds)
	if BUFFER_DURING_HITLAG: source.set_meta("ssb_hitlag", true)
	last["attacker_frozen"] = true

func _is_ranged(source) -> bool:
	for p in actor.get_tree().get_nodes_in_group("projectiles"):
		if is_instance_valid(p) and p.get("source") == source and p is Node3D and p.global_position.distance_to(actor.global_position) < RANGED_DISTANCE + 1.0:
			return true
	return (source.global_position - actor.global_position).length() > RANGED_DISTANCE

# ---- launch channel decay --------------------------------------------------------
## Shrink the launch channel by DECAY along its own direction and take that
## amount out of the fighter's velocity. Gravity/own motion is untouched, which
## is the SSB split (own velocity + knockback velocity). [FACT ftmain.c:1767]
func decay_step(delta: float) -> void:
	if knock == Vector3.ZERO: return
	var v: Vector3 = actor.velocity
	if _knock_fresh:
		_knock_fresh = false
		# A move replaced the launch after receive_hit (Doge up-B spike sets -12 m/s,
		# Tyson/Bobo setup jabs clamp to ~0.2 m/s): keep the move's bespoke motion.
		if v.distance_to(_launch_v) > OVERRIDE_TOLERANCE:
			knock = Vector3.ZERO
			return
	# A wall or the floor already stopped this axis.
	if knock.x != 0.0 and v.x * signf(knock.x) <= 0.0001: knock.x = 0.0
	# Landed: SSB keeps only the ground (x) part of the launch once you touch down.
	if knock.y != 0.0 and actor.is_on_floor() and v.y <= 0.0: knock.y = 0.0
	var speed := knock.length()
	if speed <= 0.0: return
	var next := maxf(0.0, speed - DECAY_MPS2 * delta)
	var removed := knock * (1.0 - next / speed)
	knock -= removed
	if next <= 0.0001: knock = Vector3.ZERO
	actor.velocity = v - removed

## Collision bookkeeping after move_and_slide.
func after_slide() -> void:
	if knock == Vector3.ZERO: return
	if actor.is_on_wall() and knock.x != 0.0 and actor.velocity.x * signf(knock.x) <= 0.0001: knock.x = 0.0
	if actor.is_on_ceiling() and knock.y > 0.0: knock.y = 0.0
	if actor.is_on_floor() and actor.velocity.y <= 0.0: knock.y = 0.0

## Tumble flight step: decay the launch channel and apply gravity to own motion only.
func tumble_step(delta: float) -> void:
	decay_step(delta)
	var own_y: float = actor.velocity.y - knock.y
	own_y = maxf(own_y - actor.GRAVITY * delta, -actor.MAX_FALL_SPEED)
	actor.velocity.y = own_y + knock.y

## Flinch (non-tumble) hitstun step: gravity already ran in Fighter; only decay.
func flinch_step(delta: float) -> void:
	decay_step(delta)
	if actor.hitstun <= 0.0: clear()

## True when this hit already applied SSB hitlag.
func froze() -> bool:
	return int(last.get("hitlag_f", 0)) > 0

func decay_active() -> bool:
	return LAUNCH_DECAY_ENABLED

func max_flight() -> float:
	return MAX_FLIGHT if SSB_HITSTUN_ENABLED else 1.6

# ---- Dev Mode readout -----------------------------------------------------------------
func readout() -> String:
	if not DEV_READOUT_ENABLED or last.is_empty(): return ""
	var tier: Array = ["light", "medium", "heavy", "TUMBLE"]
	var level := int(last.get("level", -1))
	var s := "  kb %.0f" % float(last.get("kb", 0.0))
	if last.get("ssb", false):
		s += " (kbg %.0f bkb %.0f w%.2f)" % [float(last.kbg), float(last.bkb), float(last.weight)]
	s += "  lag %df%s" % [int(last.get("hitlag_f", 0)), "" if last.get("attacker_frozen", false) else " (victim)"]
	if level >= 0: s += "  %s" % tier[level]
	return s

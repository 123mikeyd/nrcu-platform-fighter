extends RefCounted
## SSB64 CLANKS: attack-vs-attack cancellation + rebound (shared, whole roster).
## [CAL] = calibrated for NRCU, [INF] = inferred, not read directly in code.
##
##  ftMainUpdateAttackStatFighter (ftmain.c:2031-2059)
##    this hitbox clanks  if this.damage  - 10 < other.damage
##    other hitbox clanks if other.damage - 10 < this.damage            [FACT]
##    -> within 9 both clank; 10+ ahead the stronger keeps going and may hit.
##  Clank check only runs when BOTH fighters are grounded
##    (ftmain.c:3080 other_fp->ga == Ground && this_fp->ga == Ground). Aerials
##    never clank against fighters, they trade.                         [FACT]
##  Teammates with team attack off never clank (ftmain.c:3082-3083).    [FACT]
##  Rebound: ftMainSetHitRebound (ftmain.c:2012-2028), only if grounded:
##    attack_rebound = own_clanked_damage * 1.62 + 4 frames (US).       [FACT]
##  ftCommonReboundWaitSetStatus (ftcommonrebound.c:37-55): no interrupts,
##    slide vel_ground.x = 2 * rebound_timer units/frame, away from the other
##    fighter, normal ground friction (floor 4.0 * traction, Mario 1.5 =
##    6 u/f^2; mpcollision.c:15, 203_MarioMain.c:244, ftphysics.c:158). [FACT]
##  Clank hitlag: ftParamGetHitLag(attack_shield_push) for each CLANKED fighter,
##    attack_shield_push = its own clanked hitbox damage (ftmain.c:3935-3946,
##    3988). The uncancelled stronger side gets no clank hitlag.        [FACT]
##  If the same frame also damaged the fighter, the damage branch wins over the
##    clank (ftmain.c:3880-3946 if/else order).                         [FACT]
##  SetOff spark: scale = d<10 ? 1-0.05*(10-d) : 1+0.15*(d-10) (efmanager.c:3986).
##    No dedicated clank sound in ftmain/rebound code (grep).           [FACT]
##
##  Projectiles (weapons), ftMainUpdateAttackStatWeapon (ftmain.c:2213-2245,
##  search 3262-3320):
##    same +-10 rule with the weapon's (staled) damage; NO grounded requirement
##    on the fighter, but the fighter hitbox must be allowed to hit the weapon's
##    air/ground state, and the weapon must have can_setoff. A fighter whose
##    hitbox clanks rebounds only if grounded. A clanked weapon runs proc_setoff
##    (wpprocess.c:511-519); e.g. Mario's fireball uses ProcHit -> destroyed
##    (wpmariofireball.c:71,126), Link's boomerang returns instead.   [FACT]
##    Which weapons have can_setoff is ROM attribute data, not C.       [INF: unknown]
##  Weapon vs weapon (wpprocess.c:326-460) uses a per-weapon PRIORITY field,
##    not damage: a weapon is cancelled if its priority <= the other's. [FACT]
##    NRCU projectiles have no priority data -> not implemented.

const HitFeel = preload("res://scripts/ssb_hit_feel.gd")
const FxScript = preload("res://scripts/ssb_fx.gd")

# ---- switches (default ON unless noted) -------------------------------------------
static var CLANK_ENABLED := true             # grounded melee vs grounded melee cancel (+-10 rule)
static var CLANK_REBOUND_ENABLED := true     # clanked grounded fighter is locked in a rebound slide
static var CLANK_HITLAG_ENABLED := true      # clanked fighters freeze int(dmg/3+5) f (also needs HitFeel.HITLAG_ENABLED)
static var CLANK_SPARK_ENABLED := true       # in-world SetOff spark at the contact point
static var PROJECTILE_CLANK_ENABLED := false # melee vs projectile (+-10). OFF: can_setoff per weapon is unknown ROM data
static var DEV_READOUT_ENABLED := true       # Dev Mode hit log lists clanks
static var CLANK_SFX := ""                   # res:// path; empty = silent (SSB has no clank-specific sfx in code)

# ---- constants -------------------------------------------------------------------------
const CLANK_MARGIN := 10.0          # [FACT] ftmain.c:2035,2046
const REBOUND_MUL := 1.62           # [FACT] ftmain.c:2021 (US)
const REBOUND_ADD := 4.0            # [FACT] ftmain.c:2021
const REBOUND_SLIDE_PER_TIMER := 2.0  # [FACT] ftcommonrebound.c:54 units/frame per rebound frame
const REBOUND_FRICTION_UF2 := 6.0   # [FACT] 4.0 normal floor * 1.5 Mario traction, units/frame^2
const SETOFF_SLOPE := 0.15          # [FACT] efmanager.c:3986
const LOGIC_HZ := 60.0
# [CAL] Body-scale metres per SSB unit for the rebound slide: 0.0045 makes a
# 10% clank slide ~0.6 m (SSB: ~136 u = ~0.43 Mario heights; NRCU fighters ~2 m,
# trimmed so fighters stay in poke range). Knockback's 0.0026 m/u (hit feel) is
# a launch-speed calibration, not a body scale, so it is not reused here.
const SLIDE_UNIT_M := 0.0045
const MAX_SLIDE_M := 1.2            # [CAL] 26% charged clanks would slide 3 m; cap so ledges stay safe-ish
const MAX_REBOUND_FRAMES := 50      # [CAL] synthetic huge damage cap (26% = 46 f is the real max)
# [CAL] NRCU fighters tick one after another; a strike reported last frame is
# still "live" for one frame so the later-ticking fighter can't win by order.
const LIVE_FRAMES := 1
# [CAL] Projectile hit radius when the node exposes none (projectile.gd mesh 0.28 m).
const DEFAULT_PROJECTILE_RADIUS := 0.28
# [CAL] Actor-range (cone) moves have no limb volume; their strike is a capsule
# from the chest out to 75% of the move's range, this thick.
const CONE_STRIKE_RADIUS := 0.35

static var _rec := {}     # actor instance id -> swing record
static var log_lines: Array[String] = []
static var last := {}     # last clank, for tests / Dev Mode

static func reset_all() -> void:
	_rec.clear()
	log_lines.clear()
	last = {}

static func _now() -> int:
	return Engine.get_physics_frames()

static func _seg_dist(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Array:
	var p: PackedVector3Array = Geometry3D.get_closest_points_between_segments(a, b, c, d)
	return [p[0].distance_to(p[1]), (p[0] + p[1]) * 0.5]

## Clank-rule result for (this damage, other damage): [this_clanks, other_clanks].
static func clank_result(this_damage: float, other_damage: float) -> Array:
	return [this_damage - CLANK_MARGIN < other_damage, other_damage - CLANK_MARGIN < this_damage]

static func rebound_frames(own_damage: float) -> int:
	return mini(int(own_damage * REBOUND_MUL + REBOUND_ADD), MAX_REBOUND_FRAMES)

## Initial slide speed (m/s) and per-second deceleration for a rebound.
static func rebound_slide(own_damage: float) -> Vector2:
	var timer := float(rebound_frames(own_damage))
	var decel := REBOUND_FRICTION_UF2 * SLIDE_UNIT_M * LOGIC_HZ * LOGIC_HZ
	var v0 := REBOUND_SLIDE_PER_TIMER * timer * SLIDE_UNIT_M * LOGIC_HZ
	v0 = minf(v0, sqrt(2.0 * decel * MAX_SLIDE_M))
	return Vector2(v0, decel)

static func spark_scale(dmg: float) -> float:
	return (1.0 - 0.05 * (10.0 - dmg)) if dmg < 10.0 else (1.0 + SETOFF_SLOPE * (dmg - 10.0))

## Report one active strike volume (sphere: a == b) of `actor`'s current move.
## Call it where the move tests its own hitbox, before delivering. `key`
## names the swing (move + string step); a new key or a gap starts a new swing.
static func strike(actor, key: String, a: Vector3, b: Vector3, radius: float, damage: float) -> void:
	if not CLANK_ENABLED and not PROJECTILE_CLANK_ENABLED: return
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree(): return
	var f := _now()
	var id: int = actor.get_instance_id()
	var rec: Dictionary = _rec.get(id, {})
	if rec.is_empty() or rec.key != key or f - int(rec.frame) > 1 + int(rec.pause):
		rec = {"actor": actor, "key": key, "frame": -10, "pause": 0, "samples": [], "prev": [], "prev_frame": -10, "damage": damage, "clanked": {}, "blocked": {}, "proj": {}, "grounded": false}
		_rec[id] = rec
	if int(rec.frame) != f:
		rec.prev = rec.samples
		rec.prev_frame = rec.frame
		rec.samples = []
		rec.frame = f
	rec.damage = damage
	rec.grounded = actor.is_grounded()
	var sample := [a, b, radius]
	rec.samples.append(sample)
	if float(actor.hitstun) > 0.0: return
	if CLANK_ENABLED and rec.grounded:
		for oid in _rec.keys():
			if oid == id: continue
			var o: Dictionary = _rec[oid]
			var other = o.actor
			if not is_instance_valid(other) or not other.is_inside_tree():
				_rec.erase(oid)
				continue
			if rec.clanked.has(oid) or o.clanked.has(id): continue
			if f - int(o.frame) > LIVE_FRAMES or not o.grounded: continue
			if float(other.hitstun) > 0.0 or other.counter_hitstop > 0: continue
			if not other.is_grounded(): continue
			if not actor.can_hit(other) or not other.can_hit(actor): continue
			var pool: Array = o.samples.duplicate()
			if int(o.prev_frame) >= f - LIVE_FRAMES: pool.append_array(o.prev)
			for s in pool:
				var hit: Array = _seg_dist(a, b, s[0], s[1])
				if float(hit[0]) <= radius + float(s[2]):
					_resolve(actor, rec, other, o, hit[1])
					break
	if PROJECTILE_CLANK_ENABLED:
		_projectiles(actor, rec, a, b, radius, damage)

static func _resolve(actor, rec: Dictionary, other, o: Dictionary, point: Vector3) -> void:
	rec.clanked[other.get_instance_id()] = true
	o.clanked[actor.get_instance_id()] = true
	var r := clank_result(float(rec.damage), float(o.damage))
	last = {"frame": _now(), "a": str(actor.character_id), "b": str(other.character_id), "a_damage": rec.damage, "b_damage": o.damage, "a_clanks": r[0], "b_clanks": r[1], "point": point, "a_key": rec.key, "b_key": o.key}
	if r[0]:
		rec.blocked[other.get_instance_id()] = rec.key
		_clank_fighter(actor, rec, other.global_position.x, float(rec.damage))
	if r[1]:
		o.blocked[actor.get_instance_id()] = o.key
		_clank_fighter(other, o, actor.global_position.x, float(o.damage))
	_spark(actor, point, maxf(float(rec.damage) if r[0] else 0.0, float(o.damage) if r[1] else 0.0))
	if DEV_READOUT_ENABLED:
		var line := "f%d CLANK P%s %s %.0f%%%s  vs  P%s %s %.0f%%%s" % [_now(), str(actor.player_index), str(actor.character_id), float(rec.damage), " (rebound)" if r[0] else " (wins)", str(other.player_index), str(other.character_id), float(o.damage), " (rebound)" if r[1] else " (wins)"]
		log_lines.push_front(line)
		if log_lines.size() > 4: log_lines.pop_back()

## One fighter's clanked hitbox: hitlag, then (grounded) the rebound lockout.
static func _clank_fighter(x, rec: Dictionary, other_x: float, own_damage: float) -> void:
	var lag := 0
	if CLANK_HITLAG_ENABLED and HitFeel.HITLAG_ENABLED:
		lag = mini(HitFeel.hitlag_frames(own_damage), HitFeel.HITLAG_MAX_FRAMES)
	rec.pause = lag + 1
	if CLANK_REBOUND_ENABLED and x.is_grounded():
		var frames := rebound_frames(own_damage)
		var slide := rebound_slide(own_damage)
		var away: float = -signf(other_x - x.global_position.x)
		if away == 0.0: away = -float(x.facing)
		x.hitstun = maxf(float(x.hitstun), frames / LOGIC_HZ)
		x.velocity.x = away * slide.x
		x.velocity.y = minf(x.velocity.y, 0.0)
		if x.hit_feel: x.hit_feel.clear()
		x.set_meta("ssb_rebound", {"frames": frames, "decel": slide.y, "away": away})
		# The move must stop, exactly like a hit cancels it. Deferred so a
		# controller that is mid-sweep this callback isn't torn down under itself.
		if x.has_method("cancel_for_clank"): x.call_deferred("cancel_for_clank")
	if lag > 0:
		x.begin_counter_hitstop(lag / LOGIC_HZ)
		if HitFeel.BUFFER_DURING_HITLAG: x.set_meta("ssb_hitlag", true)
	if x.has_signal("state_changed"): x.state_changed.emit()

static func _projectiles(actor, rec: Dictionary, a: Vector3, b: Vector3, radius: float, damage: float) -> void:
	for p in actor.get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(p) or p.is_queued_for_deletion() or not p.visible: continue
		var src = p.get("source")
		if src == actor or not is_instance_valid(src) or not actor.can_hit(src): continue
		var pid: int = p.get_instance_id()
		if rec.proj.has(pid): continue
		if p.has_method("damage_active") and not p.damage_active(): continue
		var pr: float = float(p.get("wave_radius")) if p.get("wave_radius") != null else DEFAULT_PROJECTILE_RADIUS
		var pd: float = float(p.payload_damage()) if p.has_method("payload_damage") else 11.0
		var pos: Vector3 = p.global_position
		var q := Geometry3D.get_closest_point_to_segment(pos, a, b)
		if q.distance_to(pos) > radius + pr: continue
		rec.proj[pid] = true
		var r := clank_result(damage, pd)
		last = {"frame": _now(), "a": str(actor.character_id), "projectile": str(p.name), "a_damage": damage, "p_damage": pd, "a_clanks": r[0], "p_clanks": r[1], "point": (q + pos) * 0.5}
		if r[1]:
			p.hide()
			p.queue_free()
		if r[0] and float(actor.hitstun) <= 0.0:
			_clank_fighter(actor, rec, pos.x, damage)
		_spark(actor, (q + pos) * 0.5, maxf(damage if r[0] else 0.0, pd if r[1] else 0.0))

static func _spark(actor, point: Vector3, dmg: float) -> void:
	if not CLANK_SPARK_ENABLED or not actor.is_inside_tree(): return
	var fx = FxScript.new()
	fx.setup_spark(Color(1.0, 1.0, 1.0), 0.26 * spark_scale(maxf(dmg, 1.0)), false)
	var host: Node = actor.get_parent() if actor.get_parent() else actor
	host.add_child(fx)
	point.z = 0.35
	fx.global_position = point
	if not CLANK_SFX.is_empty():
		preload("res://scripts/ssb_presentation.gd").play_sfx(actor, CLANK_SFX, point)

## Box / capsule / sphere query shape -> strike capsule [a, b, radius].
static func shape_volume(shape, point: Vector3, basis := Basis.IDENTITY) -> Array:
	if shape is BoxShape3D:
		var r := maxf(shape.size.y, shape.size.z) * 0.5
		var h := maxf(0.0, shape.size.x * 0.5 - r)
		return [point - basis.x * h, point + basis.x * h, r]
	if shape is CapsuleShape3D:
		var hc := maxf(0.0, shape.height * 0.5 - shape.radius)
		return [point - basis.y * hc, point + basis.y * hc, float(shape.radius)]
	if shape is SphereShape3D:
		return [point, point, float(shape.radius)]
	if shape is ConvexPolygonShape3D and shape.points.size() > 0:
		# [CAL] hull -> capsule along its longest AABB axis.
		var box := AABB(shape.points[0], Vector3.ZERO)
		for v in shape.points: box = box.expand(v)
		var c: Vector3 = point + basis * box.get_center()
		var ax := box.get_longest_axis_index()
		var r := 0.0
		for i in 3:
			if i != ax: r = maxf(r, box.size[i] * 0.5)
		var dir := Vector3.ZERO; dir[ax] = 1.0
		var hl := maxf(0.0, box.size[ax] * 0.5 - r)
		return [c - basis * dir * hl, c + basis * dir * hl, r]
	return [point, point, 0.3]

## Fighter.receive_hit / receive_contact_hit gate. True = this hit came from a
## swing that clanked against this target and must not land.
static func blocks(target, source) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target): return false
	var rec: Dictionary = _rec.get(source.get_instance_id(), {})
	if rec.is_empty(): return false
	var key = rec.blocked.get(target.get_instance_id())
	return key != null and key == rec.key and _now() - int(rec.frame) <= 1

## Hitstun-lane step while rebounding: SSB ground friction on the slide.
static func rebound_step(actor, delta: float) -> void:
	if not actor.has_meta("ssb_rebound"): return
	var m = actor.get_meta("ssb_rebound")
	if not actor.is_grounded() or float(actor.hitstun) <= 0.0:
		# Slid off a ledge or finished: hand back to normal control/air physics.
		if float(actor.hitstun) <= 0.0 or not actor.is_grounded(): actor.remove_meta("ssb_rebound")
		if float(actor.hitstun) > 0.0 and not actor.is_grounded(): actor.hitstun = 0.0
		return
	actor.velocity.x = move_toward(actor.velocity.x, 0.0, float(m.decel) * delta)
	if float(actor.hitstun) - delta <= 0.0: actor.remove_meta("ssb_rebound")  # last rebound tick

## A real hit replaces a rebound (SSB: damage branch wins).
static func on_real_hit(actor) -> void:
	if actor.has_meta("ssb_rebound"): actor.remove_meta("ssb_rebound")

static func is_rebounding(actor) -> bool:
	return is_instance_valid(actor) and actor.has_meta("ssb_rebound") and float(actor.hitstun) > 0.0

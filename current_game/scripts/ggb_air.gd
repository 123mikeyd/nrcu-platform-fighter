extends Node
#   neutral air  GUMMY SPIN  - full-body barrel spin, wings flared, hits all around the body.
#   up air       BUMP        - squash then hard upward stretch; the top of the body bonks up.
#   down air     STINGER     - stinger needle stabs straight down; SSB-style meteor (spike).
# All timings/damage/radii are review values [CAL], not ROM data. Native mesh/material untouched:
# poses are rebuilt from sync_pose every tick and applied as a pivot transform like Wing Gust.
const HURT = preload("res://scripts/body_hurtboxes.gd")
const CLANK = preload("res://scripts/ssb_clank.gd")
const MOVES := {
	"spin":    {"label": "GUMMY SPIN",  "dur": 0.42, "on": 0.07, "off": 0.28, "dmg": 9.0,  "push": 4.0, "land": 0.15},
	"bump":    {"label": "BUMP",        "dur": 0.36, "on": 0.09, "off": 0.17, "dmg": 8.0,  "push": 4.3, "land": 0.10},
	"stinger": {"label": "STINGER",     "dur": 0.52, "on": 0.12, "off": 0.26, "dmg": 11.0, "push": 3.6, "land": 0.22},
}
const SPIN_RADIUS := 1.05  # body + flared wings; 0.95 missed a Teknium touching GGB's front, 1.05 lands both sides [CAL]
const BUMP_RADIUS := 0.50  # capsule from upper body to above the head
const STING_RADIUS := 0.24  # capsule along the needle, from belly to tip
var actor
var view
var cues
var kind := ""
var active := false
var elapsed := 0.0
var attack_facing := 1.0
var targets: Array = []
var contacts: Array = []
var last_landing_lag := 0.0

func _ready() -> void:
	actor = get_parent()
	view = actor.get_node("VisualRoot/GGBVisual")
	cues = preload("res://scripts/ggb_cues.gd").new()
	cues.name = "GGBAirCues"
	actor.add_child(cues)

## Returns false when this aim is not an air-kit slot (side air stays Short Sting).
static func handles(aim: Vector2) -> bool:
	return absf(aim.y) > 0.1 or absf(aim.x) <= 0.1

func start(aim: Vector2) -> void:
	cancel()
	kind = "spin"
	if aim.y < -0.1: kind = "bump"
	elif aim.y > 0.1: kind = "stinger"
	if absf(aim.x) > 0.1: actor.facing = signf(aim.x)
	attack_facing = actor.facing
	active = true
	elapsed = 0.0
	targets.clear()
	actor.attack_cooldown = MOVES[kind].dur
	actor.last_move = MOVES[kind].label
	actor.attack_flash_time = 0
	if actor._attack_flash: actor._attack_flash.visible = false

func invalid() -> bool:
	return not actor.controls_enabled or actor.stocks <= 0 or actor.hitstun > 0 or actor.freeze_remaining > 0 or actor.magic_locked() or actor.drop_committed or (actor.tumble and actor.tumble.active) or (actor.revival and actor.revival.phase != "idle")

func before_tick() -> void:
	if active and invalid(): cancel()

func cancel() -> void:
	active = false
	elapsed = 0.0
	targets.clear()
	if is_instance_valid(cues): cues.hide_all()

func tick(delta: float) -> void:
	if not active: return
	if invalid(): cancel(); return
	if actor.is_grounded() and actor.velocity.y <= 0.0:
		# SSB-style aerial landing: the move is cut and costs its own landing lag.
		var lag: float = MOVES[kind].land
		cancel()
		actor.attack_cooldown = 0.0
		actor.landing_lag = maxf(actor.landing_lag, lag)
		last_landing_lag = lag
		return
	elapsed += delta
	if elapsed >= MOVES[kind].dur: cancel(); return
	cues.hide_all()
	present()
	var m: Dictionary = MOVES[kind]
	if elapsed >= m.on and elapsed <= m.off:
		var c: Vector3 = view.body_center_world()
		match kind:
			"spin":
				var sc := Vector3(actor.global_position.x, c.y, c.z)  # symmetric front/back (view yaw shifts c.x)
				query(sc, sc, SPIN_RADIUS)
			"bump": query(c, c + Vector3.UP * 0.50, BUMP_RADIUS, c + Vector3.UP * 0.05)
			"stinger": query(c, c + Vector3.DOWN * (0.45 + 0.40 * _sting_ext()), STING_RADIUS, c + Vector3.DOWN * 0.25)

func _sting_ext() -> float:
	if elapsed < 0.10: return 0.0
	if elapsed < 0.16: return smoothstep(0.10, 0.16, elapsed)
	if elapsed < 0.28: return 1.0
	return 1.0 - smoothstep(0.28, 0.38, elapsed)

func _pivot(basis: Basis, lift := Vector3.ZERO) -> void:
	var pivot: Vector3 = view.body_center_world()
	var g: Transform3D = view.model.global_transform
	g = Transform3D(basis, pivot - basis * pivot) * g
	g.origin += lift
	view.model.global_transform = g

func _wings(amount: float) -> void:
	for i in view.wings.size():
		var side: float = -1.0 if i == 0 else 1.0
		view.wings[i].rotation.z = side * amount

func present() -> void:
	view.rotation.y = attack_facing * 0.48
	match kind:
		"spin":
			var t := smoothstep(0.05, 0.30, elapsed)
			var wind := sin(clampf(elapsed / 0.05, 0.0, 1.0) * PI) * 0.12
			_wings(0.25 + 0.75 * sin(clampf((elapsed - 0.03) / 0.33, 0.0, 1.0) * PI))
			var spin := Basis(Vector3.BACK, -attack_facing * TAU * t)
			_pivot(spin * Basis.from_scale(Vector3(1.0 + wind, 1.0 - wind, 1.0)))
		"bump":
			var sx := 1.0; var sy := 1.0; var lift := 0.0
			if elapsed < 0.08:
				var s := sin(clampf(elapsed / 0.08, 0.0, 1.0) * PI * 0.5)
				sx = 1.0 + 0.18 * s; sy = 1.0 - 0.22 * s
			elif elapsed < 0.16:
				var s := smoothstep(0.08, 0.13, elapsed)
				sx = lerpf(1.18, 0.82, s); sy = lerpf(0.78, 1.38, s); lift = 0.22 * s
			else:
				var k := (elapsed - 0.16) / 0.20
				var wob := cos(k * TAU * 1.5) * exp(-4.0 * k)
				sx = 1.0 - 0.18 * wob; sy = 1.0 + 0.38 * wob; lift = 0.22 * maxf(wob, 0.0)
			_wings(0.7 if elapsed < 0.2 else 0.3)
			_pivot(Basis.from_scale(Vector3(sx, sy, sx)), Vector3.UP * lift)
		"stinger":
			var e := _sting_ext()
			var tuck := sin(clampf(elapsed / 0.10, 0.0, 1.0) * PI * 0.5) if elapsed < 0.10 else 1.0 - 0.6 * e
			var pitch := Basis(Vector3.BACK, attack_facing * 0.35 * tuck)
			_wings(0.2 + 0.6 * e)
			_pivot(pitch * Basis.from_scale(Vector3(1.0 - 0.08 * e, 1.0 + 0.10 * e, 1.0)), Vector3.DOWN * 0.10 * e)
			if e > 0.02:
				var c: Vector3 = view.body_center_world()
				cues.needle.visible = true
				cues.needle.rotation = Vector3(0, 0, -PI * 0.5)
				cues.needle.scale = Vector3(0.6 + 0.6 * e, 1.25, 1.0)
				cues.needle.global_position = c + Vector3(0, -(0.45 + 0.40 * e) + 0.18, 0.12)

func query(origin: Vector3, point: Vector3, radius: float, from := Vector3.INF) -> void:
	# Sphere at `point`, or a capsule from `from` to `point` when `from` is given.
	var a: Vector3 = point if from == Vector3.INF else from
	CLANK.strike(actor, "ggb_air:" + kind, a, point, radius, float(MOVES[kind].dmg))  # aerials never clank (both must be grounded); kept for consistency
	var space = actor.get_world_3d().direct_space_state
	if origin.distance_to(point) > 0.01:
		var ray = PhysicsRayQueryParameters3D.create(origin, point, 2); ray.exclude = [actor.get_rid()]
		if not space.intersect_ray(ray).is_empty(): return
	var q = PhysicsShapeQueryParameters3D.new()
	var mid: Vector3 = (a + point) * 0.5
	var length: float = a.distance_to(point)
	if length < 0.01:
		var s = SphereShape3D.new(); s.radius = radius; q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, point)
	else:
		var cap = CapsuleShape3D.new(); cap.radius = radius; cap.height = length + 2.0 * radius; q.shape = cap
		var up: Vector3 = (point - a).normalized()
		var basis := Basis(Quaternion(Vector3.UP, up)) if absf(up.dot(Vector3.UP)) < 0.999 else (Basis.IDENTITY if up.y > 0 else Basis(Vector3.RIGHT, PI))
		q.transform = Transform3D(basis, mid)
	q.collision_mask = 7; q.margin = 0
	HURT.prepare(actor, q)
	var hits = space.intersect_shape(q, 64)
	for hit in hits:
		var target = HURT.resolve(hit.collider)
		if not actor.can_hit(target) or target in targets: continue
		targets.append(target)
		var launch := Vector3.ZERO
		match kind:
			"spin":
				var away: float = signf(target.global_position.x - actor.global_position.x)
				if away == 0.0: away = attack_facing
				launch = Vector3(away, 0.55, 0)
			"bump": launch = Vector3(attack_facing * 0.15, 1.0, 0)
			"stinger": launch = Vector3(attack_facing * 0.10, -1.0, 0)  # meteor
		contacts.append({"kind": kind, "time": elapsed, "point": point, "target": str(target.name), "launch": launch})
		cues.spark.visible = true; cues.spark.global_position = point + Vector3(0, 0, 0.15); cues.spark.scale = Vector3.ONE * 0.3
		hit.position = point
		HURT.deliver(target, MOVES[kind].dmg, launch, MOVES[kind].push, hit, actor)

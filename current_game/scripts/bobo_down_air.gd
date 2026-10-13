extends Node
# assets/bobo/player_down_air.res (tools/import_bobo_down_air.gd). Manually sampled like the other player clips.
# Phases (Blender frame f at clip time f/30; move elapsed e = (f - 1)/30):
#   f1 air idle, f2-14 wind-up/hang/overhead swing, f15-17 ACTIVE (claws swing down to straight-down lock = spike),
#   f17-~26 front flip (no hitbox), ~26-34 jet stabilize (Blender-only thruster meshes are NOT installed), 35-41 settle
# Hit geometry = the measured >65% hand-weighted claw hulls already used by the side claws (thrust_slash.json),
# placed on the live DownAir pose; no extra reach. Sampled every 1/240 s of clip time through the active window.
# All numbers below are provisional review values [CAL], modelled on GGB's Stinger (11%, push 3.6, land 0.22 s).
const HURT = preload("res://scripts/body_hurtboxes.gd")
const CLANK = preload("res://scripts/ssb_clank.gd")
const CLIP := "DownAir"
const KEY0 := 1.0 / 30.0           # clip time of Blender frame 1
const DURATION := 40.0 / 30.0      # f1 -> f41 (1.33 s)
const ACTIVE_START := 14.0 / 30.0  # f15
const ACTIVE_END := 16.0 / 30.0    # f17 claws-down lock; the flip starts on the next frame
const DAMAGE := 12.0               # [CAL] heavier, slower cousin of GGB Stinger (11)
const PUSH := 3.8                  # [CAL] Stinger 3.6
const LAUNCH := Vector2(0.15, -1.0)  # [CAL] meteor, ~81 deg below horizontal toward his facing
const LANDING_LAG := 0.30          # [CAL] 18 frames; Stinger 0.22, Bobo is the bigger commitment
const BLEND_IN := 0.05             # from whatever air pose was showing into f1
var actor
var active := false
var elapsed := 0.0
var attack_facing := 1.0
var targets: Array = []
var contacts: Array = []
var last_landing_lag := 0.0
var serial := 0

func _ready() -> void:
	actor = get_parent()

func view():
	return actor._visual_root.get_node("BoboVisual")

func allowed() -> bool:
	var a = actor
	return a.controls_enabled and a.stocks > 0 and a.hitstun <= 0 and a.freeze_remaining <= 0 and not a.magic_locked() \
		and not (a.tumble and a.tumble.active) and (not a.revival or a.revival.phase == "idle") \
		and not is_instance_valid(a.caught_by) and not (a.ledge_grab and a.ledge_grab.active())

func start() -> bool:
	var a = actor
	if active or not allowed() or a.is_grounded(): return false
	if a.attack_cooldown > 0 or a.landing_lag > 0 or a.counter_hitstop > 0: return false
	if not a.special_move.is_empty() or a.thrust_active or a.down_a_active: return false
	active = true
	elapsed = 0.0
	serial += 1
	attack_facing = a.facing
	targets.clear()
	a.attack_cooldown = DURATION
	a.last_move = "CLAW HAMMER DROP"
	var v = view()
	v.cancel_locomotion()
	v.begin_down_air()
	present()
	return true

func cancel() -> void:
	if not active: return
	active = false
	elapsed = 0.0
	targets.clear()
	actor.attack_cooldown = 0.0

func in_flip() -> bool:
	return active and elapsed > ACTIVE_END

func present() -> void:
	var v = view()
	actor.facing = attack_facing
	v.model.rotation.y = attack_facing * PI / 2
	v.present_down_air(KEY0 + clampf(elapsed, 0.0, DURATION), elapsed)

func tick(delta: float) -> void:
	if not active: return
	if not allowed(): cancel(); return
	if actor.is_grounded() and actor.velocity.y <= 0.0:
		# SSB-style aerial landing: the move (flip included) is cut and costs its own landing lag.
		cancel()
		actor.landing_lag = maxf(actor.landing_lag, LANDING_LAG)
		last_landing_lag = LANDING_LAG
		var v = view()
		v.airborne = true  # next locomotion tick plays the approved JumpLand
		v.landing = -1.0
		return
	var start_t := elapsed
	var end_t := minf(start_t + delta, DURATION)
	var lo := maxf(start_t, ACTIVE_START)
	var hi := minf(end_t, ACTIVE_END)
	if hi >= lo:
		var steps := maxi(1, ceili((hi - lo) * 240.0 - 0.00001))
		for step in range(steps + 1):
			elapsed = lerpf(lo, hi, float(step) / steps)
			present()
			query()
			if not active: return
	elapsed = end_t
	actor.attack_cooldown = maxf(DURATION - elapsed, 0.0)
	present()
	if elapsed >= DURATION:
		cancel()
		view().begin_air_idle()

func query() -> void:
	if not active or elapsed < ACTIVE_START - 0.000001 or elapsed > ACTIVE_END + 0.000001: return
	var v = view()
	var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
	var space = actor.get_world_3d().direct_space_state
	for event in actor.thrust_manifest.hits:
		var transform: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(str(event.bone)))
		var world := PackedVector3Array()
		var mean_z := 0.0
		for p in event.hull_points:
			var w: Vector3 = transform * Vector3(p[0], p[1], p[2])
			world.append(w)
			mean_z += w.z
		mean_z /= maxf(1.0, world.size())
		# Depth collapse: the abducted arms put each claw ~0.9 m in front of / behind the fight plane (z), so the
		# side-view spike would straddle a target directly below. Re-centre each hull on the plane, keeping its
		# own thickness and its exact x/y silhouette (no reach added in the camera's view).
		var points := PackedVector3Array()
		for w in world: points.append(Vector3(w.x, w.y, w.z - mean_z + actor.global_position.z) - actor.global_position)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, actor.global_position)
		q.collision_mask = 1 | 4
		q.exclude = [actor.get_rid()]
		q.margin = 0
		var cv: Array = CLANK.shape_volume(shape, actor.global_position)
		CLANK.strike(actor, "bobo:down_air:" + str(event.bone), cv[0], cv[1], cv[2], DAMAGE)  # aerials never clank; kept for consistency
		HURT.prepare(actor, q)
		var hits = space.intersect_shape(q, 32)
		for result in hits:
			var target = HURT.resolve(result.collider)
			if not actor.can_hit(target) or target in targets: continue
			targets.append(target)
			var contact = HURT.shape_contact(space, q, result, hits)
			var launch := Vector3(attack_facing * LAUNCH.x, LAUNCH.y, 0)
			contacts.append({"time": elapsed, "frame": 1.0 + elapsed * 30.0, "bone": str(event.bone), "target": str(target.name), "launch": launch, "point": contact.get("position", Vector3.INF)})
			HURT.deliver(target, DAMAGE, launch, PUSH, contact, actor)
			if not active: return

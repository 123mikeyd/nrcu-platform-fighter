extends RefCounted
## Detached finite pressure pulse; never owns a Node or autonomous clock.
const TTL := .9
const FADE_START := .65
const MAX_RANGE := 4.86
const START_SPEED := 9.0
const END_SPEED := 1.8
const START_RADIUS := .45
const END_RADIUS := .85
const HALF_DEPTH := .34
var activation_id := ""
var source := -1
var team := -1
var facing := 1.0
var position := Vector3.ZERO
var age := 0.0
var distance := 0.0
var speed := START_SPEED
var radius := START_RADIUS
var opacity := .8
var active := false

func start(id: String, owner: int, owner_team: int, origin: Vector3, direction: float) -> bool:
	if active or id.is_empty(): return false
	activation_id = id
	source = owner
	team = owner_team
	position = origin
	facing = direction
	age = 0.0
	distance = 0.0
	speed = START_SPEED
	radius = START_RADIUS
	opacity = .8
	active = true
	return true

func tick(delta: float, context: Dictionary = {}) -> Array:
	if not context.get("owner_valid", true) or not context.get("owner_enabled", true): cancel()
	if not active or delta <= 0 or not context.get("advance", true) or context.get("paused", false) or context.get("hitstop", false): return []
	var step := minf(delta, TTL - age)
	var old_speed := speed
	age = minf(TTL, age + step)
	speed = lerpf(START_SPEED, END_SPEED, age / TTL)
	radius = lerpf(START_RADIUS, END_RADIUS, age / TTL)
	opacity = .8 * clampf((TTL-age)/(TTL-FADE_START),0,1)
	var travel := minf((old_speed + speed) * .5 * step, MAX_RANGE-distance)
	distance += travel
	var motion := Vector3(facing * travel,0,0)
	if context.get("space") != null:
		var contact := _sweep(context.space, motion, context.get("targets", []), context.get("collision_mask", 0xFFFFFFFF))
		if not contact.is_empty():
			cancel()
			return [contact]
	position += motion
	if age >= TTL - .000001 or distance >= MAX_RANGE: cancel()
	return []

func _eligible(target: Dictionary) -> bool:
	var target_team: int = target.get("team", -1)
	return target.id != source and target.get("eligible", true) and (team < 0 or target_team < 0 or team != target_team)

func _sweep(space: PhysicsDirectSpaceState3D, motion: Vector3, targets: Array, mask: int) -> Dictionary:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = HALF_DEPTH * 2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.margin = .001
	query.collision_mask = mask
	var offset := Vector3(facing * .15,0,0)
	query.transform = Transform3D(Basis(Vector3.FORWARD, PI/2), position + offset)
	var by_body: Dictionary = {}
	var excluded: Array[RID] = []
	var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
	var generated_hit := {}; var generated_target := {}
	for target in targets:
		var body: CollisionObject3D = target.body
		if not is_instance_valid(body): continue
		by_body[body.get_instance_id()] = target
		if not _eligible(target) or age >= FADE_START: excluded.append(body.get_rid())
		elif recipient.generated(target):
			excluded.append(body.get_rid())
			var contact: Dictionary = recipient.cylinder_sweep(target,position+offset,motion.x,radius,HALF_DEPTH)
			if not contact.is_empty() and (generated_hit.is_empty() or contact.t < generated_hit.t or (contact.t == generated_hit.t and target.id < generated_target.id)):
				generated_hit = contact; generated_target = target
	query.exclude = excluded
	var limit := maxi(32, targets.size() + 32)
	var hits := space.intersect_shape(query, limit)
	var native_t := 0.0
	if hits.is_empty():
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions[0] >= 1.0:
			if generated_hit.is_empty(): return {}
			position += motion*generated_hit.t
			return recipient.annotate(_target_contact(generated_target),generated_target,generated_hit)
		native_t = fractions[0]
		query.transform.origin += motion * minf(1.0, fractions[1] + .002)
		query.motion = Vector3.ZERO
		hits = space.intersect_shape(query, limit)
	if not generated_hit.is_empty() and generated_hit.t < native_t:
		position += motion*generated_hit.t
		return recipient.annotate(_target_contact(generated_target),generated_target,generated_hit)
	position = query.transform.origin - offset
	var event := {"kind":"terrain", "source":source, "activation_id":activation_id, "position":position}
	# Physics result order is unspecified. Terrain beats fighters at contact.
	var contacts: Array = []
	for hit in hits:
		if not by_body.has(hit.collider_id): return event
		contacts.append(by_body[hit.collider_id])
	contacts.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	for target in contacts:
		if not _eligible(target) or age >= FADE_START: continue
		return _target_contact(target)
	return event

func _target_contact(target: Dictionary) -> Dictionary:
	var event := {"source":source,"activation_id":activation_id,"position":position,"victim":target.id,"hit_ordinal":0}
	if target.get("absorbing",false):
		event.kind = "absorb"; event.payload_damage = 11.0
	elif target.get("shielding",false):
		event.kind = "shield_absorb"; event.damage = 0.0
	else:
		event.kind = "hit"; event.damage = 11.0; event.base_knockback = 4.5; event.direction = Vector3(facing,.2,0)
	return event

func reflect(new_source: int, new_team: int) -> bool:
	if not active: return false
	source = new_source
	team = new_team
	facing *= -1
	return true

func cancel() -> void:
	active = false

func snapshot() -> Dictionary:
	return {"activation_id":activation_id, "source":source, "team":team, "facing":facing, "position":position, "age":age, "remaining":TTL-age, "distance":distance, "speed":speed, "radius":radius, "opacity":opacity, "active":active, "damage_active":active and age < FADE_START}

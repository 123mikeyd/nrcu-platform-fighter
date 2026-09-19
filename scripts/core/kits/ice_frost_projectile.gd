extends RefCounted
## Detached caller-ticked source projectile. Returns values; owns no scene nodes.
const TTL := 1.6
const SPEED := 15.0
var activation_id := ""
var source := -1
var team := -1
var facing := 1.0
var position := Vector3.ZERO
var age := 0.0
var remaining := TTL
var active := false
func start(id: String, owner: int, owner_team: int, origin: Vector3, direction: float) -> bool:
	if active or id.is_empty(): return false
	activation_id = id
	source = owner
	team = owner_team
	position = origin
	facing = direction
	age = 0
	remaining = TTL
	active = true
	return true
func _eligible(target: Dictionary) -> bool:
	var other_team: int = target.get("team",-1)
	return target.id != source and target.get("eligible",true) and (team < 0 or other_team < 0 or team != other_team)
func tick(delta: float, context: Dictionary = {}) -> Array:
	if not context.get("owner_valid",true) or not context.get("owner_enabled",true): cancel()
	# Actor hitstop is intentionally NOT a detached projectile clock gate.
	if not active or delta <= 0 or context.get("paused",false) or not context.get("advance",true): return []
	age += delta
	remaining -= delta
	if remaining <= 0:
		cancel()
		return []
	var end := position + Vector3(facing*SPEED*delta,0,0)
	var targets: Array = context.get("targets",[])
	var by_body := {}
	var excluded: Array[RID] = []
	for target in targets:
		var body: CollisionObject3D = target.get("body")
		if is_instance_valid(body):
			by_body[body.get_instance_id()] = target
			if not _eligible(target): excluded.append(body.get_rid())
	if context.get("space") != null:
		var query := PhysicsRayQueryParameters3D.create(position,end,context.get("collision_mask",0xFFFFFFFF),excluded)
		var contact: Dictionary = context.space.intersect_ray(query)
		if not contact.is_empty():
			position = contact.position
			cancel()
			if by_body.has(contact.collider_id) and _eligible(by_body[contact.collider_id]): return [_hit(by_body[contact.collider_id])]
			return [{"kind":"terrain","source":source,"activation_id":activation_id,"position":position}]
	# Preserve original unsynchronized-body fallback AFTER the actual stage ray.
	var nearest := {}
	var nearest_distance := INF
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary): return a.id < b.id)
	for target in ordered:
		if not _eligible(target): continue
		var center: Vector3 = target.position + Vector3.UP
		var closest := Geometry3D.get_closest_point_to_segment(center,position,end)
		var distance := position.distance_to(closest)
		if center.distance_to(closest) <= .75 and distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	if not nearest.is_empty():
		cancel()
		return [_hit(nearest)]
	position = end
	return []
func _hit(target: Dictionary) -> Dictionary:
	var event := {"kind":"hit","source":source,"victim":target.id,"activation_id":activation_id,"hit_ordinal":0,"position":position}
	if target.get("absorbing",false):
		event.kind = "absorb"
		event.payload_damage = 4.0
		return event
	event.damage = 4.0
	event.base_knockback = 1.0
	event.direction = Vector3(facing,.2,0)
	# Atomic hit extension: shared host must apply AFTER accepted damage/shatter.
	# Do not pre-evaluate victim freeze/immunity: that would miss shatter immunity.
	event.status_requests = [] if target.get("shielding",false) else [{"kind":"freeze","source":source,"victim":target.id,"activation_id":activation_id,"hit_ordinal":0,"duration":1.0,"immunity":1.0,"order":"after_damage","requires_accepted_hit":true}]
	return event
func reflect(new_source: int, new_team: int) -> bool:
	if not active: return false
	source = new_source
	team = new_team
	facing *= -1
	remaining = maxf(remaining,.8)
	return true
func expire_source(owner: int) -> void:
	if source == owner: cancel()
func cancel() -> void:
	active = false
func snapshot() -> Dictionary:
	return {"kind":"frost_bolt","activation_id":activation_id,"source":source,"team":team,"facing":facing,"position":position,"age":age,"remaining":remaining,"active":active,"damage_active":active,"reflectable":active}

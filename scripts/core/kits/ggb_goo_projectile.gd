extends RefCounted
## Goo's source ray, not the generic projectile's unsynchronized sphere fallback.
const TTL := 1.5
const THROW_SPEED := 5.5
const LIFT := 3.4
const GRAVITY := 18.0
const MAX_TRAVEL := 4.5
var activation_id := ""
var source := -1
var team := -1
var facing := 1.0
var position := Vector3.ZERO
var age := 0.0
var remaining := TTL
var fall_speed := LIFT
var travel := 0.0
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
	fall_speed = LIFT
	travel = 0
	active = true
	return true
func _eligible(target: Dictionary) -> bool:
	var other_team: int = target.get("team",-1)
	return target.id != source and target.get("eligible",true) and (team < 0 or other_team < 0 or team != other_team)
func tick(delta: float, context: Dictionary = {}) -> Array:
	if not context.get("owner_valid",true) or not context.get("owner_enabled",true) or context.get("owner_stocks",1) <= 0: cancel()
	if not active or delta <= 0 or context.get("paused",false) or not context.get("advance",true): return []
	remaining -= delta
	if remaining <= 0:
		cancel()
		return []
	age += delta
	fall_speed -= GRAVITY*delta
	var step := minf(THROW_SPEED*delta,maxf(0,MAX_TRAVEL-travel))
	travel = minf(MAX_TRAVEL,travel+step)
	var end := position+Vector3(facing*step,fall_speed*delta,0)
	var by_body := {}
	var excluded: Array[RID] = []
	for target in context.get("targets",[]):
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
			if by_body.has(contact.collider_id):
				return [_hit(by_body[contact.collider_id])]
			var event := {"kind":"terrain","source":source,"team":team,"activation_id":activation_id,"position":position}
			if fall_speed < 0 and contact.normal.y > .6:
				event.kind = "spawn_puddle"
				event.surface = contact.collider
				event.normal = contact.normal
				event.position = position+Vector3.UP*.025
			return [event]
	position = end
	return []
func _hit(target: Dictionary) -> Dictionary:
	var event := {"kind":"hit","source":source,"victim":target.id,"activation_id":activation_id,"hit_ordinal":0,"position":position}
	if target.get("absorbing",false):
		event.kind = "absorb"
		event.payload_damage = 11.0
	else:
		event.damage = 11.0
		event.base_knockback = 4.5
		event.direction = Vector3(facing,.2,0)
	return event
func reflect(new_source: int, new_team: int) -> bool:
	if not active: return false
	source = new_source
	team = new_team
	facing *= -1
	return true
func expire_source(owner: int) -> void:
	if source == owner: cancel()
func cancel() -> void:
	active = false
func snapshot() -> Dictionary:
	return {"kind":"sticky_goo","source":source,"team":team,"activation_id":activation_id,"position":position,"facing":facing,"age":age,"remaining":remaining,"travel":travel,"fall_speed":fall_speed,"active":active,"damage_active":active,"reflectable":active}

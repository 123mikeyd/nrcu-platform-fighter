extends RefCounted
## Match-owned RISING STRIKE activation, never a body/velocity writer.
const UP_THRESHOLD := Vector2(0, -0.1) # Match InputFrame component precision.
const ACTIVE_SECONDS := 0.38
const ACTIVE_TICKS := 23 # ceil(.38 * 60); final decrement still queries.
const COOLDOWN_SECONDS := 0.65
const COOLDOWN_TICKS := 39
const BOX_UPPER := Vector3(1.3, 2.6, 1.0)
const BOX_LOWER := Vector3(-1.3, -0.4, -1.0)
var age: int = 0
var victims: Dictionary = {}
var facing: float
var activation_id: String
func _init(direction: float, identity: String) -> void:
	facing = direction
	activation_id = identity
func advance() -> void:
	age += 1
func contains(offset: Vector3) -> bool:
	return absf(offset.x) < BOX_UPPER.x and absf(offset.z) < BOX_UPPER.z and offset.y > BOX_LOWER.y and offset.y < BOX_UPPER.y
func contact(source: int, victim: int, offset: Vector3, tick: int, target: Dictionary = {}, origin: Vector3 = Vector3.ZERO) -> Dictionary:
	if victims.has(victim): return {}
	var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
	var hit := {}
	if recipient.generated(target):
		hit = recipient.box(target,origin,BOX_LOWER,BOX_UPPER)
		if hit.is_empty(): return {}
	elif not contains(offset): return {}
	victims[victim] = true
	return recipient.annotate({"source": source, "victim": victim, "activation_id": activation_id, "tick": tick, "damage": 12.0, "base_knockback": 5.5, "direction": Vector3(facing * 0.2, 1, 0)},target,hit)

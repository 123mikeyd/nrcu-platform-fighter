extends RefCounted
## Force-only clock, detached from rendering and the legacy combined magic node.
const CONTACT = preload("res://data/contact/force_event.tres")
const EVENT_TICKS := 15
const END_TICKS := 60
const COOLDOWN_TICKS := 75
var age := 0
var facing := 1.0
var activation_id := ""
func _init(direction: float, identity: String):
	facing = direction
	activation_id = identity
func advance() -> bool:
	age += 1
	return age == EVENT_TICKS
func origin(at: Vector3) -> Vector3:
	return at + Basis(Vector3.UP, facing * PI / 2) * CONTACT.get_meta("model_hand") * 1.25
static func source_time(seconds: float) -> float:
	return seconds * (16.0 / 24.0) / 0.25 if seconds <= 0.25 else 16.0 / 24.0 + seconds - 0.25

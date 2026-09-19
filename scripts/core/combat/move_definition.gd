extends Resource
## Authoring definition only; match snapshots Resources, never stores mutable victims here.
@export var move_id: String = "SIDE STRIKE"
@export var damage: float = 8.0
@export var base_knockback: float = 3.8
@export var cooldown_seconds: float = 0.32
func cooldown_ticks() -> int:
	return ceili(cooldown_seconds * 60.0)
@export var query_axis: Vector3 = Vector3.RIGHT
func query_direction(facing: float) -> Vector3:
	return Vector3(query_axis.x * facing, query_axis.y, query_axis.z).normalized()
func launch_direction(facing: float) -> Vector3:
	var direction := query_direction(facing)
	if absf(direction.y) < 0.5: direction.y = 0.35
	return direction
func contains(offset: Vector3, facing: float) -> bool:
	return absf(offset.z) < 1.5 and offset.length() <= 2.5 and offset.normalized().dot(query_direction(facing)) > Vector3(0.4, 0, 0).x

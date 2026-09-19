extends Resource
## Explicit stage-authored world-space foot-origin geometry. Never infer from meshes.
@export var anchor_id: String = ""
## Outward side: -1 left edge, +1 right edge. Stage interior is opposite.
@export_enum("Left:-1", "Right:1") var outward: int = -1
@export var edge: Vector3 = Vector3.ZERO
@export var hang_offset: Vector3 = Vector3(0.65, -1.5, 0)
@export var climb_offset: Vector3 = Vector3(-0.7, 0.06, 0)
@export var approach_width: float = 1.4
@export var approach_depth: float = 0.5
@export var min_foot_y: float = -1.8
@export var max_foot_y: float = -0.4
func hang(snapshot: Dictionary = {}) -> Vector3:
	var offset := hang_offset
	var body: Dictionary = snapshot.get("body", {})
	if not body.is_empty():
		if not is_equal_approx(body.radius, 0.4): offset.x += body.radius - 0.4
		if not is_equal_approx(body.height, 1.8): offset.y -= body.height - 1.8
	return edge + Vector3(outward * offset.x - body.get("center", Vector3.ZERO).x, offset.y, offset.z)
func climb(snapshot: Dictionary = {}) -> Vector3:
	var offset := climb_offset
	var body: Dictionary = snapshot.get("body", {})
	if not body.is_empty() and not is_equal_approx(body.radius, 0.4): offset.x -= body.radius - 0.4
	return edge + Vector3(outward * offset.x - body.get("center", Vector3.ZERO).x, offset.y, offset.z)
func eligible(snapshot: Dictionary) -> bool:
	if anchor_id.is_empty() or abs(outward) != 1: return false
	var d: Vector3 = snapshot.position - edge
	var v: Vector3 = snapshot.velocity
	return not snapshot.get("grounded", false) and v.y <= 0 and v.x * outward < 0 and d.x * outward > 0 and d.x * outward <= approach_width and d.y >= min_foot_y and d.y <= max_foot_y and abs(d.z) <= approach_depth

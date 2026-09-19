extends RefCounted
## Stable core-width horizontal separation, independent of hurtboxes/poses.
const MAX_CORRECTION := 0.25
const FEET_TOLERANCE := 0.08
static func pair(a: Dictionary, b: Dictionary) -> Vector2:
	if not a.eligible or not b.eligible: return Vector2.ZERO
	if absf(a.feet-b.feet) > FEET_TOLERANCE: return Vector2.ZERO
	var dx: float = b.center-a.center
	var overlap: float = a.radius+b.radius-absf(dx)
	if overlap <= 0.00001: return Vector2.ZERO
	var direction := signf(dx) if absf(dx)>0.00001 else 1.0
	var correction := minf(MAX_CORRECTION,overlap*0.5)
	return Vector2(-direction*correction,direction*correction)

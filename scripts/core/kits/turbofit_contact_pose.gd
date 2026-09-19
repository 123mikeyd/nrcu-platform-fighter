extends RefCounted
## 120Hz installed source samples; no AnimationPlayer, Skeleton or actor reference.
const CURVES = preload("res://data/contact/turbofit_kick_curves.tres")
func center(clip: String, elapsed: float, facing: float, scale_factor := 1.0) -> Vector3:
	var points: PackedVector3Array = CURVES.get_meta(clip)
	var sample := clampf(elapsed * 120.0, 0, points.size() - 1)
	var index := floori(sample)
	var local := points[index].lerp(points[mini(index + 1, points.size() - 1)], sample - index)
	return Basis(Vector3.UP, facing * PI / 2.0) * local * 1.25 * scale_factor

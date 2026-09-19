extends RefCounted

static func earliest_contact(start: Vector3, finish: Vector3, radius: float, capsules: Array, source_id: String = "", victim_id: String = "") -> Dictionary:
	var best := {}
	for capsule: Variant in capsules:
		if not capsule is Dictionary: continue
		var contact := sweep_sphere(start, finish, radius, capsule, source_id, victim_id)
		if contact.is_empty(): continue
		if best.is_empty() or contact.t < best.t or (contact.t == best.t and contact.hurtbox_id < best.hurtbox_id): best = contact
	return best

static func capsule_from_transform(id: String, transform: Transform3D, height: float, radius: float) -> Dictionary:
	if id.is_empty() or not transform.is_finite() or not is_finite(height) or not is_finite(radius) or radius <= 0 or height < 2.0*radius: return {}
	var x := transform.basis.x
	var y := transform.basis.y
	var z := transform.basis.z
	var scale2 := _dot(x, x)
	if scale2 <= 0: return {}
	# Relative tolerance accommodates float32 rotation matrices, not shape fitting.
	var tolerance := 0.000001 * scale2
	if absf(_dot(y, y)-scale2) > tolerance or absf(_dot(z, z)-scale2) > tolerance: return {}
	if absf(_dot(x, y)) > tolerance or absf(_dot(x, z)) > tolerance or absf(_dot(y, z)) > tolerance: return {}
	var half_segment := height*0.5 - radius
	var result := {"id": id, "a": transform * Vector3(0, -half_segment, 0), "b": transform * Vector3(0, half_segment, 0), "radius": radius*sqrt(scale2)}
	return result if _valid(result) else {}
## Enclosure, NOT an exact ellipsoid or an authored-pose repair.
## A(segment + ball(r)) = A(segment) + A(ball(r)); ||A v|| <= sqrt(||A^T A||inf)||v||.
## Scalar doubles operate on stored float32 columns. 1e-14 exceeds gamma_32
## for double roundoff (including three-term dot, row sums and sqrt).
static func capsule_enclosing_affine(id: String, transform: Transform3D, height: float, radius: float) -> Dictionary:
	if id.is_empty() or not transform.is_finite() or not is_finite(height) or not is_finite(radius) or radius <= 0 or height < 2.0*radius: return {}
	var columns := [transform.basis.x,transform.basis.y,transform.basis.z]
	var magnitude := 0.0
	for v: Vector3 in columns:
		for axis in 3: magnitude = maxf(magnitude,absf(v[axis]))
	if magnitude == 0: return {}
	# Normalize in doubles, not Vector3, to avoid float overflow/underflow.
	var n := []
	for v: Vector3 in columns: n.append([float(v.x)/magnitude,float(v.y)/magnitude,float(v.z)/magnitude])
	var determinant: float = n[0][0]*(n[1][1]*n[2][2]-n[1][2]*n[2][1])-n[1][0]*(n[0][1]*n[2][2]-n[0][2]*n[2][1])+n[2][0]*(n[0][1]*n[1][2]-n[0][2]*n[1][1])
	# Both orientations are valid; degenerate/ill-conditioned maps fail closed.
	if absf(determinant) <= 1e-12: return {}
	var bound2 := 0.0; var minimum_column2 := INF
	var uniform := true; var first_diagonal := -1.0
	for i in 3:
		var row := 0.0
		for j in 3:
			var dot: float = n[i][0]*n[j][0]+n[i][1]*n[j][1]+n[i][2]*n[j][2]
			row += absf(dot)
			if i == j:
				minimum_column2 = minf(minimum_column2,dot)
				if first_diagonal < 0: first_diagonal = dot
				elif dot != first_diagonal: uniform = false
			elif dot != 0: uniform = false
		bound2 = maxf(bound2,row)
	var scale_bound := magnitude*sqrt(bound2)*(1.0+1e-14)
	var half_segment := height*0.5-radius
	var ends := []; var endpoint_error := 0.0
	for sign_ in [-1.0,1.0]:
		var end := Vector3.ZERO; var error2 := 0.0
		for axis in 3:
			var term: float = float(transform.basis.y[axis])*half_segment*sign_
			var value := float(transform.origin[axis])+term
			end[axis] = value
			# Bound stored endpoint rounding plus double evaluation error.
			var error := absf(float(end[axis])-value)+(absf(term)+absf(transform.origin[axis]))*1e-14
			error2 += error*error
		ends.append(end); endpoint_error = maxf(endpoint_error,sqrt(error2)*(1.0+1e-14))
	var result := {"id":id,"a":ends[0],"b":ends[1],"radius":(radius*scale_bound+endpoint_error)*(1.0+1e-14),"mapping":"uniform" if uniform else "conservative_affine_enclosure","radius_scale_bound":scale_bound,"inflation_factor":scale_bound/(magnitude*sqrt(minimum_column2)),"endpoint_rounding_pad":endpoint_error,"reflected":determinant < 0}
	return result if _valid(result) else {}

## Pure world-space narrowphase. Touching is inclusive; invalid inputs miss.

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _valid(c: Dictionary) -> bool:
	return c.get("id") is String and not c.id.is_empty() and c.get("a") is Vector3 and c.get("b") is Vector3 and c.a.is_finite() and c.b.is_finite() and _number(c.get("radius")) and c.radius > 0

# Scalar double arithmetic avoids Vector3 dot products rounding to real_t.
static func _dot(a: Vector3, b: Vector3) -> float:
	return float(a.x) * b.x + float(a.y) * b.y + float(a.z) * b.z

static func sphere_overlap(center: Vector3, radius: float, capsule: Dictionary) -> bool:
	if not center.is_finite() or not is_finite(radius) or radius < 0 or not _valid(capsule): return false
	var a: Vector3 = capsule.a
	var b: Vector3 = capsule.b
	var ab := [float(b.x)-a.x, float(b.y)-a.y, float(b.z)-a.z]
	var p := [float(center.x)-a.x, float(center.y)-a.y, float(center.z)-a.z]
	var length2: float = ab[0]*ab[0] + ab[1]*ab[1] + ab[2]*ab[2]
	var projection: float = p[0]*ab[0] + p[1]*ab[1] + p[2]*ab[2]
	var u := clampf(projection / length2, 0, 1) if length2 > 0 else 0.0
	var dx: float = p[0] - ab[0] * u
	var dy: float = p[1] - ab[1] * u
	var dz: float = p[2] - ab[2] * u
	var r: float = radius + capsule.radius
	return dx * dx + dy * dy + dz * dz <= r * r

# Solve |p + t*v| <= r by its closest approach, avoiding B*B-A*C
# cancellation for very long sweeps. Inputs are scalar doubles, not Vector3.
static func _entry(p: Array, v: Array, r: float) -> float:
	var speed2: float = v[0]*v[0] + v[1]*v[1] + v[2]*v[2]
	if speed2 == 0: return INF
	var closest: float = -(p[0]*v[0] + p[1]*v[1] + p[2]*v[2]) / speed2
	var x: float = p[0] + closest*v[0]
	var y: float = p[1] + closest*v[1]
	var z: float = p[2] + closest*v[2]
	var margin := r*r - (x*x + y*y + z*z)
	if margin < 0: return INF
	return closest - sqrt(margin / speed2)

static func sweep_sphere(start: Vector3, finish: Vector3, radius: float, capsule: Dictionary, source_id: String = "", victim_id: String = "") -> Dictionary:
	if not start.is_finite() or not finish.is_finite() or not is_finite(radius) or radius < 0 or not _valid(capsule): return {}
	var best := INF
	if sphere_overlap(start, radius, capsule):
		best = 0.0
	else:
		var v := [float(finish.x)-start.x, float(finish.y)-start.y, float(finish.z)-start.z]
		var r: float = radius + capsule.radius
		for end: Vector3 in [capsule.a, capsule.b]:
			var p := [float(start.x)-end.x, float(start.y)-end.y, float(start.z)-end.z]
			var t := _entry(p, v, r)
			if t >= 0 and t <= 1: best = minf(best, t)
		var a: Vector3 = capsule.a
		var b: Vector3 = capsule.b
		var axis := [float(b.x)-a.x, float(b.y)-a.y, float(b.z)-a.z]
		var p := [float(start.x)-a.x, float(start.y)-a.y, float(start.z)-a.z]
		var length2: float = axis[0]*axis[0] + axis[1]*axis[1] + axis[2]*axis[2]
		if length2 > 0:
			var u: float = (p[0]*axis[0] + p[1]*axis[1] + p[2]*axis[2]) / length2
			var du: float = (v[0]*axis[0] + v[1]*axis[1] + v[2]*axis[2]) / length2
			var radial_p := []; var radial_v := []
			for i in 3:
				radial_p.append(p[i] - u*axis[i])
				radial_v.append(v[i] - du*axis[i])
			var t := _entry(radial_p, radial_v, r)
			if t >= 0 and t <= 1 and u + t*du >= 0 and u + t*du <= 1: best = minf(best, t)
	if not is_finite(best): return {}
	return {"t": best, "source_id": source_id, "victim_id": victim_id, "hurtbox_id": capsule.id}

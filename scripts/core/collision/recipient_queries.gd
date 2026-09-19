extends RefCounted
## Recipient adapter. Generated misses never consult native bodies or origins.
## Cone distance uses convex projections (spherical sector intersect depth slab),
## then convex one-dimensional segment minimization. Tolerance is world-space
## numerical contact tolerance, not an attack-range/profile tuning parameter.
const Queries = preload("res://scripts/core/collision/hurtbox_queries.gd")
const CONTACT_EPS := 0.000001

static func generated(target: Dictionary) -> bool:
	return target.get("geometry_mode","") == "generated_hurtboxes" or target.get("collision_host") != null

static func snapshot(target: Dictionary) -> Dictionary:
	var value: Dictionary = target.collision_host.telemetry() if target.get("collision_host") != null else target.get("hurtbox_snapshot",{})
	# Never substitute the post-damage presentation pose for frozen contacts.
	return value.get("contact_snapshot",value)

static func primitives(target: Dictionary) -> Array:
	var value := snapshot(target)
	return value.get("primitives",[]) if value.get("ok",false) else []

static func evidence(target: Dictionary, capsule: Dictionary) -> Dictionary:
	var value := snapshot(target)
	return {"hurtbox_id":capsule.id,"pose_revision":value.get("pose_revision",{}).duplicate(true),"profile_revision":value.get("profile_revision",{}).duplicate(true)}

static func annotate(event: Dictionary, target: Dictionary, contact: Dictionary) -> Dictionary:
	if generated(target):
		event.geometry_mode = "generated_hurtboxes"
		event.contact_evidence = contact.duplicate(true)
	return event

static func sphere(target: Dictionary, start: Vector3, finish: Vector3, radius: float) -> Dictionary:
	var hit := Queries.earliest_contact(start,finish,radius,primitives(target))
	if hit.is_empty(): return {}
	var value := snapshot(target)
	hit.pose_revision = value.get("pose_revision",{}).duplicate(true)
	hit.profile_revision = value.get("profile_revision",{}).duplicate(true)
	return hit

static func box(target: Dictionary, origin: Vector3, lower: Vector3, upper: Vector3) -> Dictionary:
	return _volume(target,origin,func(p: Vector3) -> Vector3: return p.clamp(lower,upper))

static func cylinder_sweep(target: Dictionary, start: Vector3, motion_x: float, radius: float, half_depth: float) -> Dictionary:
	var initial := _cylinder_prefix(target,start,0,radius,half_depth)
	if not initial.is_empty(): initial.t = 0.0; return initial
	var last := _cylinder_prefix(target,start,motion_x,radius,half_depth)
	if last.is_empty(): return {}
	var lo := 0.0; var hi := 1.0
	for i in 26:
		var middle := (lo+hi)*.5
		var hit := _cylinder_prefix(target,start,motion_x*middle,radius,half_depth)
		if hit.is_empty(): lo = middle
		else: hi = middle; last = hit
	last.t = hi
	return last

static func _cylinder_prefix(target: Dictionary, start: Vector3, motion_x: float, radius: float, half_depth: float) -> Dictionary:
	# An X-axis cylinder swept along its axis is another X-axis cylinder.
	var lower := minf(0,motion_x)-half_depth
	var upper := maxf(0,motion_x)+half_depth
	var project := func(p: Vector3) -> Vector3:
		var radial := Vector2(p.y,p.z).limit_length(radius)
		return Vector3(clampf(p.x,lower,upper),radial.x,radial.y)
	return _volume(target,start,project)

static func cone(target: Dictionary, origin: Vector3, direction: Vector3, reach: float, depth: float = 1.5, cosine: float = .4) -> Dictionary:
	var axis := direction.normalized()
	var project := func(p: Vector3) -> Vector3: return _project_sector_slab(p,axis,reach,depth,cosine)
	return _volume(target,origin,project)

static func _volume(target: Dictionary, origin: Vector3, project: Callable) -> Dictionary:
	for capsule in primitives(target):
		var nearest := _segment_distance(capsule.a-origin,capsule.b-origin,project)
		if nearest.distance <= float(capsule.radius)+CONTACT_EPS:
			var hit := evidence(target,capsule)
			hit.point = origin+nearest.point
			return hit
	return {}

static func _segment_distance(a: Vector3, b: Vector3, project: Callable) -> Dictionary:
	# Squared distance to a closed convex volume along a segment is convex.
	var lo := 0.0; var hi := 1.0
	for i in 36:
		var u := (2*lo+hi)/3; var v := (lo+2*hi)/3
		var p := a.lerp(b,u); var q := a.lerp(b,v)
		if p.distance_squared_to(project.call(p)) <= q.distance_squared_to(project.call(q)): hi = v
		else: lo = u
	var best := {"distance":INF,"point":a}
	for t in [0.0,1.0,(lo+hi)*.5]:
		var p := a.lerp(b,t)
		var distance := p.distance_to(project.call(p))
		if distance < best.distance: best = {"distance":distance,"point":p}
	return best

static func _project_sector(p: Vector3, axis: Vector3, reach: float, cosine: float) -> Vector3:
	var axial := p.dot(axis)
	var radial := p-axis*axial
	var width := radial.length()
	var sine := sqrt(1-cosine*cosine)
	var result := p
	if axial < p.length()*cosine:
		var along := axial*cosine+width*sine
		if along <= 0: return Vector3.ZERO
		result = (axis*cosine+(radial/width if width > 0 else Vector3.ZERO)*sine)*along
	return result.limit_length(reach)

static func _project_sector_slab(p: Vector3, axis: Vector3, reach: float, depth: float, cosine: float) -> Vector3:
	var unconstrained := _project_sector(p,axis,reach,cosine)
	if absf(unconstrained.z) <= depth: return unconstrained
	# Every authored cone axis is in the XY gameplay plane. If the sector
	# projection violates the depth slab, the constrained optimum lies on its
	# nearer boundary plane. Solve that convex 2D slice instead of terminating
	# alternating projections with an unbounded convergence residual.
	var lateral := Vector3(-axis.y,axis.x,0)
	var px := float(p.x)*axis.x+float(p.y)*axis.y
	var py := float(p.x)*lateral.x+float(p.y)*lateral.y
	var slope := cosine/sqrt(1-cosine*cosine)
	var cap2 := reach*reach-depth*depth
	var maximum := sqrt(maxf(0,reach*reach*(1-cosine*cosine)-depth*depth))
	var lo := -maximum; var hi := maximum
	for i in 48:
		var u := (2*lo+hi)/3; var v := (lo+2*hi)/3
		if _slice_distance(u,px,py,slope,depth,cap2) <= _slice_distance(v,px,py,slope,depth,cap2): hi = v
		else: lo = u
	var best_y := (lo+hi)*.5
	var best := _slice_distance(best_y,px,py,slope,depth,cap2)
	for y in [-maximum,maximum]:
		var distance := _slice_distance(y,px,py,slope,depth,cap2)
		if distance < best: best = distance; best_y = y
	var x := clampf(px,slope*sqrt(best_y*best_y+depth*depth),sqrt(maxf(0,cap2-best_y*best_y)))
	return axis*x+lateral*best_y+Vector3(0,0,signf(p.z)*depth)

static func _slice_distance(y: float, px: float, py: float, slope: float, depth: float, cap2: float) -> float:
	var x := clampf(px,slope*sqrt(y*y+depth*depth),sqrt(maxf(0,cap2-y*y)))
	return (x-px)*(x-px)+(y-py)*(y-py)

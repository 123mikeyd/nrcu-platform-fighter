extends RefCounted
## Caller-owned discrete committed hurtboxes, never physical movement shapes.
const Queries = preload("res://scripts/core/collision/hurtbox_queries.gd")
var _profile: Resource
var _transform_policy := "exact"
var _revision: Dictionary = {}
var _cache_key: Array = []
var _cache: Dictionary = {}

func reset() -> void:
	_cache_key.clear()
	_cache.clear()

func cache_size() -> int:
	return 0 if _cache_key.is_empty() else 1

func configure(profile: Resource, source_asset: String, source_sha256: String, revision: String, transform_policy: String = "exact") -> PackedStringArray:
	reset()
	_profile = null
	_revision.clear()
	var errors := PackedStringArray()
	_transform_policy = "exact"
	if transform_policy not in ["exact","conservative_affine"]: return PackedStringArray(["unsupported transform policy"])
	if profile == null or profile.get_script() != preload("res://scripts/core/collision/character_collision_profile.gd"):
		return PackedStringArray(["unsupported or null profile"])
	# Validate resource types before invoking the schema's nested validators.
	for h in profile.hurtboxes:
		if h == null or h.get_script() != preload("res://scripts/core/collision/generated_hurtbox.gd"):
			return PackedStringArray(["unsupported or null hurtbox"])
	errors.append_array(profile.validate())
	if profile.generator_version != 1: errors.append("unsupported generator version")
	var hash_pattern := RegEx.new()
	hash_pattern.compile("^[0-9a-f]{64}$")
	if hash_pattern.search(profile.source_sha256) == null: errors.append("invalid source SHA256")
	if profile.source_asset.is_empty() or profile.source_asset != source_asset or profile.source_sha256 != source_sha256: errors.append("source identity mismatch")
	if revision.strip_edges().is_empty(): errors.append("missing profile revision")
	if profile.hurtboxes.is_empty(): errors.append("no skeletal hurtboxes; static/rigid anchors unsupported")
	for h in profile.hurtboxes:
		if h.hurtbox_id.strip_edges().is_empty(): errors.append("invalid hurtbox ID")
	if not errors.is_empty(): return errors
	_transform_policy = transform_policy
	_profile = profile.duplicate(true)
	_profile.hurtboxes.sort_custom(func(a,b): return a.hurtbox_id < b.hurtbox_id)
	_revision = {"character_id":profile.character_id,"generator_version":profile.generator_version,"source_asset":source_asset,"source_sha256":source_sha256,"revision":revision}
	return PackedStringArray()

func build(entity_id: String, pose: Dictionary, model_to_world: Transform3D, pose_revision: Dictionary, participation: Dictionary = {}) -> Dictionary:
	var key := [entity_id,pose,model_to_world,pose_revision,participation]
	if key == _cache_key: return _cache.duplicate(true)
	var result := _build(entity_id,pose,model_to_world,pose_revision,participation)
	# Never retain malformed inputs or references to caller-owned containers.
	reset()
	if result.ok:
		_cache_key = key.duplicate(true)
		_cache = result.duplicate(true)
	return result

func _build(entity_id: String, pose: Dictionary, model_to_world: Transform3D, pose_revision: Dictionary, participation: Dictionary) -> Dictionary:
	var result := {"ok":true,"diagnostics":PackedStringArray(),"entity_id":entity_id,"profile_revision":_revision.duplicate(true),"pose_revision":pose_revision.duplicate(true),"participation":participation.duplicate(true),"primitives":[],"aabb":AABB(),"has_bounds":false,"transform_policy":_transform_policy}
	if _profile == null: return _fail(result,"profile not configured")
	if entity_id.strip_edges().is_empty(): return _fail(result,"missing entity ID")
	for key in ["source_asset","source_sha256","clip","episode_id"]:
		if not pose_revision.get(key) is String or pose_revision[key].is_empty(): return _fail(result,"missing pose identity: " + key)
	if pose_revision.source_asset != _revision.source_asset or pose_revision.source_sha256 != _revision.source_sha256: return _fail(result,"pose source identity mismatch")
	if not (pose_revision.get("seconds") is float or pose_revision.get("seconds") is int) or not is_finite(float(pose_revision.seconds)): return _fail(result,"invalid committed source seconds")
	if not pose_revision.get("policy") is int or pose_revision.policy not in [0,1]: return _fail(result,"unsupported time policy")
	for key in pose_revision:
		if key not in ["source_asset","source_sha256","clip","episode_id","seconds","policy"]: return _fail(result,"unsupported pose metadata (including blends)")
	for key in participation:
		if key not in ["enabled","eliminated","team_id","enabled_hurtbox_ids"]: return _fail(result,"unsupported participation field")
	for key in ["enabled","eliminated"]:
		if participation.has(key) and not participation[key] is bool: return _fail(result,"participation flag must be bool")
	if participation.has("team_id") and not participation.team_id is String: return _fail(result,"team ID must be String")
	if participation.has("enabled_hurtbox_ids"):
		if not participation.enabled_hurtbox_ids is PackedStringArray: return _fail(result,"enabled IDs must be PackedStringArray")
		var known := {}; var selected := {}
		for h in _profile.hurtboxes: known[h.hurtbox_id] = true
		for id in participation.enabled_hurtbox_ids:
			if not known.has(id) or selected.has(id): return _fail(result,"unknown/duplicate enabled hurtbox ID")
			selected[id] = true
	result.participation.enabled = participation.get("enabled",true)
	result.participation.eliminated = participation.get("eliminated",false)
	result.participation.active = result.participation.enabled and not result.participation.eliminated
	if not result.participation.active: return result
	if _convert("placement",model_to_world,2.0,1.0).is_empty(): return _fail(result,"unsupported model_to_world transform")
	for h in _profile.hurtboxes:
		if participation.has("enabled_hurtbox_ids") and h.hurtbox_id not in participation.enabled_hurtbox_ids: continue
		if not pose.get(h.bone_name) is Transform3D: return _fail(result,"missing/invalid bone: " + h.bone_name)
		if _convert("bone",pose[h.bone_name],2.0,1.0).is_empty(): return _fail(result,"nonfinite/singular or policy-unsupported bone: " + h.bone_name)
		var c := _convert(h.hurtbox_id,model_to_world * pose[h.bone_name] * h.local_transform,h.height,h.radius)
		if c.is_empty(): return _fail(result,"unsupported world capsule: " + h.hurtbox_id)
		if c.get("inflation_factor",1.0) > 1.05:
			result.diagnostics.append("large affine enclosure: %s inflation=%s" % [h.hurtbox_id,c.inflation_factor])
		result.primitives.append(c)
		result.aabb = _capsule_bounds(c,result.aabb,result.has_bounds)
		if not result.aabb.position.is_finite() or not result.aabb.size.is_finite() or not result.aabb.end.is_finite(): return _fail(result,"nonfinite world bounds")
		result.has_bounds = true
	result.participation.active = not result.primitives.is_empty()
	return result

func _convert(id: String, transform: Transform3D, height: float, radius: float) -> Dictionary:
	if _transform_policy == "conservative_affine": return Queries.capsule_enclosing_affine(id,transform,height,radius)
	return Queries.capsule_from_transform(id,transform,height,radius)

func _capsule_bounds(c: Dictionary, previous: AABB, has_previous: bool) -> AABB:
	var low := Vector3.ZERO
	var size := Vector3.ZERO
	for axis in 3:
		var lo := minf(c.a[axis],c.b[axis])-float(c.radius)
		var hi := maxf(c.a[axis],c.b[axis])+float(c.radius)
		if has_previous:
			lo = minf(lo,previous.position[axis])
			hi = maxf(hi,previous.end[axis])
		low[axis] = _outward_float(lo,false)
		var upper := _outward_float(hi,true)
		size[axis] = _outward_float(upper-float(low[axis]),true)
		# Position+size is rounded again by Vector3/AABB.end.
		if float((low+size)[axis]) < hi:
			size[axis] = _next_float(size[axis],true)
	return AABB(low,size)

func _outward_float(value: float, upper: bool) -> float:
	var bytes := PackedByteArray(); bytes.resize(4); bytes.encode_float(0,value)
	var rounded := bytes.decode_float(0)
	if (upper and rounded < value) or (not upper and rounded > value): return _next_float(rounded,upper)
	return rounded

func _next_float(value: float, upper: bool) -> float:
	if not is_finite(value): return value
	var bytes := PackedByteArray(); bytes.resize(4); bytes.encode_float(0,value)
	var bits := bytes.decode_u32(0)
	if value == 0.0: bits = 1 if upper else 0x80000001
	else: bits += 1 if (value > 0.0) == upper else -1
	bytes.encode_u32(0,bits)
	return bytes.decode_float(0)

func _fail(result: Dictionary, diagnostic: String) -> Dictionary:
	result.ok = false
	result.participation.active = false
	result.diagnostics.append(diagnostic)
	result.primitives.clear()
	result.aabb = AABB()
	result.has_bounds = false
	return result

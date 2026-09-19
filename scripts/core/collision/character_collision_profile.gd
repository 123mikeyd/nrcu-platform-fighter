@tool
extends Resource
const Hurtbox = preload("res://scripts/core/collision/generated_hurtbox.gd")
@export var character_id: String = ""
@export var generator_version: int = 1
@export var source_asset: String = ""
@export var source_sha256: String = ""
@export var visual_scale: float = 1.0
@export var foot_origin: Vector3 = Vector3.ZERO
@export var body_radius: float = 0.0
@export var body_height: float = 0.0
@export var body_center: Vector3 = Vector3.ZERO
@export var hurtboxes: Array[Resource] = []
@export var warnings: PackedStringArray = []
@export var provenance: Dictionary = {}
@export var manual_override: bool = false
# Separate override resource: only these explicitly named properties are merged.
@export var override_fields: PackedStringArray = []
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if character_id.is_empty(): errors.append("missing character ID")
	if not is_finite(visual_scale) or visual_scale <= 0: errors.append("invalid visual scale")
	if not is_finite(body_radius) or not is_finite(body_height) or body_radius <= 0 or body_height <= 0 or (body_height < 2 * body_radius and not is_equal_approx(body_height, 2 * body_radius)): errors.append("invalid body dimensions")
	if not body_center.is_finite() or not foot_origin.is_finite(): errors.append("nonfinite origin")
	errors.append_array(_validate_hurtboxes())
	return errors
func _validate_hurtboxes() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for h in hurtboxes:
		if h == null: errors.append("null hurtbox"); continue
		if not h is Hurtbox: errors.append("unsupported hurtbox resource"); continue
		errors.append_array(h.validate())
		if ids.has(h.hurtbox_id): errors.append("duplicate hurtbox")
		ids[h.hurtbox_id] = true
	return errors
func merged_with(overrides: Resource) -> Dictionary:
	# Validate both resource trees before reading override flags or matching IDs.
	var errors := validate()
	if not errors.is_empty(): return {"errors": errors}
	if overrides != null:
		if not is_instance_of(overrides, load("res://scripts/core/collision/character_collision_profile.gd")):
			return {"errors": PackedStringArray(["unsupported collision override resource"])}
		# Body overrides may be partial; only selected body fields are validated
		# on the merged result. Nested hurtboxes are always complete definitions.
		errors = overrides._validate_hurtboxes()
		if not errors.is_empty(): return {"errors": errors}
	var result = duplicate(true)
	if overrides == null: return {"profile": result, "errors": result.validate()}
	if overrides.character_id != character_id or not overrides.manual_override:
		return {"errors": ["override must explicitly flag matching character ID"]}
	for field in overrides.override_fields:
		if field not in ["body_radius", "body_height", "body_center", "foot_origin"]:
			return {"errors": ["unsupported override field: " + field]}
		result.set(field, overrides.get(field))
	for h in overrides.hurtboxes:
		if not h.manual_override: continue
		var found := false
		for i in result.hurtboxes.size():
			if result.hurtboxes[i].hurtbox_id == h.hurtbox_id:
				if result.hurtboxes[i].bone_name != h.bone_name: return {"errors": ["override cannot silently rebind bone"]}
				result.hurtboxes[i] = h.duplicate(true); found = true; break
		if not found: return {"errors": ["unknown override hurtbox ID: " + h.hurtbox_id]}
	result.manual_override = true
	return {"profile": result, "errors": result.validate()}

func instantiate_body() -> CollisionShape3D:
	assert(validate().is_empty())
	var node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius; shape.height = body_height
	node.shape = shape; node.position = body_center
	return node

@tool
extends Resource
## Definition only: consumers must request independent CollisionShape3D instances.
@export var hurtbox_id: String = ""
@export var bone_name: String = ""
@export var local_transform: Transform3D = Transform3D.IDENTITY
@export var radius: float = 0.0
@export var height: float = 0.0
@export var confidence: String = "unreviewed"
@export var provenance: String = ""
@export var manual_override: bool = false
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if hurtbox_id.is_empty() or bone_name.is_empty(): errors.append("missing ID/bone")
	if not is_finite(radius) or not is_finite(height) or radius <= 0 or height <= 0 or (height < 2 * radius and not is_equal_approx(height, 2 * radius)): errors.append("invalid capsule dimensions")
	if not local_transform.is_finite() or not local_transform.basis.is_equal_approx(local_transform.basis.orthonormalized()) or local_transform.basis.determinant() <= 0: errors.append("local transform must be finite rigid transform without scale/reflection")
	return errors
func instantiate_shape() -> CollisionShape3D:
	assert(validate().is_empty())
	var node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius; shape.height = height
	node.shape = shape; node.transform = local_transform
	return node

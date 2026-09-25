extends "res://scripts/projectile.gd"
const IMPACT_DAMAGE := 6.0
const IMPACT_KNOCKBACK := 2.0
const DESCENT_RATIO := 0.18
func _travel_step(delta: float) -> Vector3:
    # The authored hand is above capsule height: a shallow downward bolt,
    # not an enlarged hit radius or an invisible target-proximity status.
    return Vector3(direction, -DESCENT_RATIO, 0) * SPEED * delta

func place_at_cast_hand(visual: Node3D, cast_facing: float) -> void:
    visual.sync_pose(true, Vector3.ZERO, false, false, "", cast_facing, 0, "IceCast", 0.2)
    var rig: Skeleton3D = visual.model.find_children("*", "Skeleton3D", true, false)[0]
    rig.force_update_all_bone_transforms()
    global_position = rig.global_transform * rig.get_bone_global_pose(rig.find_bone("RightHand")).origin
    global_position.z = 0

func _ready() -> void:
    freeze_bolt = false
    color = Color(1, 0.24, 0.035)
    super._ready()
    var core := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.15
    sphere.height = 0.3
    core.mesh = sphere
    core.position.z = 0.21
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1, 0.8, 0.16)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    core.material_override = material
    add_child(core)
func payload_damage() -> float: return IMPACT_DAMAGE
func _hit_target(target: Node3D) -> void:
    if is_queued_for_deletion() or not is_instance_valid(source) or not source.can_hit(target): return
    if _try_absorb(target): return
    var blocked: bool = target.shielding
    preload("res://scripts/body_hurtboxes.gd").deliver(target, payload_damage(), Vector3(direction, 0.2, 0), IMPACT_KNOCKBACK, contact_hit, source)
    if not blocked: target.apply_burn(source)
    hide()
    queue_free()
func reflect(new_source: Node3D, _new_color: Color) -> void:
    # Ownership changes; fire identity and finite travel-time budget do not.
    source = new_source
    direction *= -1.0

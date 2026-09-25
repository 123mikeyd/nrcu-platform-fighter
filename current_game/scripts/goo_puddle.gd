extends Node3D

const DURATION := 3.0
const SPEED_MULTIPLIER := 0.65
const RADIUS := 0.85
const MAX_PER_OWNER := 3
var source: Node3D
var surface: Node3D
var lifetime := DURATION

func _ready() -> void:
    add_to_group("goo_puddles")
    var owned: Array = []
    for puddle in get_tree().get_nodes_in_group("goo_puddles"):
        if puddle.source == source and not puddle.is_queued_for_deletion(): owned.append(puddle)
    while owned.size() > MAX_PER_OWNER:
        owned.pop_front().queue_free()
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.24, 0.59, 0.10)
    material.roughness = 0.3
    # Overlapping flattened lobes, not a luminous attack sphere.
    for i in 3:
        var visual := MeshInstance3D.new()
        var mesh := SphereMesh.new()
        mesh.radius = 1;mesh.height = 2
        visual.mesh = mesh
        visual.scale = Vector3(0.58 if i==0 else 0.40, 0.045, 0.44 if i==0 else 0.32)
        visual.position = Vector3((i-1)*0.32, 0, 0.08 if i==1 else -0.06)
        visual.material_override = material
        add_child(visual)

func affects(fighter: Node3D) -> bool:
    if is_queued_for_deletion() or lifetime <= 0 or not is_instance_valid(source) or not source.controls_enabled or source.stocks <= 0:
        return false
    if not fighter.controls_enabled or fighter.stocks <= 0 or not fighter.is_grounded() or fighter.velocity.y > 0 or not source.can_hit(fighter):
        return false
    var offset: Vector3 = fighter.global_position - global_position
    return absf(offset.y) < 0.16 and Vector2(offset.x, offset.z).length() <= RADIUS

func _physics_process(delta: float) -> void:
    lifetime -= delta
    if lifetime <= 0 or not is_instance_valid(surface) or not is_instance_valid(source) or not source.controls_enabled or source.stocks <= 0:
        queue_free()

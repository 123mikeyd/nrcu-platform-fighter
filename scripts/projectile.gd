extends Node3D

var source: Node3D
var direction := 1.0
var color := Color.GREEN
var sound_wave := false
var freeze_bolt := false
var lifetime := 1.6
const SPEED := 15.0
var _visual: MeshInstance3D
var contact_hit: Dictionary = {}

func _ready() -> void:
    add_to_group("projectiles")
    var visual := MeshInstance3D.new()
    _visual = visual
    var mesh := SphereMesh.new()
    mesh.radius = 0.28
    mesh.height = 0.56
    visual.mesh = mesh
    visual.scale.x = 1.8
    if freeze_bolt:
        var crystal := CylinderMesh.new()
        crystal.top_radius = 0.0
        crystal.bottom_radius = 0.2
        crystal.height = 0.65
        crystal.radial_segments = 6
        visual.mesh = crystal
        visual.rotation.z = -direction * PI / 2
        visual.scale = Vector3.ONE
    if sound_wave:
        var ring := TorusMesh.new()
        ring.inner_radius = 0.32
        ring.outer_radius = 0.48
        visual.mesh = ring
        visual.rotation.z = PI / 2.0
        visual.scale = Vector3.ONE
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    visual.material_override = material
    add_child(visual)

func payload_damage() -> float:
    return 4.0 if freeze_bolt else 11.0

# Called only after the existing projectile/body contact query succeeds.
func _try_absorb(target: Node3D) -> bool:
    if is_queued_for_deletion(): return true
    if lifetime <= 0 or not visible or not is_instance_valid(source): return false
    if target.absorb_witcheer_projectile(source, payload_damage()):
        hide()
        queue_free()
        return true
    return false

func _hit_target(target: Node3D) -> void:
    if _try_absorb(target): return
    var blocked: bool = target.shielding
    preload("res://scripts/body_hurtboxes.gd").deliver(target, payload_damage(), Vector3(direction, 0.2, 0), 1.0 if freeze_bolt else 4.5, contact_hit)
    if freeze_bolt and not blocked:
        target.apply_freeze(source)

func reflect(new_source: Node3D, new_color: Color) -> void:
    source = new_source
    direction *= -1.0
    if freeze_bolt and _visual:
        _visual.rotation.z = -direction * PI / 2
    color = new_color
    lifetime = maxf(lifetime, 0.8)
    if _visual and _visual.material_override is StandardMaterial3D:
        _visual.material_override.albedo_color = new_color

func _travel_step(delta: float) -> Vector3:
    return Vector3(direction * SPEED * delta, 0, 0)

func _physics_process(delta: float) -> void:
    if is_queued_for_deletion():
        return
    if not is_instance_valid(source) or not source.controls_enabled:
        queue_free()
        return
    lifetime -= delta
    if lifetime <= 0:
        queue_free()
        return
    var start := global_position
    var end := start + _travel_step(delta)
    # Sweep against stage and fighter capsules: no tunneling at low FPS.
    var query := PhysicsRayQueryParameters3D.create(start, end)
    query.exclude = [source.get_rid()]
    for fighter in get_tree().get_nodes_in_group("fighters"):
        if not source.can_hit(fighter):
            query.exclude += [fighter.get_rid()]
    preload("res://scripts/body_hurtboxes.gd").prepare(source, query)
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    contact_hit = hit.duplicate()
    if not hit.is_empty(): hit.collider = preload("res://scripts/body_hurtboxes.gd").resolve(hit.collider)
    if not hit.is_empty():
        var collider = hit.collider
        if collider.is_in_group("fighters") and source.can_hit(collider):
            _hit_target(collider)
        queue_free()
        return
    # Also cover fighters not yet synchronized into the physics space.
    var nearest: Node3D
    var nearest_distance := INF
    for target in get_tree().get_nodes_in_group("fighters"):
        if not source.can_hit(target):
            continue
        if target.has_node("BodyHurtboxes"): continue # No legacy proximity fallback for pilots.
        var center: Vector3 = target.global_position + Vector3.UP
        var closest := Geometry3D.get_closest_point_to_segment(center, start, end)
        var distance := start.distance_to(closest)
        if center.distance_to(closest) <= 0.75 and distance < nearest_distance:
            nearest = target
            nearest_distance = distance
    if nearest:
        _hit_target(nearest)
        queue_free()
        return
    global_position = end

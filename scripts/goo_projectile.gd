extends "res://scripts/projectile.gd"

const Puddle = preload("res://scripts/goo_puddle.gd")
const THROW_SPEED := 5.5
const LIFT := 3.4
const GRAVITY := 18.0
const MAX_TRAVEL := 4.5
const TTL := 1.5
var fall_speed := LIFT
var travel := 0.0
var age := 0.0

func _ready() -> void:
    color = Color(0.25, 0.66, 0.12)
    super._ready()
    lifetime = TTL
    _visual.scale = Vector3(1.1, 0.85, 0.9)
    _visual.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    _visual.material_override.roughness = 0.32

func reflect(new_source: Node3D, new_color: Color) -> void:
    var remaining := lifetime
    super.reflect(new_source, new_color)
    lifetime = remaining # Reflection cannot extend goo's TTL or travel budget.
    _visual.material_override.albedo_color = Color(0.25, 0.66, 0.12)

func _physics_process(delta: float) -> void:
    if is_queued_for_deletion(): return
    if not is_instance_valid(source) or not source.controls_enabled or source.stocks <= 0:
        queue_free();return
    lifetime -= delta
    if lifetime <= 0:
        queue_free();return
    age += delta
    fall_speed -= GRAVITY * delta
    var step := minf(THROW_SPEED * delta, maxf(0, MAX_TRAVEL - travel))
    travel = minf(MAX_TRAVEL, travel + step)
    var start := global_position
    var end := start + Vector3(direction * step, fall_speed * delta, 0)
    var query := PhysicsRayQueryParameters3D.create(start, end)
    query.exclude = [source.get_rid()]
    for fighter in get_tree().get_nodes_in_group("fighters"):
        if not source.can_hit(fighter): query.exclude += [fighter.get_rid()]
    # One ordered physics sweep: terrain occludes fighters. Never create a pool
    # from the capsule of a fighter or a wall/ceiling, only a downward top hit.
    preload("res://scripts/body_hurtboxes.gd").prepare(source, query)
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    contact_hit = hit.duplicate()
    if not hit.is_empty(): hit.collider = preload("res://scripts/body_hurtboxes.gd").resolve(hit.collider)
    if not hit.is_empty():
        var collider = hit.collider
        if collider.is_in_group("fighters"):
            if source.can_hit(collider): _hit_target(collider)
        elif fall_speed < 0 and hit.normal.y > 0.6:
            var puddle := Puddle.new()
            puddle.source = source
            puddle.surface = collider
            get_parent().add_child(puddle)
            puddle.global_position = hit.position + Vector3.UP * 0.025
        queue_free();return
    global_position = end
    _visual.scale = Vector3(1.1 + sin(age * 19) * 0.09, 0.85 - sin(age * 19) * 0.07, 0.9)

extends "res://scripts/projectile.gd"
# TurboFit-only pressure pulse. No filled ball and no SoundOrb changes.
const TTL := 0.9
const FADE_START := 0.65
const MAX_RANGE := 4.86
const START_SPEED := 9.0
const END_SPEED := 1.8
const START_RADIUS := 0.45
const END_RADIUS := 0.85
const HALF_DEPTH := 0.34
var age := 0.0
var distance_travelled := 0.0
var current_speed := START_SPEED
var wave_radius := START_RADIUS
var opacity := 0.8
var _rings: Array[MeshInstance3D] = []

func _ready() -> void:
    add_to_group("projectiles")
    lifetime = TTL
    for i in 3:
        var visual := MeshInstance3D.new()
        var ring := ImmediateMesh.new()
        # Bow each transverse ring slightly forward: it reads as ))) even
        # edge-on, while remaining an open 3D pressure front, never a ball.
        ring.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
        for segment in 48:
            for tube in 8:
                for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(0,1),Vector2i(1,0),Vector2i(1,1)]:
                    var phi: float = TAU * (tube + corner.y) / 8.0
                    var theta: float = TAU * (segment + corner.x) / 48.0
                    var r := 0.975 + 0.025 * cos(phi)
                    ring.surface_add_vertex(Vector3(0.3 * absf(cos(theta)) + 0.02*sin(phi), r*sin(theta), r*cos(theta)))
        ring.surface_end()
        visual.mesh = ring
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        material.albedo_color = Color(0.72, 0.94, 1.0, opacity)
        visual.material_override = material
        add_child(visual)
        _rings.append(visual)
    _update_wave()

func reflect(new_source: Node3D, _new_color: Color) -> void:
    if is_queued_for_deletion(): return
    source = new_source
    direction *= -1.0
    _update_wave()
    # Never refresh age, speed, radius, cumulative path or remaining TTL.

func damage_active() -> bool:
    return age < FADE_START and not is_queued_for_deletion()

func _update_wave() -> void:
    for i in _rings.size():
        var ring := _rings[i]
        # Three sparse transverse pressure fronts; no sphere or glow overlay.
        var radius := wave_radius * (1.0 - i * 0.13)
        ring.scale = Vector3(direction, radius, radius)
        ring.position.x = direction * (0.16 - i * 0.16)
        ring.material_override.albedo_color = Color(0.72, 0.94, 1.0, opacity * (1.0-i*0.18))

func _sweep_wave(motion: Vector3) -> bool:
    var shape := CylinderShape3D.new()
    shape.radius = wave_radius
    shape.height = HALF_DEPTH * 2.0
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    var volume_offset := Vector3(direction * 0.15, 0, 0)
    query.transform = Transform3D(Basis(Vector3.FORWARD, PI/2.0), global_position + volume_offset)
    query.margin = 0.001
    var excluded: Array[RID] = [source.get_rid()]
    for fighter in get_tree().get_nodes_in_group("fighters"):
        if not source.can_hit(fighter) or not damage_active():
            excluded.append(fighter.get_rid())
    query.exclude = excluded
    preload("res://scripts/body_hurtboxes.gd").prepare(source, query, damage_active())
    var space := get_world_3d().direct_space_state
    var hits := space.intersect_shape(query, 32)
    if hits.is_empty():
        query.motion = motion
        var fractions := space.cast_motion(query)
        if fractions[0] >= 1.0: return false
        var sweep_origin := query.transform.origin
        query.transform.origin += motion * minf(1.0, fractions[1] + 0.002)
        query.motion = Vector3.ZERO
        hits = space.intersect_shape(query, 32)
        # cast_motion and intersect_shape use different contact tolerances.
        # Narrow tilted pilot limbs can yield a cast without a contact manifold.
        # Refine only INSIDE this already-budgeted movement segment: no radius,
        # TTL, travel, team, terrain or damage extension. Require a real overlap.
        if hits.is_empty() and source.get_tree().get_nodes_in_group("fighters").any(func(f): return f.has_node("BodyHurtboxes")):
            for distance in [0.001, 0.002, 0.004, 0.008, 0.016]:
                var fraction := minf(1.0, fractions[1] + distance / maxf(motion.length(), 0.000001))
                query.transform.origin = sweep_origin + motion * fraction
                hits = space.intersect_shape(query, 32)
                if not hits.is_empty(): break
            if hits.is_empty(): return false # A numerical graze is not an impact.
    else:
        query.motion = Vector3.ZERO
    for hit in hits:
        hit.contact = preload("res://scripts/body_hurtboxes.gd").shape_contact(space,query,hit,hits)
        hit.collider = preload("res://scripts/body_hurtboxes.gd").resolve(hit.collider)
    global_position = query.transform.origin - volume_offset
    # Terrain takes priority when touching stage and hurtbody simultaneously.
    for hit in hits:
        if not hit.collider.is_in_group("fighters"): return true
    for hit in hits:
        var target = hit.collider
        if source.can_hit(target) and damage_active():
            if _try_absorb(target): return true
            if not target.shielding:
                preload("res://scripts/body_hurtboxes.gd").deliver(target,11.0, Vector3(direction,0.2,0),4.5,hit.contact, source)
            return true
    return true

func _physics_process(delta: float) -> void:
    if is_queued_for_deletion(): return
    if not is_instance_valid(source) or not source.controls_enabled:
        queue_free(); return
    var step := minf(delta, TTL-age)
    var old_speed := current_speed
    age = minf(TTL, age+step)
    lifetime = TTL-age
    current_speed = lerpf(START_SPEED, END_SPEED, age/TTL)
    wave_radius = lerpf(START_RADIUS, END_RADIUS, age/TTL)
    opacity = 0.8 * clampf((TTL-age)/(TTL-FADE_START),0.0,1.0)
    var travel := minf((old_speed+current_speed)*0.5*step, MAX_RANGE-distance_travelled)
    distance_travelled += travel
    var motion := Vector3(direction * travel, 0, 0)
    if _sweep_wave(motion):
        queue_free(); return
    global_position += motion
    _update_wave()
    if lifetime <= 0.000001 or distance_travelled >= MAX_RANGE:
        queue_free()

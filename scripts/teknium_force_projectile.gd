extends "res://scripts/projectile.gd"
# Isolated force variant: ordinary bolts, goo and SoundOrb are unchanged.
const DAMAGE := 8.0
const PUSH := 6.0
func _ready() -> void:
    color = Color(0.82,0.94,1.0,0.12)
    super._ready()
    var material: StandardMaterial3D = _visual.material_override
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _visual.scale = Vector3(1.8,1.15,1.15)
    var air := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void fragment(){ float rim=pow(1.0-abs(dot(NORMAL,VIEW)),2.4); ALBEDO=vec3(0.82,0.94,1.0); ALPHA=0.012+rim*0.16; }"
    air.shader = shader
    _visual.material_override = air
    for i in 3:
        var edge := MeshInstance3D.new()
        var ring := TorusMesh.new()
        ring.inner_radius = 0.23 + i * 0.035
        ring.outer_radius = ring.inner_radius + 0.016
        edge.mesh = ring
        edge.rotation.z = PI/2
        edge.rotation.y = 0.65
        edge.position.x = -direction * i * 0.15
        var pale := material.duplicate()
        pale.albedo_color = Color(0.82,0.94,1,0.28-i*0.06)
        edge.material_override = pale
        add_child(edge)
func payload_damage() -> float:
    return DAMAGE
func _hit_target(target: Node3D) -> void:
    if _try_absorb(target): return
    target.receive_hit(DAMAGE,Vector3(direction,0.12,0),PUSH)
func reflect(new_source: Node3D, _new_color: Color) -> void:
    source = new_source
    direction *= -1
    # Allegiance changes, source-authored pale air identity and TTL do not.
func _physics_process(delta: float) -> void:
    if is_queued_for_deletion(): return
    if not is_instance_valid(source) or not source.controls_enabled:
        queue_free();return
    lifetime -= delta
    if lifetime <= 0:queue_free();return
    var start := global_position
    var end := start + Vector3(direction*SPEED*delta,0,0)
    # The reviewed right hand reaches off the 2.5D plane. Travel visibly back
    # toward it instead of teleporting the origin or missing every hurtbody.
    end.z = move_toward(start.z, 0.0, 6.0 * delta)
    var query := PhysicsRayQueryParameters3D.create(start,end)
    query.hit_from_inside = true
    var excluded: Array[RID] = [source.get_rid()]
    for fighter in get_tree().get_nodes_in_group("fighters"):
        if not source.can_hit(fighter):excluded.append(fighter.get_rid())
    query.exclude = excluded
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        global_position = hit.position
        if hit.collider.is_in_group("fighters") and source.can_hit(hit.collider):_hit_target(hit.collider)
        queue_free();return
    global_position = end

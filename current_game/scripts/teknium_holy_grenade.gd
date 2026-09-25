extends CharacterBody3D
# No fuse: only the owner's next fresh down-special detonates this device.
var source: Node3D
var spent := false
func material(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color; m.metallic = 0.65; m.roughness = 0.3
    m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = 0.35
    return m
func piece(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
    var v := MeshInstance3D.new(); v.mesh = mesh; v.position = pos; v.material_override = material(color); add_child(v); return v
func _ready():
    collision_layer = 0; collision_mask = 1
    add_to_group("teknium_grenades")
    var col := CollisionShape3D.new(); var shape := SphereShape3D.new(); shape.radius = 0.23; col.shape = shape; add_child(col)
    var shell := SphereMesh.new(); shell.radius = 0.23; shell.height = 0.46
    piece(shell,Vector3.ZERO,Color(0.06,0.5,0.16))
    for angle in [0.0,PI/2]:
        var ring := TorusMesh.new(); ring.inner_radius = 0.22; ring.outer_radius = 0.27
        var v = piece(ring,Vector3.ZERO,Color(1,0.72,0.13)); v.rotation.z = angle
    var stem := BoxMesh.new(); stem.size = Vector3(0.075,0.32,0.075)
    piece(stem,Vector3(0,0.33,0),Color(1,0.8,0.25))
    var cross := BoxMesh.new(); cross.size = Vector3(0.25,0.07,0.07)
    piece(cross,Vector3(0,0.38,0),Color(1,0.8,0.25))
    for x in [-1,1]:
        var diode := BoxMesh.new(); diode.size = Vector3(0.08,0.12,0.03)
        piece(diode,Vector3(x*0.12,0,0.225),Color(0.25,1,0.6))
func _physics_process(delta):
    if spent: return
    if not is_instance_valid(source) or not source.controls_enabled or source.stocks <= 0:
        queue_free(); return
    velocity.y -= 18.0 * delta
    if is_on_floor(): velocity.x = move_toward(velocity.x,0,12*delta)
    move_and_slide()
    global_position.z = 0
    if global_position.y < -8 or absf(global_position.x)>18: queue_free()
func detonate():
    if spent or not is_instance_valid(source): return
    spent = true
    for target in get_tree().get_nodes_in_group("fighters"):
        if not source.can_hit(target): continue
        var center: Vector3 = target.global_position + Vector3.UP
        if center.distance_to(global_position) > 2.6: continue
        var ray := PhysicsRayQueryParameters3D.create(global_position,center,1)
        ray.exclude = [source.get_rid(), target.get_rid()]
        if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
        target.receive_hit_from(16.0,Vector3(signf(center.x-global_position.x),0.65,0),6.0,source)
    # Bounded non-damaging expanding holy-tech flash.
    var blast := Node3D.new(); get_parent().add_child(blast); blast.global_position = global_position
    var ring := MeshInstance3D.new(); var mesh := TorusMesh.new(); mesh.inner_radius=0.85; mesh.outer_radius=1.0
    ring.mesh=mesh; ring.rotation.x=PI/2; ring.material_override=material(Color(0.4,1,0.3)); blast.add_child(ring)
    var tween=blast.create_tween(); tween.tween_property(blast,"scale",Vector3.ONE*2.6,0.18); tween.tween_callback(blast.queue_free)
    hide(); queue_free()

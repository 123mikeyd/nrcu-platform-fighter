extends Node3D
# Shared Return to Sender. Analytic owner support, deliberately NO collision body.
# Timings use physics delta and naturally freeze when the SceneTree is paused.
@export var arrival_seconds := 0.30
@export var orientation_seconds := 0.45
@export var platform_seconds := 2.40
@export var protection_seconds := 1.20
var actor
var phase := "idle"
var elapsed := 0.0
var protection := 0.0
var anchor := Vector3.ZERO
var platform: MeshInstance3D
var ring: MeshInstance3D
var portal: MeshInstance3D
var aura: MeshInstance3D
var label: Label3D
func begin(fighter):
    actor = fighter
    phase = "arrival"
    elapsed = 0
    protection = 0
    anchor = safe_anchor()
    actor.global_position = anchor + Vector3.UP * 0.65
    actor.velocity = Vector3.ZERO
    actor.hitstun = 0
    actor.collision_layer = 0
    actor.collision_mask = 0
    if platform == null: build()
    present()
func safe_anchor() -> Vector3:
    var candidates: Array = [-6.2,-3.8,3.8,6.2,0.0]
    var preferred: float = clampf(actor.spawn_position.x, -6.2, 6.2)
    candidates.sort_custom(func(a,b): return absf(a-preferred) < absf(b-preferred))
    var excluded: Array[RID] = []
    for fighter in actor.get_tree().get_nodes_in_group("fighters"):
        excluded.append(fighter.get_rid())
    for x in candidates:
        var occupied := false
        for fighter in actor.get_tree().get_nodes_in_group("fighters"):
            if fighter != actor and fighter.revival and fighter.revival.phase != "idle" and absf(fighter.revival.anchor.x-x) < 2.1:
                occupied = true
        if occupied: continue
        var top := -INF
        var valid := true
        for dx in [-0.9,0.0,0.9]:
            var ray := PhysicsRayQueryParameters3D.create(Vector3(x+dx,12,0),Vector3(x+dx,-4,0),3)
            ray.exclude = excluded
            var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(ray)
            if hit.is_empty() or hit.normal.y < 0.8:
                valid = false
                break
            top = maxf(top,hit.position.y)
        if valid and top <= 3.9:
            return Vector3(x,maxf(2.5,top+1.6),0)
    # Only used in isolated no-stage fixtures / unsupported custom geometry.
    # Production stages have four tested separate eligible slots.
    return Vector3(preferred,3,0)
func protected() -> bool:
    return phase != "idle" or protection > 0
func tick(delta: float, input: Dictionary) -> bool:
    if phase == "idle":
        protection = maxf(0, protection - delta)
        present()
        return false
    elapsed += delta
    if phase == "arrival":
        actor.global_position = anchor + Vector3.UP * (0.65 * maxf(0, 1.0 - elapsed / arrival_seconds))
        if elapsed + 0.00001 >= arrival_seconds:
            phase = "waiting"
            elapsed = 0
    else:
        actor.global_position = anchor
        if elapsed >= platform_seconds or (elapsed >= orientation_seconds and (input.left or input.right or input.jump or input.up)):
            restore_collision()
            phase = "idle"
            protection = protection_seconds
            actor.reset_air_resources()
            present()
            return false
    actor.velocity = Vector3.ZERO
    actor._floor_contacts_valid = false
    actor._attack_was_down = input.attack
    actor._special_was_down = input.special
    actor._jump_was_down = false
    actor._down_was_down = input.down
    actor._update_move_visuals(delta)
    present()
    return true
func restore_collision():
    if is_instance_valid(actor):
        actor.collision_layer = actor._active_collision_layer
        actor.collision_mask = actor._active_collision_mask
func clear():
    if phase != "idle": restore_collision()
    phase = "idle"
    elapsed = 0
    protection = 0
    present()
func permit_attack() -> bool:
    if phase != "idle": return false
    protection = 0
    present()
    return true
func material(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return m
func mesh_node(node_name: String, mesh: Mesh, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = node_name
    node.mesh = mesh
    node.material_override = material(color)
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)
    return node
func build():
    var disc := CylinderMesh.new()
    disc.top_radius = 1.0
    disc.bottom_radius = 0.82
    disc.height = 0.13
    platform = mesh_node("Platform", disc, Color(0.13,0.28,0.36,0.85))
    var torus := TorusMesh.new()
    torus.inner_radius = 0.89
    torus.outer_radius = 1.0
    ring = mesh_node("TimeRing", torus, Color(0.4,0.9,1,0.9))
    portal = mesh_node("Portal", torus, Color(0.55,0.85,1,0.5))
    var shell := SphereMesh.new()
    shell.radius = 0.78
    shell.height = 2.7
    aura = mesh_node("Protection", shell, Color(0.45,0.85,1,0.13))
    label = Label3D.new()
    label.font_size = 28
    label.pixel_size = 0.012
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color(0.65,0.94,1)
    add_child(label)
func present():
    if platform == null: return
    platform.visible = phase != "idle"
    ring.visible = phase != "idle"
    portal.visible = phase == "arrival"
    label.visible = phase != "idle"
    platform.global_position = anchor - Vector3.UP * 0.08
    ring.global_position = anchor + Vector3.UP * 0.02
    var fraction := 1.0 if phase == "arrival" else clampf(1 - elapsed/platform_seconds, 0.01, 1)
    ring.scale = Vector3(fraction, 0.4, fraction)
    portal.global_position = anchor + Vector3.UP * 2.8
    portal.material_override.albedo_color.a = 0.5 * maxf(0,1-elapsed/arrival_seconds)
    label.global_position = anchor - Vector3.UP * 0.48
    label.text = "RETURN TO SENDER" if phase == "arrival" or elapsed < orientation_seconds else "MOVE / JUMP"
    aura.visible = protected()
    aura.position = Vector3(0,1.2,0)
    aura.material_override.albedo_color.a = 0.22 if phase != "idle" else 0.22 * clampf(protection/protection_seconds,0,1)

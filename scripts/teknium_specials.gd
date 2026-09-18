extends Node
# Tek-only kit. Fighter retains input edges and all controller displacement.
var actor
var grenade
var stored_charge := 0.0
var phase := "idle"
var elapsed := 0.0
var burst_direction := Vector3.UP
var previous := Vector3.ZERO
var targets: Array = []
var ghosts: Array = []
var ghost_clock := 0.0
const HURT = preload("res://scripts/body_hurtboxes.gd")
var cue: Node3D
func _ready():
    actor = get_parent()
    cue = Node3D.new(); cue.name="HolyTechCue"; add_child(cue)
    for i in 2:
        var mesh := MeshInstance3D.new(); var ring := TorusMesh.new()
        ring.inner_radius=0.55; ring.outer_radius=0.62; mesh.mesh=ring
        mesh.rotation.x=PI/2; mesh.rotation.z=i*PI/2
        var mat := StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color=Color(0.2,1,0.35) if i==0 else Color(1,0.75,0.18)
        mesh.material_override=mat; cue.add_child(mesh)
    cue.hide()
func start(aim: Vector2) -> void:
    if phase != "idle": return
    if aim.y < -0.1:
        if actor.recovery_spent: return
        actor.recovery_spent = true
        actor.jumps_used = 2
        phase = "rise_charge"
        elapsed = 0
        targets.clear()
        burst_direction = Vector3(aim.x,-aim.y,0).normalized()
        actor.velocity = Vector3.ZERO
        actor.attack_cooldown = 0.95
        actor.last_move = "HOLY IGNITION"
    elif aim.y > 0.1:
        if is_instance_valid(grenade):
            grenade.detonate()
            grenade = null
            actor.last_move = "REMOTE DETONATION"
        else:
            grenade = preload("res://scripts/teknium_holy_grenade.gd").new()
            grenade.source = actor
            actor.get_parent().add_child(grenade)
            grenade.global_position = actor.global_position + Vector3(actor.facing * 0.8,1.4,0)
            grenade.velocity = Vector3(actor.facing * 6.0,5.0,0)
            actor.last_move = "HOLY HAND GRENADE"
        actor.attack_cooldown = 0.35
    elif absf(aim.x) > 0.1:
        phase = "shadow_start"
        elapsed = 0
        targets.clear()
        actor.facing = signf(aim.x)
        burst_direction = Vector3(actor.facing,0,0)
        actor.attack_cooldown = 0.55
        actor.last_move = "SHADOW KICK"
    elif aim == Vector2.ZERO:
        actor.charging = true
        actor.charge_time = stored_charge
        actor.last_move = "CHARGING"
func store() -> void:
    if not actor.charging: return
    stored_charge = actor.charge_time
    actor.charging = false
    actor.charge_time = 0
    actor.last_move = "CHARGE STORED"
func release() -> void:
    if not actor.charging: return
    var shot = preload("res://scripts/teknium_charge_shot.gd").new()
    shot.source = actor
    shot.direction = actor.facing
    shot.power = clampf(actor.charge_time / actor.MAX_CHARGE_TIME,0,1)
    actor.get_parent().add_child(shot)
    shot.global_position = actor.global_position + Vector3(actor.facing*0.85,1.25,0)
    actor.charging = false
    actor.charge_time = 0
    stored_charge = 0
    actor.attack_cooldown = 0.28
    actor.last_move = "CHARGE RELEASE"
func before_move(delta: float, input: Dictionary) -> void:
    previous = actor.global_position
    if phase == "idle": return
    if actor.hitstun>0 or actor.freeze_remaining>0 or not actor.controls_enabled:
        cancel()
        return
    elapsed += delta
    if phase == "shadow_start":
        actor.velocity.x = 0
        if elapsed >= 0.06:
            phase = "shadow_dash"
            elapsed = 0
            ghost_clock = 0
    if phase == "shadow_dash":
        actor.velocity = burst_direction * 23.0
        actor.facing = burst_direction.x
        if elapsed >= 0.23:
            phase = "idle"
            actor.velocity *= 0.12
    if phase == "rise_charge":
        var aim := Vector3(float(input.right)-float(input.left),float(input.up)-float(input.down),0)
        if aim.length_squared() > 0.1: burst_direction = aim.normalized()
        actor.velocity = Vector3.ZERO
        if elapsed >= 0.45:
            phase = "rise_burst"
            elapsed = 0
            actor.last_move = "HOLY BURST"
    if phase == "rise_burst":
        actor.velocity = burst_direction * 20.0
        if absf(burst_direction.x)>0.1: actor.facing = signf(burst_direction.x)
        if elapsed >= 0.28:
            phase = "idle"
            actor.velocity *= 0.15
func cancel() -> void:
    phase = "idle"
    elapsed = 0
    actor.charging = false
    actor.charge_time = 0
    targets.clear()
    for ghost in ghosts:
        if is_instance_valid(ghost): ghost.queue_free()
    ghosts.clear()
    if cue: cue.hide()
func after_move(delta: float) -> void:
    if phase not in ["shadow_dash","rise_burst"]: return
    present()
    # Sweep the leading foot across actual controller travel, never past a wall.
    var view = actor._visual_root.get_node("TekniumVisual")
    var skeleton: Skeleton3D = view.model.find_children("*","Skeleton3D",true,false)[0]
    var foot: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
    if phase=="rise_burst": foot=actor.global_position+Vector3.UP+burst_direction*0.65
    var start: Vector3 = foot + previous - actor.global_position
    var steps := maxi(1,ceili(start.distance_to(foot)/0.12))
    for i in range(steps+1):
        var point: Vector3 = start.lerp(foot,float(i)/steps)
        var sphere := SphereShape3D.new(); sphere.radius=0.32 if phase=="shadow_dash" else 0.6
        var q := PhysicsShapeQueryParameters3D.new(); q.shape=sphere; q.transform.origin=point; q.collision_mask=7
        HURT.prepare(actor,q)
        for hit in actor.get_world_3d().direct_space_state.intersect_shape(q,64):
            var target = HURT.resolve(hit.collider)
            if not actor.can_hit(target) or target in targets: continue
            var ray := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP,point,1)
            ray.exclude=[actor.get_rid(),target.get_rid()]
            if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
            targets.append(target)
            hit.position=point
            HURT.deliver(target,13.0 if phase=="shadow_dash" else 12.0,Vector3(actor.facing,0.2,0) if phase=="shadow_dash" else burst_direction,5.0,hit,actor)
    ghost_clock -= delta
    if ghost_clock <= 0:
        ghost_clock = 0.045
        afterimage(view)
func present() -> void:
    cue.visible = actor.charging or phase in ["rise_charge","rise_burst"]
    cue.global_position = actor.global_position + (Vector3(actor.facing*0.85,1.25,0) if actor.charging else Vector3.UP)
    cue.scale = Vector3.ONE*(lerpf(0.3,0.9,actor.charge_time/actor.MAX_CHARGE_TIME) if actor.charging else (0.75 if phase=="rise_charge" else 1.1))
    cue.rotation.z = elapsed*8
    if phase in ["rise_charge","rise_burst"]:
        var view = actor._visual_root.get_node("TekniumVisual")
        view.magic_pose("Block" if phase=="rise_charge" else "Jump",0.2,actor.facing)
    if phase in ["shadow_start","shadow_dash"]:
        var view = actor._visual_root.get_node("TekniumVisual")
        view.magic_pose("humanoid_air_neutral/Neutral",0.18,actor.facing)
func afterimage(view) -> void:
    var ghost = view.model.duplicate()
    actor.get_parent().add_child(ghost)
    ghost.global_transform = view.model.global_transform
    ghost.add_to_group("teknium_afterimages")
    ghost.process_mode = Node.PROCESS_MODE_DISABLED
    for player in ghost.find_children("*","AnimationPlayer",true,false): player.stop(true)
    var source_skeleton: Skeleton3D = view.model.find_children("*","Skeleton3D",true,false)[0]
    var skeleton: Skeleton3D = ghost.find_children("*","Skeleton3D",true,false)[0]
    for bone in source_skeleton.get_bone_count(): skeleton.set_bone_pose(bone,source_skeleton.get_bone_pose(bone))
    var mat := StandardMaterial3D.new()
    mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color=Color(0.1,1.0,0.3,0.30)
    for mesh in ghost.find_children("*","MeshInstance3D",true,false): mesh.material_override=mat
    ghosts = ghosts.filter(func(g): return is_instance_valid(g))
    ghosts.append(ghost)
    var tween = create_tween()
    tween.tween_property(mat,"albedo_color:a",0.0,0.2)
    tween.tween_callback(ghost.queue_free)
func clear() -> void:
    cancel()
    stored_charge = 0
    actor.charging = false
    actor.charge_time = 0
    if is_instance_valid(grenade): grenade.queue_free()
    grenade = null

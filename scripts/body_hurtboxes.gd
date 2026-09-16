extends Node3D
# Pilot receiving geometry only. Layer 4 is NOT in movement/terrain masks.
# No new attack volumes, hit ledgers, immunity or damage policy live here.
var actor
var skeleton: Skeleton3D
var body: StaticBody3D
var shapes: Array[CollisionShape3D] = []
var prefix := ""
var head_end := ""
var debug_visible := false
var meshes: Array[MeshInstance3D] = []
func _ready() -> void:
    actor = get_parent()
    skeleton = actor._visual_root.find_children("*", "Skeleton3D", true, false)[0]
    prefix = "mixamorig_" if actor.character_id == "turbofit" else ""
    head_end = "mixamorig_HeadTop_End" if prefix != "" else "head_end"
    body = StaticBody3D.new()
    body.name = "DamageOnlyBody"
    body.collision_layer = 4
    body.collision_mask = 0
    body.set_meta("hurtbox_actor", actor)
    add_child(body)
    for region in ["Head", "Torso", "LeftThigh", "LeftShin", "RightThigh", "RightShin", "LeftUpperArm", "LeftForearmHand", "RightUpperArm", "RightForearmHand"]:
        var shape := CollisionShape3D.new()
        shape.name = region
        shape.shape = CapsuleShape3D.new()
        body.add_child(shape)
        shapes.append(shape)
        var mesh := MeshInstance3D.new()
        mesh.mesh = CapsuleMesh.new()
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.albedo_color = Color(1, 0.08, 0.7, 0.22)
        material.no_depth_test = true
        mesh.material_override = material
        add_child(mesh)
        meshes.append(mesh)
    sync()
func point(bone: String) -> Vector3:
    var index := skeleton.find_bone(bone)
    assert(index >= 0, "Verified pilot bone missing: " + bone)
    return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
func fit(index: int, a: Vector3, b: Vector3, radius: float) -> void:
    var shape := shapes[index]
    # World-space endpoints include the imported centimeter/rotated parents.
    # Strip inherited scale from the damage body, not from the visible rig.
    var axis := b-a
    shape.shape.radius = radius
    shape.shape.height = maxf(radius*2, axis.length()+radius*2)
    var orientation := Basis.IDENTITY if axis.length_squared() < 0.00000001 else Basis(Quaternion(Vector3.UP,axis.normalized()))
    shape.global_transform = Transform3D(orientation,(a+b)*0.5)
    shape.force_update_transform()
    meshes[index].global_transform = shape.global_transform
    meshes[index].mesh.radius = radius
    meshes[index].mesh.height = shape.shape.height
    meshes[index].visible = debug_visible and actor.visible and actor.controls_enabled
func sync() -> void:
    if not is_instance_valid(skeleton): return
    # Evaluate current visible pose; NEVER seek/restart victim animations here.
    skeleton.force_update_all_bone_transforms()
    body.global_transform = Transform3D.IDENTITY
    body.collision_layer = 4 if actor.controls_enabled and actor.stocks > 0 else 0
    var hips := point(prefix+"Hips")
    var neck := point(prefix+"Neck" if prefix != "" else "neck")
    var head := point(prefix+"Head")
    var top := point(head_end)
    var shoulder_width := point(prefix+"LeftArm").distance_to(point(prefix+"RightArm"))
    var hip_width := point(prefix+"LeftUpLeg").distance_to(point(prefix+"RightUpLeg"))
    # Head fit from CPU-skinned >60%-Head vertices of the installed meshes:
    # median lateral axis, 75th-percentile radius, trimmed longitudinal core.
    # Bone-local center excludes the long hair envelope; native scale retained.
    var head_transform := skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(prefix+"Head"))
    var head_local := Vector3(-0.157315,9.129968,1.193446) if prefix != "" else Vector3(-0.501004,11.078810,-5.389196)
    var head_radius := (12.086204 if prefix != "" else 11.854314)*head_transform.basis.x.length()
    var head_center := head_transform*head_local
    fit(0, head_center, head_center, head_radius)
    var torso_radius := shoulder_width*0.48
    fit(1, hips.lerp(neck,0.22), hips.lerp(neck,0.72), torso_radius)
    # CPU-skinned installed mesh cross-sections, >60% limb influence:
    # Tek thighs/shins ~0.13; Turbo clothed thighs 0.16, shins 0.105.
    # Separate knee segments follow bent/spread legs without an inter-leg tube.
    # Radius scales with native limb length; decorative coat outliers excluded.
    for side_index in 2:
        var side := "Left" if side_index == 0 else "Right"
        var hip := point(prefix+side+"UpLeg")
        var knee := point(prefix+side+"Leg")
        var ankle := point(prefix+side+"Foot")
        var thigh_radius := hip.distance_to(knee)*(0.259 if prefix != "" else 0.294)
        var shin_radius := knee.distance_to(ankle)*(0.192 if prefix != "" else 0.274)
        fit(2+side_index*2, hip.lerp(knee,0.10), knee.lerp(hip,0.10), thigh_radius)
        fit(3+side_index*2, knee.lerp(ankle,0.10), ankle.lerp(knee,0.10), shin_radius)
        # Actual Bobo hull/mesh witnesses touch fingers/forearms that the core
        # omitted. Add narrow anatomical limbs, never widen Bobo's attack hull.
        var shoulder := point(prefix+side+"Arm")
        var elbow := point(prefix+side+"ForeArm")
        var wrist := point(prefix+side+"Hand")
        var palm: Vector3
        if prefix != "":
            palm = point(prefix+side+"HandIndex2")
        else:
            var hand_transform := skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"))
            palm = hand_transform*(Vector3(0.508190,9.104293,0.924976) if side_index == 0 else Vector3(-0.417714,9.173387,1.516884))
        var arm_radius := shoulder.distance_to(elbow)*(0.294 if prefix != "" else 0.37)
        var forearm_radius := elbow.distance_to(wrist)*(0.236 if prefix != "" else 0.32)
        fit(6+side_index*2, shoulder.lerp(elbow,0.10), elbow, arm_radius)
        fit(7+side_index*2, elbow, palm, forearm_radius)
    body.force_update_transform()
func _process(_delta: float) -> void:
    if debug_visible: sync()

static func resolve(collider):
    return collider.get_meta("hurtbox_actor",collider) if is_instance_valid(collider) else collider
static func deliver(target, amount, direction, push, contact := {}) -> void:
    # Only real query witnesses select fitted presentation. Actor-only sinks
    # retain native alternates; damage/acceptance remain in receive_hit.
    if contact.has("position") and target.has_method("receive_contact_hit"):
        var region := ""
        var collider = contact.get("collider")
        if is_instance_valid(collider) and collider.has_meta("hurtbox_actor") and contact.has("shape"):
            var owner = collider.shape_owner_get_owner(collider.shape_find_owner(int(contact.shape)))
            if owner: region = "head" if owner.name == "Head" else "body"
        target.receive_contact_hit(amount, direction, push, contact.position, region)
    else:
        target.receive_hit(amount, direction, push)
static func deliver_capsule(target, amount, direction, push, shape, axis_point, attack_point) -> void:
    # The same closest-axis witness that accepted this overlap selects a
    # receiving surface point. It never changes radius, timing or hit ledger.
    var radius = shape.shape.radius * maxf(shape.global_basis.x.length(), shape.global_basis.z.length())
    var point = axis_point + (attack_point-axis_point).normalized()*radius
    var region := ""
    if shape.get_parent().has_meta("hurtbox_actor"):
        region = "head" if shape.name == "Head" else "body"
    target.receive_contact_hit(amount, direction, push, point, region)
static func shape_contact(space, query, hit, hits) -> Dictionary:
    # intersect_shape reports ownership, not a surface point. Ask the same
    # overlap for a manifold against this body only; no invented hull center.
    var witness := PhysicsShapeQueryParameters3D.new()
    witness.shape = query.shape
    witness.transform = query.transform
    witness.margin = query.margin
    witness.collision_mask = query.collision_mask
    var excluded: Array[RID] = query.exclude.duplicate()
    for other in hits:
        if other.rid != hit.rid: excluded.append(other.rid)
    witness.exclude = excluded
    var rest = space.get_rest_info(witness)
    if rest.is_empty() or rest.rid != hit.rid: return {}
    return {"collider":hit.collider,"shape":rest.shape,"position":rest.point}
static func prepare(source, query, damage_active := true) -> void:
    var excluded: Array[RID] = query.exclude
    for fighter in source.get_tree().get_nodes_in_group("fighters"):
        var pilot = fighter.get_node_or_null("BodyHurtboxes")
        if pilot:
            pilot.sync()
            excluded.append(fighter.get_rid())
            if not damage_active or not source.can_hit(fighter): excluded.append(pilot.body.get_rid())
    query.exclude = excluded

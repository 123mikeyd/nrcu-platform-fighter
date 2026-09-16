extends Node
# Provisional gameplay tuning; one owner and one combat clock.
const Kit=preload("res://scripts/mephisto_kit.gd")
var actor
var impulse_done := false
func route(aim: Vector2, airborne: bool, special: bool) -> String:
    return Kit.route(aim,airborne,special)
func start_kit(id: String, direction: float):
    if id=="RubberGuillotine":start_side(direction);return
    if id=="ShadowUppercut":start_down();return
    if id=="CinderToss" and actor.recovery_spent:return
    if id=="CloseTraverse" and not actor.is_grounded() and actor.tackle_spent:return
    cancel()
    move=id
    facing=direction
    actor.facing=direction
    actor.last_move=Kit.MOVES[id].label
    actor.attack_cooldown=Kit.duration(id)
    impulse_done=false
    # Reserve immediately; interrupted startup never refunds airtime resources.
    if id=="CinderToss":actor.recovery_spent=true;actor.jumps_used=2
    if id=="CloseTraverse" and not actor.is_grounded():actor.tackle_spent=true
    tick(0)
var toss_phase := ""
var toss_clock := 0.0
var toss_left_floor := false
func tick_toss(delta: float):
    toss_clock+=delta
    var v=view()
    var c=v.get_node("CompanionFacing/ShadowCompanion")
    if toss_phase=="away":
        if not actor.is_grounded():toss_left_floor=true
        var hide=smoothstep(.10,.30,toss_clock)
        c._set_form(0,lerpf(.14,1.25,hide),hide)
        if toss_left_floor and actor.is_grounded() and actor.velocity.y<=0:
            toss_phase="reform";toss_clock=0
            v.restore_toss_anchor()
            v.shadow_pose("ShadowUppercut",0,actor.facing)
            c._set_form(0,1.25,1)
    elif toss_phase=="reform":
        var reveal=smoothstep(0,.24,toss_clock)
        c._set_form(0,lerpf(1.25,.14,reveal),1.0-reveal)
        if toss_clock>=.24:cancel()
func tick_kit():
    var d=Kit.MOVES[move]
    if move=="CinderToss":
        actor.recovery_spent=true;actor.jumps_used=2
        if not impulse_done:
            view().toss_pose(elapsed,facing)
            if elapsed>=.16 and not view().get_node("CompanionFacing").top_level:view().anchor_toss()
            if elapsed>=.18 and elapsed<d.startup:actor.velocity.y=3.0
            if elapsed>=d.startup:
                impulse_done=true
                actor.velocity.y=13.0
                view().anchor_toss()
                toss_phase="away";toss_clock=0;toss_left_floor=not actor.is_grounded()
        return
    view().kit_pose(move,elapsed,facing)
    # Compact jab closes with an actual short girl-owned step, never a larger hitbox.
    if move=="PactJab" and actor.is_grounded() and elapsed>=.08 and elapsed<=d.startup+d.active:
        actor.velocity.x=facing*2.5
    if elapsed>=d.startup and not impulse_done:
        impulse_done=true
        if move=="UmberPlunge":actor.velocity.y=minf(actor.velocity.y,-12.0)
    if elapsed>=d.startup and elapsed<=d.startup+d.active:
        if move=="CloseTraverse":actor.velocity.x=facing*7.0
        var direction: Vector3=d.launch
        direction.x*=facing
        query_hand(view().kit_hand(d.hand),.28,d.damage,direction,d.kb)
        if d.get("both",false):query_hand(view().kit_hand("RightHand"),.28,d.damage,direction,d.kb)
var move := ""
var elapsed := 0.0
var facing := 1.0
var targets: Array = []
var surface := Vector3.ZERO
var valid_surface := false
var effect: Node3D
var fist: Node3D
var patch_mesh: MeshInstance3D
const FORWARD_DISTANCE := 2.8
const SIDE_DURATION := 1.15
func side_source_time(time: float) -> float:
    # Feedback revision: retain every pose, not the four-second lock.
    if time<=.42:return lerpf(0.0,(38.0-.8)/24.0,time/.42)
    if time<=.67:return (38.0-.8)/24.0+(time-.42)
    return lerpf((44.0-.8)/24.0,119.0/30.0,clampf((time-.67)/.48,0,1))
func terrain_surface() -> Dictionary:
    var exclude: Array[RID] = []
    for f in get_tree().get_nodes_in_group("fighters"): exclude.append(f.get_rid())
    var start: Vector3=actor.global_position+Vector3.UP*.5
    var finish: Vector3=start+Vector3(facing*FORWARD_DISTANCE,0,0)
    var q=PhysicsRayQueryParameters3D.create(start,finish)
    q.exclude=exclude
    q.collision_mask=3 # Companion placement sees terrain, not receiving regions.
    var space=actor.get_world_3d().direct_space_state
    if not space.intersect_ray(q).is_empty():return {}
    q.from=finish+Vector3.UP*.1
    q.to=finish-Vector3.UP*1.4
    var hit=space.intersect_ray(q)
    if hit.is_empty() or hit.normal.y<.8:return {}
    return hit
func start_down():
    cancel()
    move="ShadowUppercut"
    facing=actor.facing
    actor.last_move="SHADOW UPPERCUT"
    actor.attack_cooldown=1.3
    var hit=terrain_surface()
    valid_surface=not hit.is_empty()
    if valid_surface:
        surface=hit.position
        effect=Node3D.new()
        actor.get_parent().add_child(effect)
        effect.global_position=surface
        patch_mesh=make_patch(effect,Vector3(0,.016,0),.52)
        make_patch(effect,actor.global_position-surface+Vector3(facing*1.0,.017,-.45),.38)
        fist=preload("res://assets/mephisto/shadow_uppercut_hand.glb").instantiate()
        effect.add_child(fist)
        fist.scale=Vector3.ONE*1.4
        fist.rotation.y=facing*PI/2
        var mat=ShaderMaterial.new()
        mat.shader=preload("res://scripts/mephisto_uppercut.gdshader")
        mat.set_shader_parameter("height_min",-.396)
        mat.set_shader_parameter("height_span",.718)
        mat.set_shader_parameter("surface_y",surface.y)
        for mesh in fist.find_children("*","MeshInstance3D",true,false):mesh.material_override=mat
        fist.visible=false
    tick(0)
func make_patch(parent: Node3D, pos: Vector3, radius: float) -> MeshInstance3D:
    var mesh=MeshInstance3D.new()
    var disk=CylinderMesh.new()
    disk.top_radius=radius;disk.bottom_radius=radius;disk.height=.012;disk.radial_segments=48
    mesh.mesh=disk
    var mat=StandardMaterial3D.new()
    mat.albedo_color=Color(.022,.006,.009)
    mat.roughness=1.0
    mesh.material_override=mat
    parent.add_child(mesh);mesh.position=pos
    return mesh
func _ready(): actor=get_parent()
func view(): return actor.get_node_or_null("VisualRoot/MephistoVisual")
func start_side(direction: float):
    cancel()
    move="RubberGuillotine"
    facing=direction
    actor.facing=facing
    actor.last_move="RUBBER GUILLOTINE"
    actor.attack_cooldown=SIDE_DURATION
    tick(0)
func cancel():
    toss_phase="";toss_clock=0;toss_left_floor=false
    if actor and view():view().restore_toss_anchor()
    if is_instance_valid(effect):
        effect.visible=false
        effect.queue_free()
    effect=null
    fist=null
    patch_mesh=null
    valid_surface=false
    move=""
    elapsed=0
    targets.clear()
    if actor and view(): view().end_shadow_move()
func tick(delta: float):
    if move.is_empty() and toss_phase.is_empty():return
    if not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or is_instance_valid(actor.caught_by):
        cancel()
        return
    if not toss_phase.is_empty():tick_toss(delta)
    if move.is_empty():return
    elapsed+=delta
    if move in ["VeilCross","AirSwat","CrownHook","FallingClaw","UmberPlunge"] and actor.is_grounded():
        cancel()
        actor.landing_lag=maxf(actor.landing_lag,.12)
        return
    if elapsed>=Kit.duration(move):
        if move=="CinderToss" and not toss_phase.is_empty():
            move="";targets.clear()
        else:cancel()
        return
    var v=view()
    if not v:return
    if move not in ["RubberGuillotine","ShadowUppercut"]:
        tick_kit()
        return
    v.shadow_pose(move,side_source_time(elapsed) if move=="RubberGuillotine" else elapsed,facing)
    if move=="ShadowUppercut":
        if valid_surface and is_instance_valid(fist):
            fist.visible=elapsed>=.48 and elapsed<1.13
            var rise=smoothstep(.48,.80,elapsed)
            var fall=smoothstep(.90,1.13,elapsed)
            fist.position.y=lerpf(-.65,1.15,rise)-fall*1.8
            if elapsed>=.60 and elapsed<=.82:
                query_hand(fist.global_position+Vector3.UP*.12,.29,13.0,Vector3(facing*.15,1,0),5.2)
        return
    # Approved review frame 40 is the stretched contact pose.
    if elapsed >= .42 and elapsed <= .67:
        var hand: Vector3=v.shadow_hand()
        if absf(hand.x-actor.global_position.x)>5.0:return
        query_hand(hand,.32,11.0,Vector3(facing,.32,0),4.4)
        # The visible elastic forearm crosses close opponents while its wrist
        # is already far beyond them. Test that finite segment, not a big orb.
        query_side_forearm(v.kit_wrist("RightForeArm"),hand)
func query_side_forearm(from: Vector3, to: Vector3):
    for target in get_tree().get_nodes_in_group("fighters"):
        if target in targets or not actor.can_hit(target):continue
        if (target.global_position.x-actor.global_position.x)*facing<=0:continue
        for child in target.get_hurtbox_shapes():
            if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D:continue
            var capsule: CapsuleShape3D=child.shape
            var transform: Transform3D=child.global_transform
            var half=maxf(0,capsule.height*.5-capsule.radius)
            var a=transform*Vector3(0,-half,0)
            var b=transform*Vector3(0,half,0)
            var radius=capsule.radius*maxf(transform.basis.x.length(),transform.basis.z.length())
            var points=Geometry3D.get_closest_points_between_segments(from,to,a,b)
            if points[0].distance_to(points[1])<=radius+.18:
                targets.append(target)
                preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,11.0,Vector3(facing,.32,0),4.4,child,points[1],points[0])
                break
func query_hand(hand: Vector3, radius: float, damage: float, direction: Vector3, knockback: float):
        for target in get_tree().get_nodes_in_group("fighters"):
            if target in targets or not actor.can_hit(target):continue
            for shape in target.get_hurtbox_shapes():
                if not shape is CollisionShape3D or not shape.shape is CapsuleShape3D or shape.disabled: continue
                var half: float=maxf(0,shape.shape.height*.5-shape.shape.radius)
                var transform: Transform3D=shape.global_transform
                var nearest=Geometry3D.get_closest_point_to_segment(hand,transform*Vector3(0,-half,0),transform*Vector3(0,half,0))
                var body_radius: float=shape.shape.radius*maxf(transform.basis.x.length(),transform.basis.z.length())
                if hand.distance_to(nearest)<=body_radius+radius:
                    targets.append(target)
                    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,damage,direction,knockback,shape,nearest,hand)
                    break

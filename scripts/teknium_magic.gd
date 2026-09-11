extends Node
# Sole Teknium magic combat clock. Presentation is sought from exact source time.
const ForceProjectile = preload("res://scripts/teknium_force_projectile.gd")
const FORCE_EVENT := 0.25 # Faster anticipation only: source30 ->46.
const FORCE_SOURCE_EVENT := 16.0/24.0
const FORCE_END := FORCE_EVENT + 18.0/24.0
const GRAB_EVENT := 0.20 # Faster anticipation only: source11 ->24.
const GRAB_SOURCE_EVENT := 13.0/24.0
const START_END := GRAB_EVENT + 4.0/24.0
const LOOP_LENGTH := 30.0/24.0
const END_LENGTH := 13.0/24.0
const RELEASE_EVENT := 5.0/24.0
const GRAB_COOLDOWN := 3.5
const GRAB_RADIUS := 0.18
const TICK_INTERVAL := 0.25
const TICK_DAMAGE := 2.0
# One complete approved loop = 1.25s (about1.2s). Tunable, never indefinite.
@export_range(0.25,2.5) var hold_duration := 1.25
var phase := "idle"
var elapsed := 0.0
var facing := 1.0
var emitted := false
var cooldown := 0.0
var tick_count := 0
var victim
var anchor_offset := Vector3.ZERO
var hand_reference := Vector3.ZERO
var actor
var visual
var arcs: MeshInstance3D
var arc_width := 0.024
func _ready():
    actor = get_parent()
    visual = actor.get_node("VisualRoot/TekniumVisual")
    arcs = MeshInstance3D.new();arcs.name="LocalElectricArcs";actor.add_child(arcs)
    var material := StandardMaterial3D.new()
    material.albedo_color=Color(0.65,0.86,1.0)
    material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode=BaseMaterial3D.CULL_DISABLED
    arcs.material_override=material;arcs.visible=false
func _exit_tree():
    release_victim()
func start_force(direction: float):
    phase="force";elapsed=0;emitted=false;facing=direction
    actor.facing=facing;actor.attack_cooldown=FORCE_END+0.25
    actor.last_move="FORCE PUSH";present()
func start_grab():
    if cooldown>0 or phase!="idle":return
    cooldown=GRAB_COOLDOWN;phase="startup";elapsed=0;emitted=false;facing=actor.facing;tick_count=0
    actor.attack_cooldown=START_END+clampf(hold_duration,0.25,2.5)+END_LENGTH+0.25
    actor.last_move="ELECTRIC GRAB";present()
func present():
    match phase:
        "force":visual.magic_pose("ForcePush",force_source_time(minf(elapsed,FORCE_END)),facing)
        "startup":visual.magic_pose("GrabStart",grab_source_time(minf(elapsed,START_END)),facing)
        "hold":visual.magic_pose("GrabLoop",fmod(elapsed,LOOP_LENGTH) if elapsed>LOOP_LENGTH else elapsed,facing)
        "ending":visual.magic_pose("GrabEnd",minf(elapsed,END_LENGTH),facing)
func force_source_time(seconds: float) -> float:
    return seconds * FORCE_SOURCE_EVENT / FORCE_EVENT if seconds <= FORCE_EVENT else FORCE_SOURCE_EVENT + seconds - FORCE_EVENT
func grab_source_time(seconds: float) -> float:
    return seconds * GRAB_SOURCE_EVENT / GRAB_EVENT if seconds <= GRAB_EVENT else GRAB_SOURCE_EVENT + seconds - GRAB_EVENT
func tick(delta: float):
    cooldown=maxf(0,cooldown-delta)
    advance_phase(delta)

func advance_phase(delta: float):
    if phase=="idle":return
    if not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or is_instance_valid(actor.caught_by):
        cancel();return
    if is_instance_valid(victim) and (not actor.can_hit(victim) or victim.stocks<=0 or victim.freeze_remaining>0 or victim.global_position.distance_to(actor.global_position)>2.1):
        cancel();return
    elapsed+=delta;actor.facing=facing
    if phase=="force":
        if not emitted and elapsed+0.000001>=FORCE_EVENT:
            emitted=true;visual.magic_pose("ForcePush",FORCE_SOURCE_EVENT,facing)
            var shot=ForceProjectile.new();shot.source=actor;shot.direction=facing
            actor.get_parent().add_child(shot);shot.global_position=visual.hand_tip("RightHand")
        present()
        if elapsed+0.000001>=FORCE_END:phase="idle"
    elif phase=="startup":
        if not emitted and elapsed+0.000001>=GRAB_EVENT:
            emitted=true;visual.magic_pose("GrabStart",GRAB_SOURCE_EVENT,facing);capture()
        if elapsed+0.000001>=START_END:
            var remainder:=maxf(0,elapsed-START_END)
            phase="hold" if is_instance_valid(victim) else "ending";elapsed=0
            present()
            if remainder>0:advance_phase(remainder)
        else:present()
    elif phase=="hold":
        if not is_instance_valid(victim):cancel();return
        var bounded:=clampf(hold_duration,0.25,2.5)
        var due:=int(floor((minf(elapsed,bounded)+0.000001)/TICK_INTERVAL))
        while tick_count<due:
            tick_count+=1
            # Deliberately not receive_hit: no knockback/hitstun or freeze/immunity side effects.
            if victim.has_method("apply_status_damage"):
                victim.apply_status_damage(TICK_DAMAGE)
                if not is_instance_valid(victim): return
            else:
                victim.damage_percent=actor.CombatMathScript.apply_damage(victim.damage_percent,TICK_DAMAGE)
                victim.state_changed.emit()
        present();update_arcs()
        if elapsed+0.000001>=bounded:
            var remainder:=maxf(0,elapsed-bounded)
            phase="ending";elapsed=0;arcs.visible=false;present()
            if remainder>0:advance_phase(remainder)
    elif phase=="ending":
        present();arcs.visible=false
        if elapsed+0.000001>=RELEASE_EVENT:release_victim()
        if elapsed+0.000001>=END_LENGTH:phase="idle"
func clear_path(start: Vector3, end: Vector3, target) -> bool:
    var query:=PhysicsRayQueryParameters3D.create(start,end)
    var excluded: Array[RID] = [actor.get_rid(),target.get_rid()]
    # Fighters do not count as terrain; only the closest eligible victim captures.
    for fighter in actor.get_tree().get_nodes_in_group("fighters"):
        excluded.append(fighter.get_rid())
    query.exclude = excluded
    query.hit_from_inside=true
    return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func capture():
    var hand:Vector3=visual.hand_tip("RightHand")
    var best_distance:=INF
    var best
    for target in actor.get_tree().get_nodes_in_group("fighters"):
        if not actor.can_hit(target) or target.stocks<=0 or target.shielding or target.freeze_remaining>0 or target.grab_immunity>0 or is_instance_valid(target.caught_by):continue
        if target.teknium_magic and target.teknium_magic.phase!="idle":continue
        var offset:Vector3=target.global_position-actor.global_position
        if offset.length()>1.85 or offset.x*facing<=0:continue
        for child in target.get_children():
            if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D:continue
            var shape:CapsuleShape3D=child.shape
            var transform:Transform3D=child.global_transform
            var axis:=maxf(0,shape.height*0.5-shape.radius)
            var nearest:=Geometry3D.get_closest_point_to_segment(hand,transform*Vector3(0,-axis,0),transform*Vector3(0,axis,0))
            var radius:=shape.radius*maxf(transform.basis.x.length(),transform.basis.z.length())
            var distance:=hand.distance_to(nearest)

            if distance<=radius+GRAB_RADIUS and distance<best_distance and clear_path(actor.global_position+Vector3.UP,hand,target) and clear_path(hand,nearest,target):
                best=target;best_distance=distance
    if not is_instance_valid(best):return
    victim=best
    victim.cancel_for_grab()
    victim.caught_by=self
    victim.velocity=Vector3.ZERO
    anchor_offset=victim.global_position-actor.global_position
    hand_reference=hand-actor.global_position
    actor.add_collision_exception_with(victim);victim.add_collision_exception_with(actor)
func anchor() -> Vector3:
    # Keep the successful contact location; follow only capped hand displacement.
    var hand:Vector3=visual.hand_tip("RightHand")-actor.global_position
    var adjustment:Vector3=(hand-hand_reference).limit_length(0.25)
    adjustment.z=0
    return actor.global_position+anchor_offset+adjustment
func update_arcs():
    if not is_instance_valid(victim):arcs.visible=false;return
    var mesh:=ImmediateMesh.new()
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
    var start:Vector3=arcs.to_local(visual.hand_tip("RightHand"))
    var center:Vector3=arcs.to_local(victim.global_position+Vector3(0,1.25,0))
    for strand in 4:
        var previous:=start
        for point in range(1,7):
            var t:=point/6.0
            var next:=start.lerp(center+Vector3(0,(strand-1.5)*0.16,0.18*sin(strand)),t)
            next+=Vector3(0,sin(point*4+elapsed*32+strand)*0.055,cos(point*3+elapsed*29+strand)*0.055)*sin(t*PI)
            arc_segment(mesh,previous,next);previous=next
    # Small jagged arcs around the caught torso, never a stage-wide flash.
    for strand in 3:
        var previous:=center+Vector3(-0.28,0.36-strand*0.28,0.36)
        for point in range(1,8):
            var t:=point/7.0
            var next:=center+Vector3(-0.28+t*0.56,0.36-strand*0.28+sin(point*4+elapsed*30+strand)*0.07,0.36+sin(t*PI)*0.04)
            arc_segment(mesh,previous,next);previous=next
    mesh.surface_end();arcs.mesh=mesh;arcs.visible=true
func arc_segment(mesh: ImmediateMesh, a: Vector3, b: Vector3):
    var side:Vector3=(b-a).cross(Vector3.BACK).normalized()*arc_width*0.5
    for point in [a-side,a+side,b+side,a-side,b+side,b-side]:mesh.surface_add_vertex(point)
func release_victim():
    if is_instance_valid(victim):
        if victim.caught_by==self:
            victim.electrocution_presentation.clear()
            victim.caught_by=null;victim.grab_immunity=1.0
            victim.velocity=Vector3(0,minf(victim.velocity.y,0),0)
            victim._visual_root.position=Vector3.ZERO
            victim._resume_frozen_animation() # Resume players only; no freeze status or immunity mutation.
            # Setup/winner may stop physics immediately: do not leave the
            # designated victim clip assigned until a nonexistent next tick.
            if not victim.controls_enabled or (is_instance_valid(actor) and not actor.controls_enabled):
                victim._update_move_visuals(0.0, true)
        if is_instance_valid(actor):
            actor.remove_collision_exception_with(victim);victim.remove_collision_exception_with(actor)
    victim=null
    if is_instance_valid(arcs):arcs.visible=false
func cancel():
    release_victim();phase="idle";elapsed=0;emitted=false

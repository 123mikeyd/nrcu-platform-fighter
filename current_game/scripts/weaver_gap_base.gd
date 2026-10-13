extends Node3D
# Shared P2 geometry and full-capsule clearance helpers; match lifecycle lives in weaver_match_stage.gd.
var art
var fighters: Array = []
var decks: Array = []
var nets: Array = []
var side_decks: Array = []
var phase = "ready"
var elapsed = 0.0
var gap = 0.0
var net_y = -3.4
var net_x = 1.25
var visual_time = 0.0
var cycle_count = 0
var blocked_ticks = 0
var blockers: Array = []
var automatic = false
var freeze_stage = false
var warning_threads: Array = []
var help_panel: Label
var telemetry: Array = []

func _ready():
    process_mode=Node.PROCESS_MODE_PAUSABLE
    art=load("res://scripts/weaver_gap_art.gd").new()
    add_child(art); art.set_process(false)
    art.camera.size=20.0
    art.camera.position=Vector3(0,8,38)
    art.camera.look_at(Vector3(0,2.8,0))
    for i in 2:
        var s=-1.0 if i==0 else 1.0
        decks.append(body("InitialStone"+str(i),Vector3(s*4,-0.52,0),Vector3(8,1.04,3.8),false))
        nets.append(body("InitialWeave"+str(i),Vector3(s*1.25,-3.46,0),Vector3(2.5,0.12,3.4),true))
        side_decks.append(body("WeaverSide"+str(i),Vector3(s*12.1,2,0),Vector3(3.1,0.2,2.2),true))
    for i in 17:
        warning_threads.append(strand(self,Vector3(0,0.07,-1.6+i*0.2),Vector3(1,0.04,0.04)))
    help_panel=Label.new(); add_child(help_panel); help_panel.visible=false

func body(id: String, pos: Vector3, size: Vector3, one_way: bool) -> AnimatableBody3D:
    var b = AnimatableBody3D.new()
    b.name=id; b.position=pos; b.collision_layer=2 if one_way else 1; b.collision_mask=0
    add_child(b)
    var c=CollisionShape3D.new(); var shape=BoxShape3D.new(); shape.size=size; c.shape=shape; b.add_child(c)
    if one_way:
        b.add_to_group("pass_through_platforms")
        b.set_meta("top_y",pos.y+size.y/2)
        b.set_meta("half_width",size.x/2)
        b.set_meta("thickness",size.y)
    return b

func strand(parent: Node3D, pos: Vector3, size: Vector3) -> MeshInstance3D:
    var m=MeshInstance3D.new(); var mesh=BoxMesh.new(); mesh.size=size; m.mesh=mesh
    m.position=pos; m.material_override=art.mat(Color("c6a365"),0.35,0.65)
    parent.add_child(m)
    return m

func start_cycle():
    if phase == "ready": set_phase("warning")

func set_phase(value: String):
    phase=value; elapsed=0.0





func capsule_bounds(p) -> AABB:
    # Actual live, transformed movement collision, not feet-only clearance.
    var result=AABB(p.global_position,Vector3.ZERO)
    var first=true
    for c in p.get_children():
        if c is CollisionShape3D and not c.disabled and c.shape is CapsuleShape3D:
            var sh: CapsuleShape3D=c.shape
            var local=AABB(Vector3(-sh.radius,-sh.height/2,-sh.radius),Vector3(sh.radius*2,sh.height,sh.radius*2))
            var bounds: AABB=c.global_transform*local
            result=bounds if first else result.merge(bounds)
            first=false
    return result



func lift_blockers(next_y: float) -> Array:
    var found: Array=[]
    for p in fighters:
        if p.stocks<=0: continue
        if p.ledge_grab and p.ledge_grab.active():
            found.append(p.player_index)
            continue
        # Only a rider would be carried upward. Falling/below-net actors are not rescued.
        if not p.is_grounded() or absf(p.position.y-net_y)>0.15: continue
        var rides_net=false
        for j in p.get_slide_collision_count():
            var contact=p.get_slide_collision(j)
            if contact.get_collider() in nets and contact.get_normal().y>0.6: rides_net=true
        if not rides_net: continue
        var b: AABB=capsule_bounds(p)
        b=b.merge(AABB(b.position+Vector3(0,next_y-net_y,0),b.size)).grow(0.03)
        for s in [-1.0,1.0]:
            var stone=AABB(Vector3(s*(4+gap)-4,-1.04,-1.9),Vector3(8,1.04,3.8))
            if b.intersects(stone):
                found.append(p.player_index)
                break
    return found





func sample() -> Dictionary:
    var ps: Array=[]
    for p in fighters:
        var b=capsule_bounds(p)
        ps.append({"id":p.character_id,"position":[p.position.x,p.position.y,p.position.z],"velocity":[p.velocity.x,p.velocity.y,p.velocity.z],"grounded":p.is_grounded(),"damage":p.damage_percent,"hitstun":p.hitstun,"stocks":p.stocks,"controls":p.controls_enabled,"ledge":p.ledge_grab.phase if p.ledge_grab else "none","bounds_position":[b.position.x,b.position.y,b.position.z],"bounds_size":[b.size.x,b.size.y,b.size.z]})
    return {"phase":phase,"elapsed":elapsed,"gap":gap,"net_x":net_x,"net_y":net_y,"blockers":blockers.duplicate(),"fighters":ps}

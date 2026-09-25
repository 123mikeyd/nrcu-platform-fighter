extends RefCounted
# Player-only contact solver. Evaluates skinned sole points, not ankle height.
# Upper-body bones and approved animation resources are never edited.
const MAX_CORRECTION := 0.60
var sk: Skeleton3D
var binds := []
var points := {}
var anchors := {}
var last_facing := 0.0
var max_applied := 0.0
func setup(visual):
    sk=visual.model.find_children("*","Skeleton3D",true,false)[0]
    var mesh:MeshInstance3D=visual.model.find_children("*","MeshInstance3D",true,false)[0]
    for i in mesh.skin.get_bind_count(): binds.append([sk.find_bone(mesh.skin.get_bind_name(i)),mesh.skin.get_bind_pose(i)])
    var a=mesh.mesh.surface_get_arrays(0)
    var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
    var bones:PackedInt32Array=a[Mesh.ARRAY_BONES]
    var weights:PackedFloat32Array=a[Mesh.ARRAY_WEIGHTS]
    var stride:int=bones.size()/vertices.size()
    for side in ["Left","Right"]:
        var candidates=[]
        var low=INF
        for i in vertices.size():
            var weight=0.0
            var p={"v":vertices[i],"bones":[],"weights":[]}
            for j in stride:
                var index=bones[i*stride+j]
                var w=weights[i*stride+j]
                if w<=0:continue
                p.bones.append(index);p.weights.append(w)
                if sk.get_bone_name(binds[index][0]) in [side+"Foot",side+"ToeBase"]:weight+=w
            if weight<0.7:continue
            var pos=evaluate(p)
            low=minf(low,pos.y);candidates.append([p,pos.y])
        var sole=[]
        for p in candidates:
            if p[1]<low+0.055:sole.append(p[0])
        points[side]=[]
        for i in mini(48,sole.size()):points[side].append(sole[int(float(i)*sole.size()/mini(48,sole.size()))])
func evaluate(p) -> Vector3:
    var result=Vector3.ZERO
    for j in p.bones.size():
        var bind=binds[p.bones[j]]
        result+=(sk.get_bone_global_pose(bind[0])*bind[1]*p.v)*p.weights[j]
    return sk.global_transform*result
func sample(side) -> Vector3:
    var center=Vector3.ZERO
    var low=INF
    for p in points[side]:
        var v=evaluate(p);center+=v;low=minf(low,v.y)
    center/=points[side].size();center.y=low
    return center
func clear(hold_pose := false):
    anchors.clear()
    last_facing=0
    if is_instance_valid(sk) and not hold_pose:sk.clear_bones_global_pose_override()
func support(side:String,phase:float) -> float:
    var windows=[Vector2(.85,3.15),Vector2(3.75,5.85)] if side=="Left" else [Vector2(-.5,1.75),Vector2(2.4,4.4)]
    var amount=0.0
    for w in windows:
        for offset in [-5.5,0.0,5.5]:
            var t=phase+offset
            amount=maxf(amount,smoothstep(w.x,w.x+.25,t)*(1.0-smoothstep(w.y-.25,w.y,t)))
    return amount
func solve_leg(side:String,world_target:Vector3):
    var hip=sk.find_bone(side+"UpLeg");var knee=sk.find_bone(side+"Leg");var foot=sk.find_bone(side+"Foot")
    var h=sk.get_bone_global_pose(hip);var k=sk.get_bone_global_pose(knee);var f=sk.get_bone_global_pose(foot)
    var target=sk.global_transform.affine_inverse()*world_target
    var a=h.origin.distance_to(k.origin);var b=k.origin.distance_to(f.origin)
    # At reach limits prefer a small support replant to hovering above the floor.
    # Preserve the requested vertical ankle height and both bone lengths.
    var height=clampf(target.y-h.origin.y,-a-b+.001,a+b-.001)
    var horizontal=Vector3(target.x-h.origin.x,0,target.z-h.origin.z)
    horizontal=horizontal.limit_length(sqrt(maxf(0,(a+b-.001)*(a+b-.001)-height*height)))
    target=h.origin+horizontal+Vector3.UP*height
    var axis=(target-h.origin).normalized()
    var distance=clampf(h.origin.distance_to(target),absf(a-b)+.001,a+b-.001)
    target=h.origin+axis*distance
    var bend=(k.origin-h.origin)-axis*(k.origin-h.origin).dot(axis)
    if bend.length_squared()<.0001:bend=axis.cross(Vector3.RIGHT)
    bend=bend.normalized()
    var along=(a*a-b*b+distance*distance)/(2*distance)
    var next_knee=h.origin+axis*along+bend*sqrt(maxf(0,a*a-along*along))
    var hrot=Basis(Quaternion((k.origin-h.origin).normalized(),(next_knee-h.origin).normalized()))
    var krot=Basis(Quaternion((f.origin-k.origin).normalized(),(target-next_knee).normalized()))
    sk.set_bone_global_pose_override(hip,Transform3D(hrot*h.basis,h.origin),1,true)
    sk.set_bone_global_pose_override(knee,Transform3D(krot*k.basis,next_knee),1,true)
    sk.set_bone_global_pose_override(foot,Transform3D(f.basis,target),1,true)
    sk.force_update_all_bone_transforms()
func apply(actor,phase:float,stationary:bool,landing:bool):
    if actor.facing!=last_facing:
        anchors.clear();last_facing=actor.facing
    for side in ["Left","Right"]:
        var weight=1.0 if stationary or landing else support(side,phase)
        var original=sample(side)
        var support_point:Vector3=anchors.get(side,original)
        var query=PhysicsRayQueryParameters3D.create(Vector3(support_point.x,actor.global_position.y+.5,support_point.z),Vector3(support_point.x,actor.global_position.y-.3,support_point.z),3,[actor.get_rid()])
        var hit:Dictionary=actor.get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty() or hit.normal.y<.7:
            anchors.erase(side)
            continue
        var floor_y:float=hit.position.y+0.008
        if weight<=.001:
            anchors.erase(side)
            # Swing feet retain their lift; only prevent authored penetration.
            weight=1.0 if original.y<floor_y else 0.0
            if weight==0:continue
        if not anchors.has(side):anchors[side]=Vector3(original.x,floor_y,original.z)
        var target:Vector3=original.lerp(Vector3(anchors[side].x,floor_y,anchors[side].z),weight)
        target.y=maxf(target.y,floor_y)
        var foot=sk.find_bone(side+"Foot")
        var initial:Vector3=sk.global_transform*sk.get_bone_global_pose(foot).origin
        for iteration in 3:
            var delta=target-sample(side)
            var current:Vector3=sk.global_transform*sk.get_bone_global_pose(foot).origin
            var correction=current+delta-initial
            correction.y=clampf(correction.y,-MAX_CORRECTION,MAX_CORRECTION)
            var horizontal=Vector3(correction.x,0,correction.z).limit_length(sqrt(maxf(0,MAX_CORRECTION*MAX_CORRECTION-correction.y*correction.y)))
            correction=horizontal+Vector3.UP*correction.y
            max_applied=maxf(max_applied,correction.length())
            solve_leg(side,initial+correction)
            var actual:Vector3=sk.global_transform*sk.get_bone_global_pose(foot).origin-initial
            max_applied=maxf(max_applied,actual.length())

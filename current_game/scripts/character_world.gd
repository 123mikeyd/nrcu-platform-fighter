extends Node3D
var arena:Node3D
var moving:AnimatableBody3D
var clock=0.0
var motion_base=1.5
var motion_amplitude=0.7
var clouds:Array=[]
var world_id="hall"
func _ready():
    arena=self
    var id=0 if world_id=="hall" else 1
    if id==0:
        surface("RecessedFloor",Vector3(0,-0.6,0),Vector3(12,1.2,4),Color("414858"))
        surface("LeftWing",Vector3(-9,0.4,0),Vector3(4,1.2,4),Color("69504e"))
        surface("RightWing",Vector3(9,0.4,0),Vector3(4,1.2,4),Color("69504e"))
        ramp(-1); ramp(1)
        motion_base=2.0; motion_amplitude=0.7
        moving=surface("PerformanceRiser",Vector3(0,2,0),Vector3(4,0.3,3.2),Color("c79865"),true)
    else:
        surface("LeftBank",Vector3(-7,-1,0),Vector3(9,2,4),Color("698351"))
        surface("RightBank",Vector3(7,0,0),Vector3(9,2,4),Color("799955"))
        motion_base=0.5; motion_amplitude=0.85
        moving=surface("FlowerCrossing",Vector3(0,0.5,0),Vector3(2.8,0.3,3.4),Color("dab078"),true)
        for x in [-1.1,0,1.1]:
            var petal=box(moving,Vector3(x,-0.12,0),Vector3(1.1,0.18,3.8),Color("ba80a4")); petal.rotation.y=x*0.2
        for x in [-10,-8,-5,5,8,10]:
            box(arena,Vector3(x,1.5 if x>0 else 0.5,-1.6),Vector3(0.08,0.9,0.08),Color("638b62"))
            box(arena,Vector3(x,2 if x>0 else 1,-1.6),Vector3(0.5,0.25,0.4),Color("c799ae"))
        for i in 5:
            var c=box(arena,Vector3(-15+i*7,6+i%2,-8),Vector3(3.5,0.55,0.5),Color("9db2bc")); clouds.append(c)
    var art=preload("res://scripts/world_art.gd").new();art.name="WorldArt";art.mode=world_id;add_child(art)
    for body in get_children():
        if body is StaticBody3D and not (id==1 and body==moving):
            for visual in body.get_children():
                if visual is MeshInstance3D:visual.material_override=art.mats.get("wood" if id==0 else "grass")
func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color):
    var mesh = MeshInstance3D.new()
    var shape = BoxMesh.new(); shape.size = size; mesh.mesh = shape
    var mat = StandardMaterial3D.new(); mat.albedo_color = color; mat.roughness=0.85
    mesh.material_override=mat; mesh.position=pos; parent.add_child(mesh)
    return mesh
func surface(id: String, pos: Vector3, size: Vector3, color: Color, moving_body := false):
    var body = AnimatableBody3D.new() if moving_body else StaticBody3D.new()
    body.name = id; body.position=pos
    body.collision_layer=2 if moving_body else 1
    body.collision_mask=0
    arena.add_child(body)
    box(body,Vector3.ZERO,size,color)
    var c = CollisionShape3D.new(); var s=BoxShape3D.new(); s.size=size; c.shape=s; body.add_child(c)
    if moving_body:
        body.add_to_group("pass_through_platforms")
        body.set_meta("top_y",pos.y+size.y/2)
        body.set_meta("half_width",size.x/2)
        body.set_meta("thickness",size.y)
    return body
func ramp(side: float):
    # Exact wedge top connects floor (x=5,y=0) to wing (x=7,y=1).
    var body=StaticBody3D.new(); body.name="RampLeft" if side<0 else "RampRight"
    arena.add_child(body)
    var points=PackedVector3Array()
    for z in [-2.0,2.0]:
        for xy in [Vector2(4.8,-0.5),Vector2(7.2,-0.5),Vector2(7.2,1.0),Vector2(7,1),Vector2(5,0),Vector2(4.8,0)]:
            points.append(Vector3(xy.x*side,xy.y,z))
    var shape=ConvexPolygonShape3D.new(); shape.points=points
    var c=CollisionShape3D.new(); c.shape=shape; body.add_child(c)
    var visual=MeshInstance3D.new(); visual.mesh=shape.get_debug_mesh()
    var mat=StandardMaterial3D.new(); mat.albedo_color=Color("ac8065"); mat.cull_mode=BaseMaterial3D.CULL_DISABLED
    visual.material_override=mat; body.add_child(visual)
    # Fill the convex wedge rather than its diagnostic wire mesh.
    var st=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for base in [0,6]:
        for j in range(1,5):
            for k in [base,base+j,base+j+1]: st.add_vertex(points[k])
    for j in 6:
        var n=(j+1)%6
        for k in [j,n,n+6,j,n+6,j+6]: st.add_vertex(points[k])
    st.generate_normals(); visual.mesh=st.commit()
func _physics_process(delta):
    if get_tree().paused: return
    clock+=delta
    moving.position.y=motion_base+sin(clock*0.55)*motion_amplitude
    moving.set_meta("top_y",moving.position.y+0.15)
    for i in clouds.size(): clouds[i].position.x=-16+fposmod(i*7+clock*0.17,35)

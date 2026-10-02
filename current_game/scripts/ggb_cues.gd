extends Node3D
var material_cache={}
var effects
var jaws=[]
var needle
var spark
var ripple
func mat(color: Color) -> StandardMaterial3D:
    var key = color.to_html()
    if material_cache.has(key): return material_cache[key]
    var m = StandardMaterial3D.new()
    m.albedo_color = color
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    material_cache[key] = m
    return m

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var node = MeshInstance3D.new()
    var mesh = BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.material_override = mat(color)
    parent.add_child(node)
    node.position = pos
    return node

func triangle(parent: Node3D, vertices: Array, color: Color):
    var node = MeshInstance3D.new()
    var mesh = ImmediateMesh.new()
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat(color))
    for v in vertices: mesh.surface_add_vertex(v)
    mesh.surface_end()
    node.mesh = mesh
    parent.add_child(node)

func ring(parent: Node3D, radius: float, width: float, color: Color) -> MeshInstance3D:
    var node = MeshInstance3D.new()
    var mesh = TorusMesh.new()
    mesh.inner_radius = radius-width
    mesh.outer_radius = radius+width
    mesh.rings = 32
    mesh.ring_segments = 8
    node.mesh = mesh
    node.material_override = mat(color)
    parent.add_child(node)
    return node


func _ready():
    effects=self
    for direction in [1.0,-1.0]:
        var jaw = Node3D.new()
        effects.add_child(jaw)
        jaws.append(jaw)
        box(jaw,Vector3(0,0,0),Vector3(0.96,0.12,0.10),Color("7e3451"))
        box(jaw,Vector3(0,direction*0.018,0.065),Vector3(0.87,0.07,0.025),Color("efb7cb"))
        for j in range(4):
            var x = -0.40+j*0.215
            triangle(jaw,[Vector3(x,-direction*0.04,0.10),Vector3(x+0.19,-direction*0.04,0.10),Vector3(x+0.095,-direction*0.23,0.10)],Color("fff4d7"))
    needle = Node3D.new()
    effects.add_child(needle)
    triangle(needle,[Vector3(-0.24,-0.045,0),Vector3(0.24,0,0),Vector3(-0.24,0.045,0)],Color("fff2b0"))
    triangle(needle,[Vector3(-0.24,0,0.005),Vector3(0.24,0,0.005),Vector3(-0.24,0.045,0.005)],Color("b0ec77"))
    box(needle,Vector3(-0.31,0,0),Vector3(0.11,0.018,0.018),Color("72c79f"))
    spark = Node3D.new()
    effects.add_child(spark)
    for j in range(6):
        var ray = box(spark,Vector3.ZERO,Vector3(0.30,0.045,0.02),Color("f9e59d"))
        ray.rotation.z = j*PI/3
        ray.position = Vector3(cos(j*PI/3),sin(j*PI/3),0)*0.20
    ripple = Node3D.new()
    effects.add_child(ripple)
    for j in range(3):
        var r = ring(ripple,0.30+j*0.13,0.022,Color("bfe45f"))
        r.position.y = j*0.014
    hide_all()
func hide_all():
    for jaw in jaws: jaw.visible=false
    needle.visible=false
    spark.visible=false
    ripple.visible=false

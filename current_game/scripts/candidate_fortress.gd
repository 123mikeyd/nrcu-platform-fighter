extends Node3D
# Review-only, collision-free set dressing; authored platform bodies are untouched.
var warm := false
func material(color: Color, glow := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.metallic = 0.65
    m.roughness = 0.6
    if glow:
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        m.emission_enabled = true
        m.emission = color
    return m
func box(p: Vector3, s: Vector3, color: Color, glow := false):
    var m := BoxMesh.new(); m.size = s
    var n := MeshInstance3D.new(); n.mesh = m; n.position = p
    n.material_override = material(color,glow); add_child(n)
    return n
func cylinder(p: Vector3, radius: float, height: float, color: Color):
    var m := CylinderMesh.new(); m.top_radius = radius; m.bottom_radius = radius; m.height = height; m.radial_segments = 32
    var n := MeshInstance3D.new(); n.mesh = m; n.position = p
    n.material_override = material(color); add_child(n)
    return n
func _ready():
    name = "FortressSetDressing"
    var steel := Color("233948")
    var dark := Color("0b1825")
    var blue := Color("3ba3c6") if not warm else Color("d9a66b")
    box(Vector3(0,6,-23),Vector3(75,45,1),Color("080f1a"))
    box(Vector3(0,-3,-12),Vector3(70,0.6,22),dark)
    # Monumental pressure chambers and their ribbed collars.
    for x in [-25.0,-15.0,-5.0,5.0,15.0,25.0]:
        cylinder(Vector3(x,8,-17),3.3,32,dark)
        for y in [-5.0,0.0,5.0,10.0,15.0,20.0]:
            cylinder(Vector3(x,y,-17),3.45,0.32,steel)
            cylinder(Vector3(x,y+0.45,-17),3.36,0.15,Color("314954"))
        for offset in [-1.9,0.0,1.9]:
            box(Vector3(x+offset,8,-13.95),Vector3(0.07,26,0.08),blue,true)
            for y in range(-3,22,2):
                box(Vector3(x+offset+0.22,y,-13.9),Vector3(0.14,0.36,0.1),Color("243f50"))
        box(Vector3(x+2.4,6,-14.0),Vector3(0.1,1.4,0.1),Color("a1513b"),true)
    # Layered maintenance catwalks with fine rails (never playable surfaces).
    for y in [-1.8,6.8,14.5]:
        box(Vector3(0,y,-10),Vector3(67,0.35,2.4),steel)
        box(Vector3(0,y+1.1,-8.9),Vector3(67,0.055,0.055),Color("52707c"))
        box(Vector3(0,y+0.45,-8.9),Vector3(67,0.04,0.04),steel)
        for x in range(-32,33,2):
            box(Vector3(x,y+0.55,-8.9),Vector3(0.06,1.1,0.06),steel)
            box(Vector3(x,y-0.25,-8.8),Vector3(0.35,0.10,0.1),blue,true)
    # Foreground industrial pipes, flanges, access panels and winches.
    for x in [-13.0,13.0]:
        cylinder(Vector3(x,7,-6.0),0.45,24,steel)
        for y in range(-3,20,3): cylinder(Vector3(x,y,-6.0),0.6,0.18,Color("456071"))
        box(Vector3(x,0,-5.5),Vector3(3.5,2.5,2),dark)
        for y in range(6): box(Vector3(x,0.15*y,-4.45),Vector3(2.6,0.035,0.05),steel)
        box(Vector3(x,1.05,-4.45),Vector3(0.6,0.13,0.08),Color("bd8952"),true)
    for x in [-9.0,9.0]:
        var pipe = cylinder(Vector3(x,11,-7),0.25,10,steel)
        pipe.rotation.z = PI/2
    if warm:
        # Personal workbench, storage, quiet amber practicals; no new likenesses.
        box(Vector3(4,-0.2,-5.2),Vector3(8,0.35,2.0),Color("6a4833"))
        for x in [0.5,7.5]: box(Vector3(x,-1.5,-5.2),Vector3(0.25,2.4,1.5),steel)
        for x in [2.0,4.0,6.0]:
            box(Vector3(x,0.45,-5.6),Vector3(1.4,1,0.18),dark)
            box(Vector3(x,0.45,-5.49),Vector3(1.2,0.75,0.02),Color("486e6d"),true)

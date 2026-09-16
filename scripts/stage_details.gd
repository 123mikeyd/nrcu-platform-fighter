extends Node3D
# Original, collision-free scenic dressing. Animation lives entirely in this owner.
var level_id := "toy_room"
var clock := 0.0
var movers: Array = []
var wood: StandardMaterial3D
var cream: StandardMaterial3D
var gold: StandardMaterial3D
var stone: StandardMaterial3D
func material(color: Color, texture := "") -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.86
    if not texture.is_empty() and ResourceLoader.exists(texture): m.albedo_texture = load(texture)
    return m
func _ready():
    name = "StageDetails"
    add_to_group("stage_decor")
    wood = material(Color(0.62,0.62,0.62),"res://assets/stages/detail/woodgrain.png")
    cream = material(Color(0.56,0.48,0.33))
    gold = material(Color(0.62,0.38,0.10))
    gold.metallic = 0.45
    stone = material(Color(0.78,0.82,0.83),"res://assets/stages/detail/ivory_stone.png")
    if level_id == "toy_room": room()
    else: sky()
func node(tag: String, pos: Vector3, parent: Node = self) -> Node3D:
    var n := Node3D.new()
    n.name = tag
    parent.add_child(n)
    n.position = pos
    return n
func mesh(shape: Mesh, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    n.mesh = shape
    n.material_override = mat
    parent.add_child(n)
    n.position = pos
    return n
func box(pos: Vector3, size: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
    var shape := BoxMesh.new()
    shape.size = size
    return mesh(shape,pos,mat,parent)
func ball(pos: Vector3, size: Vector3, mat: Material, parent: Node = self):
    var shape := SphereMesh.new()
    shape.radius = 0.5
    shape.height = 1.0
    var n := mesh(shape,pos,mat,parent)
    n.scale = size
    return n
func cylinder(pos: Vector3, radius: float, height: float, mat: Material, parent: Node = self, top := -1.0):
    var shape := CylinderMesh.new()
    shape.top_radius = radius if top < 0 else top
    shape.bottom_radius = radius
    shape.height = height
    shape.radial_segments = 24
    return mesh(shape,pos,mat,parent)
func line(a: Vector3,b: Vector3,r: float,mat: Material,parent: Node = self):
    var n = cylinder((a+b)*0.5,r,a.distance_to(b),mat,parent)
    n.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
    return n
func ring(pos: Vector3,r: float,thickness: float,mat: Material,parent: Node = self):
    var shape := TorusMesh.new()
    shape.inner_radius = r-thickness
    shape.outer_radius = r+thickness
    shape.rings = 32
    shape.ring_segments = 10
    return mesh(shape,pos,mat,parent)
func moving(n: Node3D, mode: String, amount: float, speed: float):
    n.add_to_group("stage_decor_motion")
    movers.append([n, n.position, mode, amount, speed])
func _process(delta):
    clock += delta
    for m in movers:
        var n: Node3D = m[0]
        if m[2] == "sway": n.rotation.z = sin(clock*m[4]+m[1].x)*m[3]
        elif m[2] == "turn": n.rotation.y = clock*m[4]
        else: n.position = m[1]+Vector3(sin(clock*m[4])*m[3],cos(clock*m[4])*0.12,0)
func star(pos: Vector3, radius: float, parent: Node):
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in 10:
        st.set_normal(Vector3.FORWARD)
        st.add_vertex(Vector3.ZERO)
        for j in [i,i+1]:
            var a: float = j*TAU/10.0+PI/2.0
            var r := radius if j%2 == 0 else radius*0.43
            st.set_normal(Vector3.FORWARD)
            st.add_vertex(Vector3(cos(a)*r,sin(a)*r,0))
    var n = mesh(st.commit(),pos,gold,parent)
    var mat = gold.duplicate()
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    n.material_override = mat
func fabric(pos: Vector3,width: float,height: float,mat: Material,parent: Node,folds := 5.0):
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in 24:
        for j in 8:
            for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
                var u: float = (i+corner.x)/24.0
                var v: float = (j+corner.y)/8.0
                st.set_uv(Vector2(u,v))
                st.add_vertex(Vector3((u-0.5)*width,-v*height,sin(u*TAU*folds)*0.16+sin(v*PI)*0.10))
    st.generate_normals()
    var m = mat.duplicate()
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mesh(st.commit(),pos,m,parent)
func room():
    # Textured broad shelf fronts and actual horizontal tops, inset joinery.
    for p in preload("res://scripts/stage_layouts.gd").surfaces(level_id):
        box(p[0]+Vector3(0,0,p[1].z/2+0.025),Vector3(p[1].x,p[1].y*0.85,0.055),wood)
        box(p[0]+Vector3(0,p[1].y/2+0.005,0),Vector3(p[1].x,0.012,p[1].z),wood)
        for x in [-p[1].x/2+0.18,p[1].x/2-0.18]:
            for y in [-0.10,0.10]:
                var screw = cylinder(p[0]+Vector3(x,y,p[1].z/2+0.065),0.036,0.014,gold)
                screw.rotation.x = PI/2
    # Panelled lower wall with skirting and chair rail; patterned upper wall.
    var wallpaper = material(Color(0.60,0.60,0.60),"res://assets/stages/detail/star_wallpaper.png")
    wallpaper.uv1_scale = Vector3(9,2,1)
    box(Vector3(0,7,-8.77),Vector3(45,10,0.02),wallpaper)
    var panel = material(Color(0.19,0.27,0.25))
    box(Vector3(0,-0.15,-8.65),Vector3(45,3.2,0.12),panel)
    for x in range(-22,23,2):
        box(Vector3(x,-0.15,-8.53),Vector3(0.10,3.1,0.1),cream)
    for y in [-1.65,1.45]: box(Vector3(0,y,-8.45),Vector3(45,0.14,0.23),cream)
    # Window curtains are pleated triangle meshes, not slabs.
    line(Vector3(-12.8,6.6,-7.9),Vector3(-5.3,6.6,-7.9),0.08,wood)
    var curtain_mat = material(Color(0.44,0.19,0.13))
    for x in [-12.0,-6.0]:
        var curtain = node("PleatedCurtain",Vector3(x,6.5,-7.7))
        fabric(Vector3.ZERO,1.45,5.1,curtain_mat,curtain)
        moving(curtain,"sway",0.009,0.55)
        ring(Vector3(x,3.4,-7.65),0.39,0.045,gold).rotation.x = PI/2
    box(Vector3(-9,1.3,-7.8),Vector3(6.5,0.18,0.85),cream)
    # Framed, original child's drawing, tape corners, colored pencils.
    box(Vector3(2.4,3.65,-8.2),Vector3(2.8,3.52,0.16),wood)
    var art = material(Color(0.72,0.72,0.72),"res://assets/stages/detail/crayon_poster.png")
    art.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var paper := QuadMesh.new()
    paper.size = Vector2(2.6,2.6*760.0/600.0)
    var drawing = mesh(paper,Vector3(2.4,3.65,-8.08),art)
    drawing.name = "OriginalDrawing"
    for x in [1.2,3.6]:
        var tape = box(Vector3(x,5.20,-8.0),Vector3(0.55,0.18,0.03),cream)
        tape.rotation.z = 0.22 if x < 2.0 else -0.2
    # Teddy seated beside the books.
    var teddy = node("TeddyBear",Vector3(-14,0.0,-5.1))
    var fur = material(Color(0.31,0.15,0.065))
    var muzzle = material(Color(0.56,0.38,0.20))
    ball(Vector3.ZERO,Vector3(1.65,1.9,1.1),fur,teddy)
    ball(Vector3(0,1.25,0),Vector3(1.55,1.45,1.1),fur,teddy)
    for x in [-0.59,0.59]:
        ball(Vector3(x,1.85,0),Vector3(0.61,0.62,0.35),fur,teddy)
        ball(Vector3(x*1.3,-0.68,0.45),Vector3(0.75,0.65,0.85),muzzle,teddy)
        ball(Vector3(x*1.4,0.12,0),Vector3(0.57,1.1,0.6),fur,teddy)
        ball(Vector3(x*0.52,1.40,0.52),Vector3.ONE*0.12,material(Color(0.035,0.025,0.018)),teddy)
    ball(Vector3(0,1.1,0.55),Vector3(0.70,0.45,0.27),muzzle,teddy)
    ball(Vector3(0,1.23,0.72),Vector3(0.19,0.13,0.09),material(Color(0.035,0.025,0.018)),teddy)
    ring(Vector3(0,0.67,0),0.50,0.10,curtain_mat,teddy)
    # Stacking rings and alphabet blocks form two deliberately grouped toys.
    cylinder(Vector3(13.4,-1.35,-4.2),0.9,0.22,wood)
    cylinder(Vector3(13.4,-0.1,-4.2),0.10,2.4,cream)
    var colors = [Color(0.45,0.12,0.08),Color(0.53,0.31,0.06),Color(0.12,0.31,0.27),Color(0.13,0.25,0.42)]
    for i in 4: ring(Vector3(13.4,-1.05+i*0.38,-4.2),0.72-i*0.12,0.17,material(colors[i]))
    for i in 6:
        var b = node("LetterBlock",Vector3(-8.4+(i%3)*0.87,-1.3+floori(i/3.0)*0.84,-6.6))
        b.rotation.y = (i-2)*0.08
        box(Vector3.ZERO,Vector3.ONE*0.8,wood,b)
        box(Vector3(0,0,0.405),Vector3(0.65,0.65,0.015),material(colors[i%4]),b)
        var l := Label3D.new()
        l.text = ["A","B","C","1","2","3"][i]
        l.font_size = 64
        l.pixel_size = 0.008
        l.position.z = 0.43
        b.add_child(l)
    # Bedside lamp: turned foot, stem, tapered fabric shade and warm static light.
    cylinder(Vector3(11,1.94,-6),0.62,0.18,gold)
    cylinder(Vector3(11,2.65,-6),0.095,1.4,gold)
    cylinder(Vector3(11,3.42,-6),1.0,1.18,cream,self,0.53)
    ring(Vector3(11,2.85,-6),0.99,0.035,gold)
    var lamp := OmniLight3D.new()
    lamp.name = "WarmLampPool"
    lamp.position = Vector3(11,2.85,-5.6)
    lamp.light_color = Color(1,0.65,0.29)
    lamp.light_energy = 0.8
    lamp.omni_range = 5.0
    add_child(lamp)
    # Slow mobile entirely in the side/back volume, away from central silhouettes.
    var mobile = node("HangingStarMobile",Vector3(14,9,-6))
    moving(mobile,"sway",0.065,0.48)
    line(Vector3(0,2,0),Vector3.ZERO,0.018,cream,mobile)
    line(Vector3(-1.7,0,0),Vector3(1.7,0,0),0.04,wood,mobile)
    for i in 5:
        var x := -1.6+i*0.8
        var drop := 0.7+(i%3)*0.5
        line(Vector3(x,0,0),Vector3(x,-drop,0),0.012,cream,mobile)
        star(Vector3(x,-drop-0.27,0),0.32,mobile)
    # Wood planks and oval woven rug visible around the arena.
    for x in range(-18,19): box(Vector3(x,-1.835,-2),Vector3(0.017,0.015,14),wood)
    for i in 8:
        var r = ring(Vector3(0,-1.82,-3),3.4+i*0.17,0.05,material(colors[i%4]))
        r.scale = Vector3(2.4,0.35,1)
func arch(origin: Vector3, size: float):
    var p = node("DistantArcade",origin)
    p.scale = Vector3.ONE*size
    var pale = material(Color(0.42,0.53,0.56))
    var distant = material(Color(0.38,0.51,0.57),"res://assets/stages/detail/ivory_stone.png")
    for x in [-2.1,2.1]:
        cylinder(Vector3(x,1.9,0),0.35,3.8,pale,p)
        for y in [0.15,0.45,3.75]: cylinder(Vector3(x,y,0),0.48,0.18,distant,p)
        for angle in 8:
            var a := angle*TAU/8
            cylinder(Vector3(x+cos(a)*0.34,1.9,sin(a)*0.34),0.035,3.2,distant,p)
    for i in 15:
        var a := (i+0.5)*PI/15
        var brick = box(Vector3(cos(a)*2.1,3.8+sin(a)*2.1,0),Vector3(0.49,0.44,0.66),distant,p)
        brick.rotation.z = a-PI/2
    box(Vector3(0,-0.08,0),Vector3(5.8,0.35,3.5),distant,p)
    cylinder(Vector3(0,-1.2,0),0.6,2.0,pale,p,2.8)
    for i in 5:
        var vine = material(Color(0.10,0.25,0.19))
        line(Vector3(-2.5+i*0.23,0,1.0),Vector3(-2.5+i*0.23,-0.8-i*0.23,1.1),0.035,vine,p)
func sky():
    # Inlaid platform fascias, bevel courses, engraved framed panels.
    for p in preload("res://scripts/stage_layouts.gd").surfaces(level_id):
        var pos: Vector3 = p[0]
        var dim: Vector3 = p[1]
        for y in [-dim.y*0.42,dim.y*0.42]:
            box(pos+Vector3(0,y,dim.z/2+0.035),Vector3(dim.x,0.055,0.12),gold)
        var count := int(dim.x/1.5)
        for i in count:
            var x := (i-(count-1)/2.0)*(dim.x/count)
            var center := pos+Vector3(x,0,dim.z/2+0.04)
            box(center,Vector3(dim.x/count-0.13,dim.y*0.62,0.035),material(Color(0.24,0.36,0.41)))
            for y in [-dim.y*0.25,dim.y*0.25]: box(center+Vector3(0,y,0.026),Vector3(dim.x/count-0.23,0.023,0.012),gold)
            var diamond = box(center+Vector3(0,0,0.045),Vector3(0.13,0.13,0.02),gold)
            diamond.rotation.z = PI/4
        for x in [-dim.x*0.39,dim.x*0.39]:
            cylinder(pos+Vector3(x,-dim.y*0.75,0),0.12,dim.y*0.6,stone,self,0.5)
    # Repeated architecture with deliberate depth and silhouette variation.
    arch(Vector3(-14,1,-13),1.35)
    arch(Vector3(14,1,-17),1.4)
    arch(Vector3(-5,1,-28),0.95)
    arch(Vector3(6,5,-36),0.8)
    for i in 7:
        var x := -24+i*8.3
        var z := -24.0-(i%3)*9
        var y := -2.0+(i%3)*2.2
        var island = node("FloatingGarden",Vector3(x,y,z))
        island.scale = Vector3.ONE*(0.70+(i%3)*0.17)
        island.rotation.y = i*0.71
        var rock = cylinder(Vector3(0,-1.1,0),0.15,2.2,material(Color(0.32,0.42,0.47)),island,2.7)
        rock.mesh.radial_segments = 7
        var distant = material(Color(0.38,0.51,0.57))
        cylinder(Vector3.ZERO,2.7,0.22,distant,island)
        cylinder(Vector3(0,0.15,0),2.5,0.09,material(Color(0.21,0.33,0.23)),island)
        for j in 3:
            cylinder(Vector3(-1.0+j*0.7,0.35+j*0.18,0),0.19,0.4+j*0.36,distant,island)
        var grass = material(Color(0.11,0.26,0.16))
        for j in 9:
            var blade = cylinder(Vector3(-1.8+j*0.34,0.31,0.8),0.07,0.35+(j%3)*0.1,grass,island,0.0)
            blade.rotation.z = (j%3-1)*0.25
        moving(island,"drift",0.25,0.12+i*0.014)
    # Silken banners on the outer columns, outside fighter silhouettes.
    for x in [-10.8,10.8]:
        for y in [-1.7,3.6]: cylinder(Vector3(x,y,-6),0.77,0.18,gold)
        for j in 8:
            var a := j*TAU/8
            cylinder(Vector3(x+cos(a)*0.58,1,-6+sin(a)*0.58),0.065,5.1,stone)
        line(Vector3(x,4.35,-6),Vector3(x+signf(x)*1.9,4.35,-6),0.045,gold)
        var banner = node("WindBanner",Vector3(x+signf(x)*1.05,4.25,-5.9))
        fabric(Vector3.ZERO,1.5,2.4,material(Color(0.10,0.27,0.38)),banner,1.5)
        moving(banner,"sway",0.035,0.72)
        for y in [-0.2,-2.15]: box(Vector3(0,y,0.19),Vector3(1.4,0.055,0.018),gold,banner)
    # Tiny, far-away original airship; slow drift, no particles or gameplay objects.
    var ship = node("DistantAirship",Vector3(-10,9,-30))
    ball(Vector3.ZERO,Vector3(4.2,1.45,1.3),material(Color(0.56,0.46,0.27)),ship)
    for x in [-1.2,0,1.2]:
        var band = ring(Vector3(x,0,0),0.70,0.025,gold,ship)
        band.rotation.z = PI/2
    box(Vector3(0,-1,0),Vector3(1.5,0.4,0.55),wood,ship)
    for x in [-0.6,0.6]: line(Vector3(x,-0.4,0),Vector3(x,-0.9,0),0.02,gold,ship)
    moving(ship,"drift",4.0,0.065)

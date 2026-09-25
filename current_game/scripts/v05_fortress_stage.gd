extends Node3D
# Public v0.5 architecture adapter: preserves Fortress geometry, lighting and batching.
# Decorative local-only character sequence is not part of this distribution.
# Entirely geometric layered environment. No physics bodies or gameplay groups.
var steel: StandardMaterial3D
var alloy: StandardMaterial3D
var rust: StandardMaterial3D
var ribs: StandardMaterial3D
var tread: StandardMaterial3D
var dark: StandardMaterial3D
var cold: StandardMaterial3D
var amber: StandardMaterial3D
var environment: Environment
var saved_environment: Dictionary = {}
var saved_msaa: int
var shared_light_masks: Dictionary = {}
var turbine_rotor: Node3D
const TURBINE_SPEED := 0.065 # radians/sec, ~96.7 seconds per full revolution
func _process(delta):
    # Inherit the arena's pausable lifecycle. No timers, tweens, physics or globals.
    if is_visible_in_tree() and is_instance_valid(turbine_rotor):
        turbine_rotor.rotation.z = fposmod(turbine_rotor.rotation.z + delta*TURBINE_SPEED, TAU)
    # Compatibility supports depth fog (not volumetrics). Keep it beyond the
    # fighting plane as the existing camera dollies; never write camera state.
    if visible and environment:
        var camera := get_viewport().get_camera_3d()
        if camera:
            environment.fog_depth_begin = camera.global_position.z + 7.0
            environment.fog_depth_end = camera.global_position.z + 62.0
func sync_atmosphere():
    if not environment: return
    if visible:
        environment.fog_enabled = true
        environment.fog_mode = Environment.FOG_MODE_DEPTH
        environment.fog_light_color = Color("344c60")
        environment.fog_light_energy = 0.7
        environment.fog_depth_curve = 1.4
        environment.fog_density = 0.28 # Depth-mode maximum opacity, not exponential falloff.
        environment.ambient_light_energy = 0.65
        for lamp in shared_light_masks: lamp.light_cull_mask = 1
        environment.fog_sky_affect = 0.0
        get_viewport().msaa_3d = Viewport.MSAA_4X
    else:
        for key in saved_environment: environment.set(key,saved_environment[key])
        for lamp in shared_light_masks: lamp.light_cull_mask = shared_light_masks[lamp]
        get_viewport().msaa_3d = saved_msaa
func pbr(id: String, tint: Color, scale_uv: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    var prefix := "res://assets/fortress_pbr/%s/%s_1K-JPG_" % [id,id]
    m.albedo_texture = load(prefix+"Color.jpg")
    m.normal_enabled = true
    m.normal_texture = load(prefix+"NormalGL.jpg")
    m.normal_scale = 0.35
    m.roughness_texture = load(prefix+"Roughness.jpg")
    m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    m.metallic_texture = load(prefix+"Metalness.jpg")
    m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    m.metallic = 0.3
    m.albedo_color = tint
    m.uv1_triplanar = true
    m.uv1_world_triplanar = true
    m.uv1_scale = Vector3.ONE*scale_uv
    m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return m
func plain(c: Color, emission := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = 0.8
    if emission: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return m
func mesh_at(mesh: Mesh, p: Vector3, mat: Material) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    n.mesh = mesh; n.position = p; n.material_override = mat; n.layers = 2
    add_child(n)
    return n
func box(p: Vector3,s: Vector3,m: Material) -> MeshInstance3D:
    var shape := BoxMesh.new(); shape.size=s
    return mesh_at(shape,p,m)
func cyl(p: Vector3,r: float,h: float,m: Material) -> MeshInstance3D:
    var shape := CylinderMesh.new();shape.top_radius=r;shape.bottom_radius=r;shape.height=h;shape.radial_segments=96
    return mesh_at(shape,p,m)
func ring(p: Vector3,inner: float,outer: float,m: Material) -> MeshInstance3D:
    var shape := TorusMesh.new();shape.inner_radius=inner;shape.outer_radius=outer;shape.rings=80;shape.ring_segments=12
    return mesh_at(shape,p,m)
func pipe(a: Vector3,b: Vector3,r: float,m: Material):
    var n := cyl((a+b)*0.5,r,a.distance_to(b),m)
    n.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
    n.set_meta("pipe_start",a);n.set_meta("pipe_end",b);n.set_meta("pipe_radius",r)
func light(p: Vector3,c: Color,energy: float,r: float):
    var l := OmniLight3D.new();l.position=p;l.light_color=c;l.light_energy=energy;l.omni_range=r
    l.light_cull_mask = 2
    add_child(l)
func label(text: String,p: Vector3,size: int,color: Color):
    var l := Label3D.new();l.text=text;l.position=p;l.font_size=size;l.pixel_size=0.012;l.modulate=color;l.no_depth_test=false
    add_child(l)
func walk(a: Vector3,width: float):
    box(a,Vector3(width,0.16,1.1),steel)
    for h in [0.45,0.95]: pipe(a+Vector3(-width/2,h,0.58),a+Vector3(width/2,h,0.58),0.025,alloy)
    for i in range(int(width/1.5)+1):
        var x := -width/2+i*1.5
        pipe(a+Vector3(x,0,0.58),a+Vector3(x,0.95,0.58),0.028,alloy)
    box(a+Vector3(0,-0.18,0.58),Vector3(0.5,0.08,0.08),amber)
func _ready():
    name="FortressStageV2"
    process_mode = Node.PROCESS_MODE_PAUSABLE
    environment = get_parent().find_children("*","WorldEnvironment",false,false)[0].environment
    for lamp in get_parent().find_children("*","DirectionalLight3D",false,false):
        shared_light_masks[lamp] = lamp.light_cull_mask
    for key in ["fog_enabled","fog_mode","fog_depth_begin","fog_depth_end","fog_depth_curve","fog_light_color","fog_light_energy","fog_density","fog_sky_affect","ambient_light_energy"]:
        saved_environment[key]=environment.get(key)
    saved_msaa=get_viewport().msaa_3d
    visibility_changed.connect(sync_atmosphere)
    sync_atmosphere()
    steel=pbr("Metal046B",Color("53656e"),0.16)
    alloy=pbr("Metal050A",Color("74848a"),0.3)
    rust=pbr("Metal053C",Color("8b8275"),0.38)
    ribs=pbr("CorrugatedSteel009",Color("698088"),0.22)
    tread=pbr("DiamondPlate009",Color("52616a"),0.4)
    dark=plain(Color("101b23"));cold=plain(Color("50747f"),true);amber=plain(Color("dba36c"),true)
    # The shaft is a single off-centre mass, extending above and below view.
    cyl(Vector3(3,8,-23),10.5,160,steel)
    for y in [-9.0,9.5,23.0]:
        cyl(Vector3(3,y,-23),10.9,0.8,ribs)
        ring(Vector3(3,y+0.48,-23),10.4,11.0,alloy)
    # Vertical structural fins follow the curvature, not a flat facade.
    for angle in [-72.0,-48.0,-24.0,0.0,24.0,48.0,72.0]:
        var a := deg_to_rad(angle)
        var p := Vector3(3+sin(a)*10.6,7,-23+cos(a)*10.6)
        var n := box(p,Vector3(0.22,35,0.45),alloy);n.rotation.y=a
        if angle in [-48.0,24.0]:
            var strip := box(p+Vector3(0,0,0.28),Vector3(0.065,25,0.05),cold);strip.rotation.y=a
    # Monumental concentric inspection hatch: real torus relief and deep recess.
    var hatch := cyl(Vector3(3,5.7,-12.32),3.25,0.48,dark);hatch.rotation.x=PI/2
    for rr in [3.35,3.65]:
        var tor := ring(Vector3(3,5.7,-11.99),rr-0.12,rr+0.12,alloy);tor.rotation.x=PI/2
    turbine_rotor = Node3D.new()
    turbine_rotor.name = "RecessedTurbineRotor"
    turbine_rotor.position = Vector3(3,5.7,-12.0)
    turbine_rotor.process_mode = Node.PROCESS_MODE_PAUSABLE
    add_child(turbine_rotor)
    for i in 12:
        var a := i*TAU/12
        var n := box(Vector3(3+sin(a)*3.52,5.7+cos(a)*3.52,-11.8),Vector3(0.17,0.38,0.24),rust);n.rotation.z=-a
        var blade := box(Vector3(3+sin(a)*1.9,5.7+cos(a)*1.9,-12.0),Vector3(0.5,1.7,0.12),steel)
        blade.rotation.z=-a+0.3
        blade.reparent(turbine_rotor, true)
    var hub:=cyl(Vector3(3,5.7,-11.7),0.8,0.28,alloy);hub.rotation.x=PI/2

    # Small service doors and discontinuous maintenance walks establish scale.
    walk(Vector3(-6,1.7,-12.1),6.5)
    walk(Vector3(11,12.8,-15),7)
    walk(Vector3(0,17.1,-12.3),8)
    for p in [Vector3(-7,2.75,-12.3),Vector3(12,13.85,-15.2)]:
        box(p,Vector3(1.05,2,0.3),alloy)
        box(p+Vector3(0,0,0.17),Vector3(0.85,1.8,0.08),ribs)
        box(p+Vector3(0,1.1,0.25),Vector3(0.65,0.07,0.08),amber)
        light(p+Vector3(0,0.9,1),Color("ffb46e"),1.2,5)
    # Left machinery hall: stacked heat exchanger, transfer pipes, support bays.
    box(Vector3(-16,7,-20),Vector3(10,27,9),ribs)
    for y in [-3.0,5.0,14.0]:
        box(Vector3(-15,y,-14.9),Vector3(9,0.5,0.7),steel)
        walk(Vector3(-15,y+0.4,-14.1),8)
    for x in [-19.0,-14.0]:
        # Continuous risers enter anchored headers, never free cut ends.
        pipe(Vector3(x,-60,-12),Vector3(x,65,-12),0.55,rust)
        for end_y in [-60.0,65.0]:
            box(Vector3(x,end_y,-13.1),Vector3(2.2,2.6,4.0),steel)
            flange(Vector3(x,end_y+(-1.0 if end_y>0 else 1.0),-12),Vector3.UP,0.55)
        for y in [-5.0,4.0,13.0]:cyl(Vector3(x,y,-12),0.7,0.22,alloy)
    # Right diagonal service conduit deliberately breaks the symmetry.
    pipe(Vector3(13,-55,-9),Vector3(13,3,-9),0.75,steel)
    var bend: Array[Vector3] = []
    for i in 17:
        var t:=i/16.0
        bend.append(Vector3(13,3,-9).bezier_interpolate(Vector3(13,4,-9),Vector3(13.8,4.8,-9.7),Vector3(14.5,5.5,-10.3),t))
    tube(bend,0.75,steel)
    # Continue the diagonal trunk beyond every legal view into the rear bulkhead.
    pipe(Vector3(14.5,5.5,-10.3),Vector3(133,124,-112),0.75,steel)
    box(Vector3(133,124,-112),Vector3(3,3,4),steel)
    for x in [11.0,15.8]:
        box(Vector3(x,-0.5,-7.5),Vector3(2.5,3,2.5),ribs)
        box(Vector3(x,1.05,-6.2),Vector3(1.7,0.13,0.12),alloy)
        box(Vector3(x+0.65,0.5,-6.2),Vector3(0.12,0.15,0.08),amber)
    # Distant shaft enclosure and buttresses remain 3D at the widest camera.
    box(Vector3(0,9,-112),Vector3(320,300,8),dark)
    for x in [-35.0,-26.0,24.0,33.0]:
        box(Vector3(x,8,-46),Vector3(1.2,160,2),steel)
    box(Vector3(0,-45,-10),Vector3(100,2,80),dark)
    # Foreground pipes safely outside the authored combat envelope.
    for x in [-23.0,24.0]:
        pipe(Vector3(x,-70,2),Vector3(x,80,2),0.8,steel)
        for y in [-9.0,1.0,12.0,23.0]:cyl(Vector3(x,y,2),1.0,0.28,rust)
    # Dress the EXISTING mesh only; physics body, dimensions and surface top intact.
    var arena := get_parent()
    for id in ["MainPlatform","LeftPlatform","RightPlatform","TopPlatform"]:
        var body: StaticBody3D = arena.get_node(id)
        var visual: MeshInstance3D = body.get_child(0)
        visual.layers=2
        visual.material_override=tread if id=="MainPlatform" else steel
        var s: Vector3=visual.mesh.size
        # Quiet inset fascia, limited hazard markers and fasteners break up tiling.
        var fascia := box(Vector3.ZERO,Vector3(s.x-0.25,s.y*0.62,0.035),dark)
        remove_child(fascia);visual.add_child(fascia);fascia.position=Vector3(0,-0.05,s.z/2+0.022)
        for side in [-1.0,1.0]:
            var tab := box(Vector3.ZERO,Vector3(0.24,0.065,0.035),amber)
            remove_child(tab);visual.add_child(tab);tab.position=Vector3(side*(s.x/2-0.28),s.y/2-0.13,s.z/2+0.05)
        # Structural fascia is below the playable surface, attached to its visual.
        for x in [-s.x*0.36,0.0,s.x*0.36]:
            var bracket := box(Vector3.ZERO,Vector3(0.18,0.42,s.z*0.9),alloy)
            remove_child(bracket);visual.add_child(bracket);bracket.position=Vector3(x,-s.y*0.5-0.21,0)
    # Depth below the deck: suspended load-bearing trusses, no fake walkable floor.
    for x in [-7.0,7.0]:
        pipe(Vector3(x,-1.2,1),Vector3(x*0.65,-5,-2),0.18,steel)
        pipe(Vector3(x,-1.2,-2),Vector3(x*0.65,-5,-2),0.18,steel)
    pipe(Vector3(-7,-2,1.5),Vector3(7,-2,1.5),0.16,rust)
    # Pools of practical light, not a uniform blue wash across the rear hall.
    light(Vector3(-8,9,-6),Color("92b9d1"),1.25,17)
    light(Vector3(9,13,-10),Color("8fb6cc"),1.1,17)
    light(Vector3(-13,-2,-6),Color("e69a5b"),1.6,10)
    light(Vector3(2,1,5),Color("c8ced0"),0.35,12)
    # Top-directed deck light makes walkable faces read above dark fascia.
    var deck_key := DirectionalLight3D.new()
    deck_key.name = "DeckAndMachineryKey"
    deck_key.rotation_degrees = Vector3(-68,-32,0)
    deck_key.light_color = Color("9fbbcd")
    deck_key.light_energy = 1.15
    deck_key.light_cull_mask = 2
    deck_key.shadow_enabled = true
    deck_key.shadow_opacity = 0.6
    add_child(deck_key)
    var machinery_fill := DirectionalLight3D.new()
    machinery_fill.name = "MachinerySoftFill"
    machinery_fill.rotation_degrees = Vector3(-18,25,0)
    machinery_fill.light_color = Color("8ba2af")
    machinery_fill.light_energy = 0.65
    machinery_fill.light_cull_mask = 2
    add_child(machinery_fill)
    # Tiny steady distant lamps establish service scale without luminous sheets.
    for p in [Vector3(-26,18,-24.6),Vector3(24,4,-24.6),Vector3(33,-8,-24.6)]:
        box(p,Vector3(0.32,0.11,0.1),amber)
        light(p+Vector3(0,-0.35,0.6),Color("e7ae77"),0.8,3.8)
    # Readability fill targets actor layer only, not the giant background masses.
    var fighter_fill := DirectionalLight3D.new()
    fighter_fill.rotation_degrees=Vector3(-18,15,0)
    fighter_fill.light_color=Color("b8c7d8")
    fighter_fill.name = "ActorFrontFill"
    fighter_fill.light_energy=1.8
    fighter_fill.light_cull_mask=1
    add_child(fighter_fill)
    var fighter_rim := DirectionalLight3D.new()
    fighter_rim.name = "ActorWarmRim"
    fighter_rim.rotation_degrees = Vector3(-32,155,0)
    fighter_rim.light_color = Color("f2d6b8")
    fighter_rim.light_energy = 1.8
    fighter_rim.light_cull_mask = 1
    add_child(fighter_rim)
    mechanical_connections()
    integrated_apparatus()
    preload("res://scripts/fortress_infrastructure_v8.gd").build(self)
    # Architectural entrance vestibule and service deck extension.
    var entrance_first:=get_child_count()
    box(Vector3(-19.7,1.64,-8.2),Vector3(3.8,0.20,1.25),tread)
    box(Vector3(-21.7,2.75,-7.48),Vector3(1.8,2.2,0.22),steel)
    box(Vector3(-20.72,2.78,-8.15),Vector3(0.14,2.15,1.6),dark)
    box(Vector3(-20.72,3.9,-8.15),Vector3(0.35,0.18,1.7),alloy)
    box(Vector3(-20.7,3.8,-7.40),Vector3(0.20,0.06,0.04),amber)
    box(Vector3(-12,14.38,-15.1),Vector3(1.15,0.20,3.4),tread)
    box(Vector3(-12,15.38,-15.32),Vector3(1.04,1.8,0.10),dark)
    for x in [-12.62,-11.38]:box(Vector3(x,15.38,-15.20),Vector3(0.18,2.0,0.23),alloy)
    box(Vector3(-12,16.40,-15.20),Vector3(1.4,0.16,0.24),alloy)
    collect_detail(entrance_first,"ServiceEntryVestibuleV8")
    preload("res://scripts/fortress_static_batch_v8.gd").build(self)

# Finite mesh-only details, using the established licensed metal maps.
func collect_detail(first: int, title: String) -> Node3D:
    var parts := get_children().slice(first)
    var group := Node3D.new();group.name=title;add_child(group)
    for part in parts: part.reparent(group,true)
    return group

func flange(p: Vector3, axis: Vector3, radius: float):
    var basis_q := Quaternion(Vector3.UP,axis.normalized())
    for offset in [-0.12,0.12]:
        var disk := cyl(p+axis*offset,radius*1.48,0.16,alloy)
        disk.quaternion=basis_q
    var seal:=cyl(p,radius*1.37,0.065,dark);seal.quaternion=basis_q
    for i in 8:
        var a:=i*TAU/8
        var radial:=basis_q*Vector3(cos(a)*radius*1.23,0,sin(a)*radius*1.23)
        var stud:=cyl(p+radial,0.055,0.46,dark);stud.quaternion=basis_q
        for side in [-1.0,1.0]:
            var bolt:=cyl(p+radial+axis*side*0.24,0.10,0.085,rust)
            bolt.mesh=bolt.mesh.duplicate();bolt.mesh.radial_segments=6;bolt.quaternion=basis_q

func mechanical_connections():
    var first:=get_child_count()
    # Replace the reading of floating collars with joined flanges and wall saddles.
    for x in [-19.0,-14.0]:
        for y in [-5.0,4.0,13.0]:
            flange(Vector3(x,y,-12),Vector3.UP,0.55)
            box(Vector3(x,y+0.7,-14.38),Vector3(1.45,0.85,0.18),steel)
            pipe(Vector3(x,y+0.7,-14.35),Vector3(x,y+0.7,-12),0.13,alloy)
            var band:=ring(Vector3(x,y+0.7,-12),0.56,0.63,alloy)
            band.name="PipeSaddle"
            for side in [-1.0,1.0]:
                var bolt:=cyl(Vector3(x+side*0.52,y+0.7,-14.23),0.075,0.11,rust);bolt.rotation.x=PI/2
    flange(Vector3(13,1.9,-9),Vector3.UP,0.75)
    var axis:=Vector3(15.5,15.5,-13.3).normalized()
    flange(Vector3(16.6,7.6,-12.1),axis,0.75)
    # Actual casing service cover, hinge barrels, closure bolts and a local gauge.
    box(Vector3(11,0,-6.15),Vector3(1.52,1.65,0.09),steel)
    box(Vector3(11,0,-6.09),Vector3(1.32,1.45,0.06),rust)
    for y in [-0.5,0.5]:cyl(Vector3(10.33,y,-6.0),0.07,0.25,alloy)
    for y in [-0.57,0.57]:
        var bolt:=cyl(Vector3(11.5,y,-5.99),0.07,0.08,alloy);bolt.rotation.x=PI/2
    pipe(Vector3(11.36,-0.14,-5.92),Vector3(11.36,0.14,-5.92),0.04,dark)
    pipe(Vector3(11,1.1,-7.4),Vector3(11,1.7,-7.4),0.10,alloy)
    var gauge:=cyl(Vector3(11,1.8,-7.32),0.30,0.18,alloy);gauge.rotation.x=PI/2
    var face:=cyl(Vector3(11,1.8,-7.20),0.24,0.025,plain(Color("9aa89c")));face.rotation.x=PI/2
    var needle:=box(Vector3(10.96,1.86,-7.17),Vector3(0.035,0.24,0.02),dark);needle.rotation.z=-0.5
    collect_detail(first,"MechanicalConnections")

func integrated_apparatus():
    # Reference-grounded industrial equipment, not a lore claim or floating core.
    # All parts are visual-only and remain behind the unchanged fighting plane.
    var first:=get_child_count()
    var copper:=pbr("Metal053C",Color("9a6550"),0.19)
    var shell:=pbr("Metal050A",Color("545d62"),0.18)
    shell.roughness_texture=null; shell.roughness=0.78
    var hot:=plain(Color("c78a48"),true)
    var y:=4.9
    var z:=-10.5
    # Opposed horizontal terminal bodies share a continuous structural bed.
    box(Vector3(0,2.42,z),Vector3(39,0.55,3.8),steel)
    box(Vector3(0,2.10,z+1.85),Vector3(39,0.25,0.18),dark)
    for side in [-1.0,1.0]:
        var body:=cyl(Vector3(side*11.4,y,z),1.28,14.4,shell)
        body.rotation.z=PI/2
        body.name="LeftTerminal" if side<0 else "RightTerminal"
        # Tapered transitions, heavy collars and dark recessed opposing mouths.
        var neck:=cyl(Vector3(side*3.45,y,z),1.08,1.5,steel);neck.rotation.z=PI/2
        var rim:=cyl(Vector3(side*2.60,y,z),1.43,0.32,copper);rim.rotation.z=PI/2
        var mouth:=cyl(Vector3(side*2.39,y,z),1.13,0.10,dark);mouth.rotation.z=PI/2
        var bore:=cyl(Vector3(side*2.32,y,z),0.66,0.11,alloy);bore.rotation.z=PI/2
        for x in [4.35,8.0,12.5,17.8]:
            var collar:=cyl(Vector3(side*x,y,z),1.43,0.24,copper);collar.rotation.z=PI/2
            var seam:=cyl(Vector3(side*(x+0.22),y,z),1.31,0.065,dark);seam.rotation.z=PI/2
        # Paired return lines and segmented jackets break the toy-tube silhouette.
        for level in [0,1]:
            var height:float=y+1.85+level*0.73
            pipe(Vector3(side*4.5,height,z-0.5),Vector3(side*18.1,height,z-0.5),0.28 if level==0 else 0.18,copper if level==0 else alloy)
            pipe(Vector3(side*18.1,height,z-0.5),Vector3(side*18.1,y,z-0.5),0.28 if level==0 else 0.18,copper if level==0 else alloy)
            pipe(Vector3(side*4.5,height,z-0.5),Vector3(side*4.5,y+0.95,z-0.5),0.18,alloy)
            for xx in [7.8,12.5,17.6]:
                pipe(Vector3(side*xx,y+1.05,z-0.5),Vector3(side*xx,height,z-0.5),0.07,steel)
                var ring_collar:=cyl(Vector3(side*xx,height,z-0.5),0.35 if level==0 else 0.23,0.18,steel);ring_collar.rotation.z=PI/2
        var jacket:=cyl(Vector3(side*10.2,y,z),1.40,2.9,steel);jacket.rotation.z=PI/2
        for xx in [8.75,11.65]:
            var edge:=cyl(Vector3(side*xx,y,z),1.46,0.16,alloy);edge.rotation.z=PI/2
        box(Vector3(side*10.2,y+0.25,z+1.40),Vector3(1.8,0.75,0.10),rust)
        for xx in [9.48,10.92]:
            for yy in [-0.03,0.53]:
                var bolt:=cyl(Vector3(side*xx,y+yy,z+1.49),0.045,0.04,dark);bolt.rotation.x=PI/2
        # Massive saddles terminate on bed; feet continue to the hall structure.
        for x in [6.6,12.5,17.5]:
            box(Vector3(side*x,3.1,z),Vector3(0.7,1.5,2.7),alloy)
            box(Vector3(side*x,2.75,z),Vector3(1.7,0.22,3.4),rust)
            box(Vector3(side*x,-21.3,z-0.25),Vector3(0.48,46.8,0.6),steel)
            pipe(Vector3(side*x,1.9,z),Vector3(side*(x+2),-2,z),0.12,alloy)
        # Smaller grey conduits travel alongside the massive copper feed, receding.
        var feed_start:=get_child_count()
        for lane in [0,1,2]:
            var a:=Vector3(side*(18.4-lane*1.7),y-0.15+lane*0.65,z-0.3)
            var b:=Vector3(side*(34.0-lane*1.7),y+12.0+lane*0.65,-38)
            var radius:=0.82 if lane==0 else 0.31
            pipe(a,b,radius,copper if lane==0 else alloy)
            # Terminal penetration is buried in a structural service header.
            box(b,Vector3(2.7,2.5,3.0),steel)
            pipe(b,Vector3(b.x,b.y,-112),radius,copper if lane==0 else alloy)
            if lane==0:
                pipe(b,Vector3(side*30,12.4,-34),0.19,alloy)
            var axis:Vector3=(b-a).normalized()
            for t in [0.12,0.32,0.52,0.72,0.92]:
                var collar:=cyl(a.lerp(b,t),radius*1.25,0.2,rust if lane==0 else steel)
                collar.quaternion=Quaternion(Vector3.UP,axis)
        var feeds:=collect_detail(feed_start,"FeedBankLeft" if side<0 else "FeedBankRight")
        feeds.set_meta("deep_feed",true)
    # Right-hand restrained steady amber section is mechanically caged, not a core.
    var sleeve:=cyl(Vector3(5.7,y,z),1.315,2.45,hot);sleeve.rotation.z=PI/2
    sleeve.name="AmberReactionSleeve"
    for x in [4.55,4.95,5.35,5.75,6.15,6.55,6.95]:
        var hoop:=cyl(Vector3(x,y,z),1.37,0.10,copper);hoop.rotation.z=PI/2
    for a in [0.0,PI/3,2*PI/3,PI,4*PI/3,5*PI/3]:
        pipe(Vector3(4.35,y+cos(a)*1.40,z+sin(a)*1.40),Vector3(7.1,y+cos(a)*1.40,z+sin(a)*1.40),0.09,steel)
    var lamp:=OmniLight3D.new();lamp.name="ApparatusPractical";lamp.position=Vector3(5.7,4.5,-8.8)
    lamp.light_color=Color("ffae54");lamp.light_energy=3.6;lamp.omni_range=6.2;lamp.omni_attenuation=1.4;lamp.light_cull_mask=2;add_child(lamp)
    # Local spill on the saddle/bed and collar lips: no global exposure change.
    for p in [Vector3(4.4,5.7,-9.4),Vector3(7.1,5.7,-9.4),Vector3(5.7,3.3,-9.5)]:
        light(p,Color("ffad58"),1.1,3.2)
    for xx in [4.4,7.03]:
        var lip:=ring(Vector3(xx,y,z),1.27,1.45,alloy);lip.rotation.z=PI/2
    # Tiny service access makes the machine—not furniture—the inhabited scale cue.
    walk(Vector3(0,1.66,-8.7),37)
    for x in [-16.0,15.4]:
        for h in range(9): pipe(Vector3(x,0.1+h*0.19,-8.03),Vector3(x+0.44,0.1+h*0.19,-8.03),0.024,alloy)
        for dx in [0.0,0.44]:pipe(Vector3(x+dx,0,-8.03),Vector3(x+dx,1.7,-8.03),0.035,alloy)
    # Instrumentation bolted directly to the bed, no desk, seating or task light.
    box(Vector3(0,2.5,-8.55),Vector3(0.65,1.0,0.32),steel)
    box(Vector3(0,2.75,-8.36),Vector3(0.43,0.19,0.03),cold)
    for x in [-0.16,0.0,0.16]:box(Vector3(x,2.42,-8.35),Vector3(0.045,0.045,0.03),amber)

    collect_detail(first,"IntegratedApparatus")
    hall_supports(copper)

func hall_supports(copper: Material):
    var first:=get_child_count()
    # Twin service naves recede alongside, not behind the opaque turbine shaft.
    # Constant-width real bays give perspective convergence instead of a flat wall.
    var vault_mat:=pbr("Metal046B",Color("435663"),0.12)
    var window_mat:=plain(Color("263f52"),true)
    for depth in [-22.0,-34.0,-48.0,-64.0,-82.0,-100.0]:
        for side in [-1.0,1.0]:
            var center:float=side*22.0
            for dx in [-8.0,8.0]:
                box(Vector3(center+dx,-43.6,depth),Vector3(0.85,112.8,1.3),vault_mat)
                box(Vector3(center+dx,12.4,depth),Vector3(1.25,0.45,1.65),alloy)
            var path:Array[Vector3]=[]
            for step in 33:
                var a:=step*PI/32.0
                path.append(Vector3(center+8*cos(a),12.8+7*sin(a),depth))
            tube(path,0.46,vault_mat)
            # A longitudinal gallery is a tiny depth cue, not a playable ledge.
            box(Vector3(center+side*6,-1.0,depth-5),Vector3(2.0,0.25,12.0),steel)
            for rail_y in [-0.5,0.1]:
                pipe(Vector3(center+side*5,rail_y,depth+1),Vector3(center+side*5,rail_y,depth-11),0.04,alloy)
            for dz in [0.0,-4.0,-8.0]:
                pipe(Vector3(center+side*5,-1,depth+dz),Vector3(center+side*5,0.15,depth+dz),0.04,alloy)
            # Tall cold openings on the outer side, solid piers occlude each bay.
            var wx:float=center+side*7.4
            box(Vector3(wx,7,depth-5),Vector3(0.13,8,8.5),window_mat)
            for yy in [3.0,5.0,7.0,9.0,11.0]:box(Vector3(wx-side*0.10,yy,depth-5),Vector3(0.18,0.09,8.5),steel)
            for dz in [-8.0,-6.0,-4.0,-2.0]:box(Vector3(wx-side*0.12,7,depth+dz),Vector3(0.20,8,0.09),steel)
            box(Vector3(center+side*6.9,1.6,depth+0.8),Vector3(0.17,0.5,0.17),amber)
            light(Vector3(center+side*6.6,1.6,depth+1.1),Color("e6ad76"),1.2,4.8)
            # Small utility door anchors the practical to architecture.
            box(Vector3(center+side*6.5,0.2,depth),Vector3(1.0,2.2,0.18),ribs)
    for side in [-1.0,1.0]:
        for yy in [-5.0,-6.3]:
            pipe(Vector3(side*27,yy,-20),Vector3(side*27,yy,-105),0.36,copper)
            for depth in [-22.0,-34.0,-48.0,-64.0,-82.0,-100.0]:
                var collar:=cyl(Vector3(side*27,yy,depth),0.46,0.18,alloy);collar.rotation.x=PI/2
        for depth in [-20.0,-105.0]:box(Vector3(side*27,-5.6,depth),Vector3(2.0,3.5,2.0),steel)
    collect_detail(first,"ApparatusHallSupports")

func tube(path: Array[Vector3],radius: float,mat: Material):
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var sides:=24
    for i in path.size():
        var tangent:Vector3=(path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
        var right:=tangent.cross(Vector3.FORWARD).normalized()
        var up:=right.cross(tangent).normalized()
        for j in sides+1:
            var a:=j*TAU/sides
            var normal:=right*cos(a)+up*sin(a)
            st.set_normal(normal);st.set_uv(Vector2(j/float(sides),i/float(path.size()-1)))
            st.add_vertex(path[i]+normal*radius)
    for i in path.size()-1:
        for j in sides:
            var a:=i*(sides+1)+j
            for index in [a,a+sides+1,a+1,a+1,a+sides+1,a+sides+2]:st.add_index(index)
    st.generate_tangents()
    mesh_at(st.commit(),Vector3.ZERO,mat)

extends Node3D
var stage:Node3D
var mats={}
var rng=RandomNumberGenerator.new()
var mode="hall"
func _ready():
 stage=self;rng.seed=9017
 if mode=="hall":hall()
 else:meadow()
func material(key: String, color: Color, texture := "", metal := 0.0) -> StandardMaterial3D:
 if mats.has(key): return mats[key]
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = 0.88
 m.metallic = metal
 if texture != "":
  m.albedo_texture = load("res://assets/world_textures/" + texture + ".png")
  m.uv1_scale = Vector3(5, 3, 1)
 mats[key] = m
 return m

func mesh_node(label: String, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 n.name = label
 n.mesh = mesh
 n.position = pos
 n.material_override = mat
 stage.add_child(n)
 return n

func box(label: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
 var m := BoxMesh.new()
 m.size = size
 return mesh_node(label, m, pos, mat)

func sphere(label: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
 var m := SphereMesh.new()
 m.radial_segments = 12
 m.rings = 6
 m.radius = 0.5
 m.height = 1.0
 var n := mesh_node(label, m, pos, mat)
 n.scale = size
 return n

func rod(label: String, a: Vector3, b: Vector3, radius: float, mat: Material):
 var m := CylinderMesh.new()
 m.top_radius = radius
 m.bottom_radius = radius
 m.height = a.distance_to(b)
 m.radial_segments = 10
 var n := mesh_node(label, m, (a+b)/2, mat)
 var direction := (b-a).normalized()
 if absf(direction.dot(Vector3.UP)) < 0.999:
  n.quaternion = Quaternion(Vector3.UP, direction)

func light(rot: Vector3, color: Color, energy: float):
 var n := DirectionalLight3D.new()
 n.rotation_degrees = rot
 n.light_color = color
 n.light_energy = energy
 n.shadow_enabled = true
 stage.add_child(n)

func hall():
 var wood = material("wood", Color("c4b59e"), "wood")
 var wall = material("wall", Color("a7a7a3"), "concrete")
 var steel = material("steel", Color("292d31"), "", 0.65)
 var brass = material("brass", Color("9d8051"), "", 0.7)
 var black = material("black", Color("161a1d"))
 var curtain = material("curtain", Color("ad7970"), "cloth")
 box("SubstageConcrete", Vector3(0,-1.5,-58), Vector3(100,1,100), wall)
 box("Ceiling",Vector3(0,16,-10),Vector3(40,1,50),black)
 var guitar = load("res://assets/turbofit/real_guitar.glb").instantiate()
 guitar.name = "OriginalBass_BacklineDisplay"
 stage.add_child(guitar)
 guitar.position=Vector3(3.2,1.3,-8)
 guitar.scale=Vector3.ONE*0.64
 guitar.rotation.z=-0.15
 rod("BassStand",Vector3(3.2,0,-8),Vector3(3.2,1.1,-8),0.035,steel)
 box("RearPerformanceRiser", Vector3(0,-0.4,-8), Vector3(19,0.8,7), wood)
 box("BackHallWall", Vector3(0,7,-16), Vector3(40,18,0.8), wall)
 var acoustic = material("acoustic", Color("434044"), "cloth")
 for i in range(27):
  box("RearAcousticFold", Vector3((i-13)*0.63,4.4,-14.8+sin(i)*0.12), Vector3(0.65,9,0.35), acoustic)
 for y in [0.2,8.8]:
  box("BackdropFraming",Vector3(0,y,-14.5),Vector3(18,0.18,0.18),brass)
 for x in [-15.0,15.0]:
  box("SideWall", Vector3(x,6,-7), Vector3(1,16,24), wall)
  for z in [-3.0,-9.0,-15.0]:
   box("HallColumn", Vector3(x*0.90,5,z), Vector3(0.8,13,0.9), steel)
   box("Balcony", Vector3(x*0.83,4.8,z), Vector3(3.5,0.3,5.8), wood)
   rod("BalconyRail", Vector3(x*0.72,5.8,z-2.8), Vector3(x*0.72,5.8,z+2.8),0.045,brass)
 for x in [-10.3,10.3]:
  for j in range(9):
   box("PleatedSideCurtain", Vector3(x+(j-4)*0.33,4.4,-12.5+sin(j)*0.12), Vector3(0.4,9,0.3), curtain)
 for y in [7.2,7.8]:
  rod("LightingTruss",Vector3(-12,y,-7),Vector3(12,y,-7),0.07,steel)
 for x in range(-12,12):
  rod("TrussDiagonal",Vector3(x,7.2,-7),Vector3(x+1,7.8,-7),0.035,brass)
 for x in [-8.5,-6.5,6.5,8.5]:
  box("AmpCabinet",Vector3(x,1.2,-6),Vector3(1.6,2.4,1.2),black)
  for y in [0.65,1.7]:
   var speaker = sphere("SpeakerCone",Vector3(x,y,-5.36),Vector3(0.98,0.98,0.10),steel)
   var rim = TorusMesh.new()
   rim.inner_radius=0.44
   rim.outer_radius=0.5
   var ring=mesh_node("SpeakerRim",rim,speaker.position+Vector3(0,0,0.03),black)
   ring.rotation.x=PI/2
  box("AmpBrassTrim",Vector3(x,2.35,-5.35),Vector3(1.45,0.08,0.08),brass)
 # Receding backline / drum hardware establishes performance space, not a nightclub.
 var drum = CylinderMesh.new()
 drum.top_radius=0.82; drum.bottom_radius=0.82; drum.height=0.7
 var d=mesh_node("BassDrum",drum,Vector3(0,0.85,-9),curtain)
 d.rotation.x=PI/2
 for x in [-1.6,1.6]:
  rod("CymbalStand",Vector3(x,0,-9),Vector3(x,2.2,-9),0.035,steel)
  sphere("Cymbal",Vector3(x,2.2,-9),Vector3(1.1,0.07,1.1),brass)
 for x in [-8.0,-4.0,4.0,8.0]:
  box("WarmFixture",Vector3(x,7.0,-7),Vector3(0.55,0.4,0.6),black)
  var lamp=OmniLight3D.new()
  lamp.position=Vector3(x,5.8,-5)
  lamp.light_color=Color("ffc986")
  lamp.light_energy=2.3
  lamp.omni_range=7
  stage.add_child(lamp)
  var face=material("lamp",Color("ffd49a"))
  face.emission_enabled=true; face.emission=Color("ffd49a"); face.emission_energy_multiplier=0.7
  box("SteadyLampLens",Vector3(x,6.76,-6.8),Vector3(0.38,0.06,0.38),face)
 for x in [-9.6,9.6]:
  for i in range(3):
   box("DeckAccessStep",Vector3(x, -0.2-i*0.23,1.0-i*0.6),Vector3(1.2,0.25,0.7),wood)

func meadow():
 var grass=material("grass",Color("c4c8a0"),"grass")
 var earth=material("earth",Color("b2a18a"),"soil")
 var path=material("path",Color("d4c3a2"),"soil")
 var green=material("leaf",Color("243b27"))
 box("Riverbank",Vector3(0,-1.0,-74),Vector3(160,1,140),grass)
 var water=material("water",Color("729fa5"),"",0.25)
 water.roughness=0.3
 box("QuietRiver",Vector3(0,-0.43,-12),Vector3(100,0.03,3.8),water)
 for i in range(35):
  var x=rng.randf_range(-42,42)
  var z=rng.randf_range(-39,-22)
  sphere("DistantMeadowRise",Vector3(x,-0.5,z),Vector3(rng.randf_range(9,19),rng.randf_range(3,7),10),material("hills",Color("344637")))
 for i in range(55):
  var x=rng.randf_range(-27,27)
  var z=rng.randf_range(-20,-4)
  if z < -10 and z > -14: continue
  sphere("MeadowBush",Vector3(x,-0.2,z),Vector3(rng.randf_range(0.6,1.8),rng.randf_range(0.4,0.85),0.8),green)
 for x in [-15.0,16.0]:
  rod("RiverbankTree",Vector3(x,-0.5,-17),Vector3(x+0.5,6,-17),0.35,earth)
  for j in range(7):
   sphere("SoftTreeCanopy",Vector3(x+rng.randf_range(-2,2),5+rng.randf_range(0,2),-17+rng.randf_range(-1,1)),Vector3(4,3,3),green)
 # Multimeshes retain lush clusters without thousands of node/draw calls.
 var centers: Array[Vector3]=[]
 for i in range(1100):
  var x=rng.randf_range(-28,28)
  var z=rng.randf_range(-22,3.5)
  if z < -10 and z > -14: continue
  if absf(x)<8.9 and z > -2.35: continue
  if sin(x*0.7+z)*sin(z*0.5) < -0.3: continue
  centers.append(Vector3(x, -0.4 if z < -2.5 else -0.05,z))
 var stem_mesh=CylinderMesh.new()
 stem_mesh.top_radius=0.014; stem_mesh.bottom_radius=0.023; stem_mesh.height=0.46; stem_mesh.radial_segments=5
 var stems: Array[Transform3D]=[]
 var blooms: Array[Array]=[[],[],[],[]]
 for c in centers:
  var h=rng.randf_range(0.6,1.6)
  stems.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1,h,1)),c+Vector3(0,0.23*h,0)))
  var group=rng.randi_range(0,3)
  var origin=c+Vector3(0,0.46*h,0)
  for petal in range(5):
   var a=petal*TAU/5
   blooms[group].append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.13,0.065,0.13)*h),origin+Vector3(cos(a)*0.085*h,0,sin(a)*0.085*h)))
 multi("FlowerStems",stem_mesh,stems,green)
 var petal_mesh=SphereMesh.new()
 petal_mesh.radius=0.5; petal_mesh.height=1; petal_mesh.radial_segments=6; petal_mesh.rings=3
 var colors=[Color("e9d7bb"),Color("d9b36a"),Color("ba8ca9"),Color("a8b8d2")]
 for i in range(4): multi("FlowerPetals",petal_mesh,blooms[i],material("petal"+str(i),colors[i]))
 for i in range(65):
  var x=rng.randf_range(-20,20)
  sphere("RiverStone",Vector3(x,-0.38,-9.8+rng.randf_range(-0.2,0.2)),Vector3(0.5,0.24,0.4),material("stone",Color("a2a093")))

func multi(label: String, mesh: Mesh, transforms: Array, mat: Material):
 var mm=MultiMesh.new()
 mm.transform_format=MultiMesh.TRANSFORM_3D
 mm.mesh=mesh
 mm.instance_count=transforms.size()
 for i in transforms.size(): mm.set_instance_transform(i,transforms[i])
 var n=MultiMeshInstance3D.new()
 n.name=label; n.multimesh=mm; n.material_override=mat
 stage.add_child(n)


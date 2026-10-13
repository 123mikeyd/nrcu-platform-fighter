extends Node3D
## VISUAL ONLY. No collision bodies, combat, or changes to production assets.
const PERIOD = 22.0
const FPS = 30.0
var god
var sk: Skeleton3D
var camera: Camera3D
var decks: Array = []
var inner_anchors: Array = []
var movers: Array = []
var fingers: Array = []
var dust: Array = []
var rope: ImmediateMesh
var thread_mat: StandardMaterial3D
var frame = 0
var clock = 0.0
var paused = false
var capture = false
var validate = false
var still = -1.0
var closeup = false
var telemetry: Array = []
var gap = 0.0
var external_gap = -1.0
var grip = 0.0
var tension = 0.0
var sag = 0.0
var finish = false
var runtime_check = false
var runtime_start = 0
var release_origins: Array = []
var routes: Array = []
var lower_closure = 0.0
var release_ends: Array = []
var release_visibility = 0.0
var wrist_angle = 0.0

func mat(c: Color, metal = 0.0, rough = 0.6) -> StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.albedo_color = c
 m.metallic = metal
 m.roughness = rough
 return m

func _ready():
 var args = OS.get_cmdline_user_args()
 runtime_check = "--runtime-check" in args
 runtime_start = Time.get_ticks_msec()
 capture = "--capture" in args
 validate = "--validate" in args
 closeup = "--closeup" in args
 for a in args:
  if a.begins_with("--still="): still = float(a.split("=")[1])
 var env = WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("030913")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("7194ad")
 env.environment.ambient_light_energy = 0.18
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 add_child(env)
 camera = Camera3D.new()
 add_child(camera)
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 18.0
 camera.position = Vector3(0,11.5,38)
 camera.look_at(Vector3(0,4.1,0))
 camera.current = true
 var key = DirectionalLight3D.new()
 add_child(key)
 key.rotation_degrees = Vector3(-28,-24,0)
 key.light_color = Color("ffe1ac")
 key.light_energy = 0.8
 key.shadow_enabled = true
 var rim = DirectionalLight3D.new()
 add_child(rim)
 rim.rotation_degrees = Vector3(15,150,0)
 rim.light_color = Color("6eacdd")
 rim.light_energy = 0.45
 var fill = OmniLight3D.new()
 add_child(fill)
 fill.position = Vector3(0,7,8)
 fill.omni_range = 26
 fill.light_color = Color("e8c392")
 fill.light_energy = 0.12
 god = load("res://scripts/weaver_gap_god.gd").new()
 add_child(god)
 var setup_ok: bool = god.setup(self,0.8,-2.0)
 assert(setup_ok)
 god.model.scale = Vector3.ONE*12.0
 god.model.position = Vector3(0,0.8-0.95*12,-2.0)
 sk = god.sk
 build_fingers()
 background()
 for side in [-1,1]:
  var deck = slab(8.0,3.8,side)
  decks.append(deck)
  var anchors: Array = []
  for n in 11:
   var marker = Marker3D.new()
   marker.name = "InvisibleInnerAnchor_%02d" % n
   marker.position = Vector3(-side*(4.0-0.12-float(n)/10.0*0.65),-0.15,-1.0+float(n)/10.0*1.8)
   deck.add_child(marker)
   anchors.append(marker)
  inner_anchors.append(anchors)
  var mover = slab(3.1,2.2,side)
  movers.append(mover)
 var mi = MeshInstance3D.new()
 rope = ImmediateMesh.new()
 mi.mesh = rope
 mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(mi)
 thread_mat = mat(Color(0.82,0.64,0.30),0.45,0.52)
 thread_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 thread_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 for i in 38:
  var d = MeshInstance3D.new()
  var sph = SphereMesh.new()
  sph.radius = 0.035 + float(i%4)*0.016
  sph.height = sph.radius*2.0
  d.mesh = sph
  d.material_override = mat(Color(0.38,0.42,0.39,0.25))
  d.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  add_child(d)
  dust.append(d)
 if capture: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/frames"))
 update_scene(0.0)
 print("AUDITION_READY finger_bones=",fingers.size()," duration=",PERIOD)

func background():
 var mi = MeshInstance3D.new()
 var quad = QuadMesh.new()
 quad.size = Vector2(80,45)
 mi.mesh = quad
 mi.position = Vector3(0,5,-12)
 var sm = ShaderMaterial.new()
 var sh = Shader.new()
 sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment(){
 vec2 p=(UV-vec2(0.5,0.43))*vec2(1.777,1.0);
 float r=length(p); float a=atan(p.y,p.x);
 float mist=exp(-r*7.0);
 float rays=pow(max(0.0,sin(a*96.0)),20.0)*smoothstep(0.06,0.1,r)*(1.0-smoothstep(0.15,0.33,r));
 vec3 col=vec3(0.007,0.016,0.029)+mist*vec3(0.034,0.074,0.096)+rays*vec3(0.039,0.033,0.020);
 ALBEDO=col;
}"""
 sm.shader = sh
 mi.material_override = sm
 add_child(mi)
 # Sparse remote gold motes, deterministic positions, no UI.
 var rng = RandomNumberGenerator.new()
 rng.seed = 78124
 for i in 95:
  var star = MeshInstance3D.new()
  var q = QuadMesh.new()
  q.size = Vector2.ONE*rng.randf_range(0.014,0.035)
  star.mesh = q
  star.position = Vector3(rng.randf_range(-22,22),rng.randf_range(-5,16),-10)
  var m = mat(Color(0.25,0.28,0.29))
  m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  star.material_override = m
  add_child(star)

func slab(width: float, depth: float, side: int) -> Node3D:
 var node = Node3D.new()
 add_child(node)
 var mesh = MeshInstance3D.new()
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 # Planar top with beveled, faceted rock below; straight inner edge, no posts.
 var points = [Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(width/2,0,depth/2),Vector3(-width/2,0,depth/2)]
 for ids in [[0,1,2],[0,2,3]]:
  for id in ids: st.add_vertex(points[id])
 for i in 4:
  var a: Vector3 = points[i]
  var b: Vector3 = points[(i+1)%4]
  var c = Vector3(b.x*0.88,-0.9-float(i%2)*0.27,b.z*0.8)
  var d = Vector3(a.x*0.88,-0.9-float((i+1)%2)*0.27,a.z*0.8)
  # Main halves meet through their depth, not only along the top lip.
  # Keep the outer taper and the small suspended decks unchanged.
  if width > 7.0:
   if b.x*side < 0.0: c = Vector3(b.x,-1.035,b.z*0.8)
   if a.x*side < 0.0: d = Vector3(a.x,-1.035,a.z*0.8)
  for v in [a,c,b,a,d,c]: st.add_vertex(v)
 st.generate_normals()
 mesh.mesh = st.commit()
 mesh.material_override = god.marble_material(false,0,Color("7f9d92"))
 node.add_child(mesh)
 var trim = MeshInstance3D.new()
 var box = BoxMesh.new()
 box.size = Vector3(width+0.01,0.055,depth+0.01)
 trim.mesh = box
 trim.position.y = -0.13
 trim.material_override = mat(Color("907347"),0.72,0.4)
 node.add_child(trim)
 # Individual inset face blocks add scale without obscuring the silhouette.
 for i in int(width):
  var face = MeshInstance3D.new()
  var b = BoxMesh.new()
  b.size = Vector3(0.7,0.28,0.07)
  face.mesh = b
  face.position = Vector3(-width/2+0.5+i,-0.44,depth/2-0.11)
  face.material_override = mat(Color("3f514e"),0.25)
  node.add_child(face)
 return node

func build_fingers():
 for prefix in ["","top_","low_"]:
  for side in ["L","R"]:
   var hand = sk.find_bone(prefix+"hand."+side)
   var ht = sk.get_bone_global_rest(hand)
   var target = ht.origin + ht.basis.y*0.05 + ht.basis.z*0.032
   for f in ["f_index","f_middle","f_ring","f_pinky","thumb"]:
    var base = sk.find_bone(prefix+f+".01."+side)
    var bt = sk.get_bone_global_rest(base)
    var axis = bt.basis.y.cross(target-bt.origin).normalized()
    for joint in [1,2,3]:
     var id = sk.find_bone(prefix+f+".0"+str(joint)+"."+side)
     var gt = sk.get_bone_global_rest(id)
     var local_axis = (gt.basis.inverse()*axis).normalized()
     fingers.append({"id":id,"name":sk.get_bone_name(id),"rest":sk.get_bone_rest(id).basis.get_rotation_quaternion(),"axis":local_axis,"joint":joint,"finger":f,"prefix":prefix})

func phase_ease(a: float,b: float,t: float) -> float:
 return smoothstep(a,b,t)

func soft_ease(a: float,b: float,t: float) -> float:
 # Zero velocity AND acceleration at the held ends: weight, not a snap.
 var u: float = clampf((t-a)/(b-a),0.0,1.0)
 return u*u*u*(u*(u*6.0-15.0)+10.0)

func hand_point(prefix: String,side: String) -> Vector3:
 var i = sk.find_bone(prefix+"hand."+side)
 var ht = sk.get_bone_global_pose(i)
 # Rope runs inside the closing palm, not at fingertips.
 return sk.global_transform*(ht.origin+ht.basis.y*0.058+ht.basis.z*0.026)

func update_scene(t: float):
 gap = external_gap if external_gap >= 0 else 2.35*phase_ease(2.0,5.0,t)*(1.0-soft_ease(12.5,16.5,t))
 grip = phase_ease(7.2,9.5,t)*(1.0-phase_ease(19.5,21.7,t))
 tension = phase_ease(10.0,12.0,t)*(1.0-phase_ease(18.5,21.7,t))
 sag = (2.3*(1.0-tension)+0.12)*clampf(gap/2.35,0,1)
 var pull = phase_ease(10.0,15.5,t)*(1.0-phase_ease(19.0,21.7,t))
 # Deliberate reach, exploratory pinch, reopen, final grasp, then haul.
 var reach = phase_ease(3.2,4.8,t)*(1.0-phase_ease(7.0,8.2,t))
 var explore = phase_ease(5.0,5.8,t)*(1.0-phase_ease(6.2,7.0,t))
 var release = 1.0-phase_ease(2.0,2.65,t)
 lower_closure = maxf(maxf(release*0.86,explore*0.68),grip)
 lower_closure = maxf(lower_closure,phase_ease(20.5,22.0,t)*0.86)
 wrist_angle = 28.0*reach-17.0*explore-12.0*pull
 for k in god.ARMS:
  var a = god.ARMS[k]
  var side: float = a.side
  var amount = sin(t*TAU/11.0)*0.5+0.5
  if a.job == "mover":
   god._rot(a.upper,-side*deg_to_rad(1.5)*amount)
   god._rot(a.fore,-side*deg_to_rad(2.5)*amount)
  elif a.job == "main":
   god._rot(a.upper,side*deg_to_rad(0.65)*sin(t*TAU/22.0))
   god._rot(a.fore,side*deg_to_rad(0.8)*sin(t*TAU/22.0))
  else:
   # Spread upper arms in the probed screen-plane axis. Forearms fold
   # inward AND toward camera, rather than folding up into the middle pair.
   god._rot(a.upper,side*deg_to_rad(10.0+8.0*reach-12.0*pull))
   god._rot(a.fore,0.0)
   sk.force_update_all_bone_transforms()
   var fi: int = sk.find_bone(a.fore)
   var ft: Transform3D = sk.get_bone_global_pose(fi)
   var direction = Vector3(-side*0.42,0.32+0.18*reach-0.42*pull,0.85).normalized()
   var swing = Quaternion(ft.basis.y.normalized(),direction)
   var parent_basis: Basis = sk.get_bone_global_pose(sk.get_bone_parent(fi)).basis
   var aimed_basis: Basis = Basis(swing)*ft.basis
   sk.set_bone_pose_rotation(fi,(parent_basis.inverse()*aimed_basis).get_rotation_quaternion())
   var bn = "low_hand."+("L" if side>0 else "R")
   var id = sk.find_bone(bn)
   var rest = sk.get_bone_rest(id).basis.get_rotation_quaternion()
   # A five-frame search offset only; preserve final grip and haul timing.
   var search_t: float = t-(0.16 if side<0.0 else 0.0)
   var wrist_reach: float = phase_ease(3.2,4.8,search_t)*(1.0-phase_ease(7.0,8.2,search_t))
   var wrist_explore: float = phase_ease(5.0,5.8,search_t)*(1.0-phase_ease(6.2,7.0,search_t))
   var local_wrist: float = 28.0*wrist_reach-17.0*wrist_explore-12.0*pull
   sk.set_bone_pose_rotation(id,rest*Quaternion(Vector3.UP,deg_to_rad(local_wrist)*side))
 for f in fingers:
  var g = lower_closure if f.prefix == "low_" else 0.82
  if f.prefix == "low_" and explore>0 and grip==0 and f.finger in ["f_ring","f_pinky"]: g = explore*0.20
  var delay = {"f_pinky":0.0,"f_ring":0.07,"f_middle":0.14,"f_index":0.21,"thumb":0.36}[f.finger]
  var closure = smoothstep(float(delay),1.0,g)
  var angle = [0.0,0.92,1.20,0.83][f.joint]*closure
  if f.finger == "thumb": angle *= 0.72
  sk.set_bone_pose_rotation(f.id,f.rest*Quaternion(f.axis,angle))
 sk.force_update_all_bone_transforms()
 for i in 2:
  var s = -1.0 if i==0 else 1.0
  var settle = sin((t-16.5)*18.0)*exp(-(t-16.5)*5.0)*0.035 if t>16.5 else 0.0
  decks[i].position = Vector3(s*(4+gap),0,0)
  var phase = sin(t*TAU/11.0)*0.5+0.5
  movers[i].position = Vector3(s*12.1,2.1+phase*1.5,1.0)
 rope.clear_surfaces()
 routes.clear()
 release_ends.clear()
 release_visibility = (1.0-phase_ease(2.5,3.35,t)) if t<4 else phase_ease(21.0,22.0,t)
 if release_origins.is_empty():
  release_origins = [hand_point("low_","R"),hand_point("low_","L")]
 rope.surface_begin(Mesh.PRIMITIVE_TRIANGLES,thread_mat)
 for i in 2:
  var s = -1.0 if i==0 else 1.0
  var side = "R" if i==0 else "L"
  for n in 19:
   var u = float(n)/18.0
   var spread = (u-0.5)*0.15
   var h = hand_point("top_",side)+Vector3(spread,0,0)
   routed("top_offscreen",h,Vector3(s*(13+u*1.5),18,-3+u),0.05,0.008)
   var mh = hand_point("",side)+Vector3(spread,0,0)
   routed("middle_offscreen",mh,Vector3(s*(20+u),18,-2),0.02,0.008)
   # Separate suspension fans at the OUTSIDE rim; no visible hidden route.
   var rim = movers[i].position+Vector3(s*(1.55-0.04),-0.09,-0.98+u*1.96)
   routed("side_rim_offscreen",rim,Vector3(s*(21+u*2),18,1+u),0.03,0.010)
   if release_visibility>0.001:
    var lh = hand_point("low_",side)+Vector3(spread,0,0)
    if t>2.0 and t<4.0:
     var dt = t-2.0
     lh = release_origins[i]+Vector3(spread+s*dt*0.28,-0.18-2.8*dt*dt,0)
    if n==9: release_ends.append([lh.x,lh.y,lh.z])
    routed("lower_released" if t>2 and t<4 else "lower_initial",lh,lh+Vector3(s*(2.0+u),-7.0,1.0+u),0.12,0.010*release_visibility)
 if gap > 0.001:
  for n in 24:
   var u = float(n)/23.0
   var a = Vector3(-gap-0.08-u*0.35,-0.30-u*0.05,-1.6+u*3)
   var b = Vector3(gap+0.08+(1-u)*0.35,-0.30-u*0.05,-1.6+u*3)
   # Fine strands disappear into the seam instead of switching off as a stack.
   line_curve(a,b,sag*(0.8+u*0.25),0.014*smoothstep(0.0,0.18,gap))
 rope.surface_end()
 for i in dust.size():
  var d: MeshInstance3D = dust[i]
  var dt = t-16.45-float(i%5)*0.03
  d.visible = dt>0 and dt<1.3
  if d.visible:
   d.position = Vector3(sin(i*7.13)*dt*1.7,0.03+dt*0.42-dt*dt*0.4,2.0+float(i%9)*0.3)
   d.scale = Vector3.ONE*(1+dt*2.0)
   d.material_override.albedo_color.a = 0.18*(1-dt/1.3)
 if closeup:
  var h = hand_point("low_","L")
  camera.size = 3.0
  camera.position = h+Vector3(0.8,0.4,12)
  camera.look_at(h)

func line_curve(a: Vector3,b: Vector3,drop: float,width: float):
 for j in 18:
  var u = float(j)/18.0
  var v = float(j+1)/18.0
  var p = a.lerp(b,u)+Vector3(0,-4*drop*u*(1-u),0)
  var q = a.lerp(b,v)+Vector3(0,-4*drop*v*(1-v),0)
  var d = q-p
  var n = Vector3(-d.y,d.x,0).normalized()*width*0.5
  for vert in [p-n,p+n,q+n,p-n,q+n,q-n]: rope.surface_add_vertex(vert)

func routed(kind: String,a: Vector3,b: Vector3,drop: float,width: float):
 routes.append({"kind":kind,"a":[a.x,a.y,a.z],"b":[b.x,b.y,b.z]})
 line_curve(a,b,drop,width)

func row(t: float) -> Dictionary:
 var angles = {}
 for f in fingers:
  var id: int = f.id
  angles[f.name] = rad_to_deg(sk.get_bone_rest(id).basis.get_rotation_quaternion().angle_to(sk.get_bone_pose_rotation(id)))
 var h = hand_point("low_","L")
 var top = hand_point("top_","L")
 var mh = hand_point("","L")
 return {"time":t,"gap_half":gap,"grip":grip,"lower_closure":lower_closure,"wrist_degrees":wrist_angle,"tension":tension,"sag":sag,"repair_hand":[h.x,h.y,h.z],"top_hand":[top.x,top.y,top.z],"mover_hand_y":mh.y,"mover_y":movers[1].position.y,"finger_degrees":angles,"routes":routes.duplicate(true),"release_visibility":release_visibility,"release_ends":release_ends.duplicate(true)}

func _process(delta):
 if finish: return
 if Input.is_action_just_pressed("ui_cancel"): get_tree().quit()
 if Input.is_physical_key_pressed(KEY_SPACE): paused = true
 if Input.is_physical_key_pressed(KEY_ENTER): paused = false
 if Input.is_physical_key_pressed(KEY_R): clock = 0.0
 if paused: return
 var t = fmod(clock,PERIOD)
 if capture or validate: t = float(frame)/FPS
 if still >= 0: t = still
 update_scene(t)
 if capture or validate: telemetry.append(row(t))
 if capture or still>=0:
  await RenderingServer.frame_post_draw
  var image = get_viewport().get_texture().get_image()
  if still>=0:
   image.save_png("res://evidence/"+("grip_detail_" if closeup else "overview_")+str(int(still*10))+".png")
   print("STILL_RENDERED ",t)
   finish = true
   get_tree().quit()
   return
  image.save_png("res://evidence/frames/%04d.png" % frame)
 frame += 1
 clock += delta
 if runtime_check and clock >= PERIOD*2.0:
  var elapsed = float(Time.get_ticks_msec()-runtime_start)/1000.0
  var result = {"loops":2,"simulated_seconds":clock,"wall_seconds":elapsed,"rendered_frames":frame,"average_fps":float(frame)/elapsed}
  var f = FileAccess.open("res://evidence/realtime_loop_check.json",FileAccess.WRITE)
  f.store_string(JSON.stringify(result,"  "))
  print("REALTIME_TWO_LOOPS_OK ",JSON.stringify(result))
  finish = true
  get_tree().quit()
 if (capture or validate) and frame>=int(PERIOD*FPS):
  var file = FileAccess.open("res://evidence/"+("render_telemetry.json" if capture else "headless_telemetry.json"),FileAccess.WRITE)
  file.store_string(JSON.stringify(telemetry," "))
  print("AUDITION_COMPLETE samples=",telemetry.size()," bones=",fingers.size())
  finish = true
  get_tree().quit()

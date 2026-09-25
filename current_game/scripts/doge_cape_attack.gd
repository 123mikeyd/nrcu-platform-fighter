extends Node
# Exact V5 source body bake at 120 Hz; evaluated cape at source 30 Hz.
# Additional source cape is episode-only; native mesh/rig and other clips untouched.
const DATA_PATH="res://assets/doge_man/cape_quick_yellow_20260920.json"
# Skip authored standing/load and long stand-up tail. Keep the released sweep.
const SOURCE_START=0.6
const SOURCE_END=34.0/30.0
const RATE=1.5
const SWEEP_END=(SOURCE_END-SOURCE_START)/RATE
const EXIT=0.10
const DURATION=SWEEP_END+EXIT
const ENTRY=0.06
const ACTIVE=Vector2(21.0/30.0,34.0/30.0) # Released cape sweep, not planted push-off.
static var data:Dictionary={}
var actor
var view
var skeleton:Skeleton3D
var cape:MeshInstance3D
var material:StandardMaterial3D
var active=false
var elapsed=0.0
var direction=1.0
var targets=[]
var contacts=[]
var bones=[]
var entry=[]
var vertices:PackedVector3Array
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual")
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 if data.is_empty():data=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
 for name in data.bones:
  var b=skeleton.find_bone(name)
  assert(b>=0,"V5 native bone missing: "+name)
  bones.append(b)
 cape=MeshInstance3D.new();cape.name="V5SourceCape";view.model.add_child(cape);cape.visible=false
 var color=data.cape_color
 material=StandardMaterial3D.new();material.albedo_color=Color(color[0],color[1],color[2],color[3]);material.roughness=data.cape_roughness;material.cull_mode=BaseMaterial3D.CULL_DISABLED
 cape.material_override=material
func start():
 if active:return
 active=true;elapsed=0;direction=actor.facing;targets.clear();contacts.clear();entry.clear()
 for b in bones:entry.append(actor.approved_crouch.endpoint[b])
 actor.doge_tyson_followup=false;actor.doge_punch_buffered=false
 actor.attack_cooldown=DURATION;actor.last_move="LOW CAPE SPIN";actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.visible=false
 view.cancel_up_special();view.jump_elapsed=-1;view.air_uppercut=false
 present(0)
func cancel():
 if not active:return
 active=false;elapsed=0;targets.clear();entry.clear();cape.visible=false
 actor.attack_cooldown=0;view.current_clip="";view.animation_player.speed_scale=1
func before_tick():
 if active and (not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or (actor.tumble and actor.tumble.active)):cancel()
func before_move():
 if active:actor.facing=direction;actor.velocity.x=0
func source_time(t:float)->float:
 return minf(SOURCE_START+t*RATE,SOURCE_END)
func pose_at(t:float):
 var sample=clampf(source_time(t)*120,0,240);var i=int(sample);var j=mini(i+1,240);var w=sample-i
 for n in bones.size():
  var a=data.frames[i][n];var b=data.frames[j][n]
  var p=Vector3(a[0],a[1],a[2]).lerp(Vector3(b[0],b[1],b[2]),w)
  var q=Quaternion(a[3],a[4],a[5],a[6]).slerp(Quaternion(b[3],b[4],b[5],b[6]),w)
  var s=Vector3(a[7],a[8],a[9]).lerp(Vector3(b[7],b[8],b[9]),w)
  var pose=Transform3D(Basis(q).scaled(s),p)
  if t<ENTRY:pose=entry[n].interpolate_with(pose,smoothstep(0,ENTRY,t))
  if t>SWEEP_END:pose=pose.interpolate_with(actor.approved_crouch.endpoint[bones[n]],smoothstep(SWEEP_END,DURATION,t))
  if t<=0 or t>=DURATION:pose=actor.approved_crouch.endpoint[bones[n]]
  skeleton.set_bone_pose(bones[n],pose)
 skeleton.force_update_all_bone_transforms()
func cape_at(t:float)->PackedVector3Array:
 var sample=clampf(t*30,0,60);var i=int(sample);var j=mini(i+1,60);var w=sample-i
 var result=PackedVector3Array();result.resize(data.cape_frames[i].size())
 for n in result.size():
  var a=data.cape_frames[i][n];var b=data.cape_frames[j][n]
  result[n]=Vector3(a[0],a[1],a[2]).lerp(Vector3(b[0],b[1],b[2]),w)
 return result
func present(t:float):
 if not active:return
 actor._visual_root.scale=Vector3.ONE;view.model.rotation.y=direction*PI/2
 view.flight_root.rotation=Vector3.ZERO;view.current_clip="CapeV5";view.animation_player.pause()
 pose_at(t)
 vertices=cape_at(source_time(t))
 # Gameplay entry blends from approved crouch; keep cloth on the blended neck.
 if t<ENTRY or t>SWEEP_END:
  var sample=clampf(source_time(t)*120,0,240);var i=int(sample);var j=mini(i+1,240)
  var a=data.neck[i];var b=data.neck[j]
  var source=Vector3(a[0],a[1],a[2]).lerp(Vector3(b[0],b[1],b[2]),sample-i)
  var actual=view.model.to_local(skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("neck")).origin)
  for n in vertices.size():
   vertices[n]+=actual-source
   if t>SWEEP_END:vertices[n]=vertices[n].lerp(actual,smoothstep(SWEEP_END,DURATION,t))
 var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(data.cape_indices)
 var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var surface=SurfaceTool.new();surface.create_from(mesh,0);surface.generate_normals();mesh=surface.commit()
 cape.mesh=mesh;cape.visible=t<DURATION
func query_contact(t:float):
 if not active or t<ACTIVE.x or t>ACTIVE.y:return
 var points=cape_at(t)
 for target in get_tree().get_nodes_in_group("fighters"):
  if target in targets or not actor.can_hit(target) or actor.global_position.distance_to(target.global_position)>3:continue
  for shape in target.get_hurtbox_shapes():
   if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
   var cap:CapsuleShape3D=shape.shape;var tr:Transform3D=shape.global_transform
   var half=maxf(0,cap.height*.5-cap.radius);var a=tr*Vector3(0,-half,0);var b=tr*Vector3(0,half,0)
   var radius=cap.radius*maxf(tr.basis.x.length(),tr.basis.z.length())
   for local in points:
    var point=cape.global_transform*local
    var receiver=Geometry3D.get_closest_point_to_segment(point,a,b)
    if point.distance_to(receiver)>radius+.035:continue
    targets.append(target)
    contacts.append({"time":t,"point":str(point),"receiver":str(receiver),"distance":point.distance_to(receiver),"receiver_radius":radius,"cloth_radius":.035,"target":target.character_id})
    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,10,Vector3(signf(target.global_position.x-actor.global_position.x),.25,0),4.2,shape,receiver,point,actor)
    break
   if target in targets:break
func after_tick(delta:float):
 if not active:return
 if not actor.is_grounded():cancel();return
 var end=minf(elapsed+delta,DURATION);var t=elapsed
 while t<end-.000001:
  t=minf(t+1.0/(120*RATE),end)
  if t<=SWEEP_END:query_contact(source_time(t))
 elapsed=end;present(elapsed);actor.attack_cooldown=maxf(.00001,DURATION-elapsed)
 if elapsed>=DURATION-.000001:
  cancel()
  # Finish the whole attack before either held crouch or released-Down rise.
  actor.approved_crouch.amount=1;actor.approved_crouch.phase="hold"

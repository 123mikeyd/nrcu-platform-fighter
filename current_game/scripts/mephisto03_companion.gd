extends Node3D
# Native Mephisto03 companion. Never owns collision, damage percentage or stocks.
var view
var model:Node3D
var skeleton:Skeleton3D
var player:AnimationPlayer
var clock=0.0
var clips={}
var mist=[]
@export var mist_density=.32
@export var mist_spread=.22
@export var mist_speed=.65
const BODY_SCALE=1.5
func setup(owner_view):
 view=owner_view
 var scene=load("res://assets/mephisto03/mephisto03.glb") as PackedScene
 assert(scene!=null,"Mephisto03 asset missing")
 model=scene.instantiate();add_child(model)
 skeleton=model.find_children("*","Skeleton3D",true,false)[0]
 player=model.find_children("*","AnimationPlayer",true,false)[0]
 for key in ["Idle","Grasp","Swipe"]:
  for name in player.get_animation_list():
   if str(name)==key or str(name).ends_with("/"+key):clips[key]=name
  assert(clips.has(key),"Missing Mephisto03 clip "+key)
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  for i in mesh.mesh.get_surface_count():
   var source=mesh.get_active_material(i)
   var mat=ShaderMaterial.new();mat.shader=preload("res://scripts/mephisto03_body.gdshader")
   if source is StandardMaterial3D:
    mat.set_shader_parameter("albedo_tex",source.albedo_texture);mat.set_shader_parameter("tint",source.albedo_color)
   mesh.set_surface_override_material(i,mat)
 for i in 14:
  var card=MeshInstance3D.new();card.name="Mist"+str(i);card.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var quad=QuadMesh.new();quad.size=Vector2(.62,.44);card.mesh=quad
  var mat=ShaderMaterial.new();mat.shader=preload("res://scripts/mephisto03_mist.gdshader");card.material_override=mat
  add_child(card);mist.append(card)
 curl(0.0)
 sync_pose()
func attack_duration()->float:
 return player.get_animation(clips.Swipe).length
func sample(clip:String,time:float):
 player.play(clips[clip],0);player.seek(clampf(time,0,player.get_animation(clips[clip]).length),true);player.pause()
 skeleton.force_update_all_bone_transforms()
func sync_pose():
 if not view:return
 var actor=view.actor();var moves=actor.mephisto_moves
 var direction=actor.facing
 # Mirror only combat direction: keep the demon behind the girl in camera depth.
 basis=Basis(Vector3.UP,PI/2)*Basis.from_scale(Vector3(BODY_SCALE,BODY_SCALE,BODY_SCALE*direction))
 var advance=0.0
 var grasping=moves!=null and moves.move=="DreamGrasp"
 if moves and moves.move=="CompanionPalm":
  advance=smoothstep(.12,.333,moves.elapsed)*(1.0-smoothstep(.583,.9,moves.elapsed))
 elif grasping:advance=moves.grasp().advance(moves.elapsed)
 # Dream Grasp lunges the demon further forward than the old palm (longer reach).
 position=Vector3(direction*lerpf(-.30,.12+(moves.grasp().lunge if grasping else 0.0),advance),.72,lerpf(-.80,-.27,advance))
 if moves and moves.move=="CompanionPalm":sample("Swipe",moves.elapsed)
 elif grasping:
  sample("Swipe",moves.grasp().swipe_time(moves.elapsed));curl(moves.grasp().finger_close(moves.elapsed))
  var g=moves.grasp()
  if g.caught():hoist(g.held_arm_angle(self,moves.elapsed))
  else:g.apply_reach_aim(self,moves.elapsed)
 else:sample("Idle",fmod(clock,player.get_animation(clips.Idle).length))
 # Center the idle torso behind the visible girl; preserve the tested strike endpoint.
 var girl_axis=view.to_local(view.girl_point("Hips")).x
 var demon_axis=view.to_local(point("Chest")).x
 position.x+=(girl_axis-demon_axis)*(1.0-advance)
 visible=actor.stocks>0
func _process(delta):
 if not view:return
 var actor=view.actor()
 if actor.freeze_remaining<=0:clock+=delta
 sync_pose()
 for i in mist.size():
  var phase=clock*mist_speed+float(i)*1.71
  var u=fmod(phase*.22+float(i)/mist.size(),1.0)
  var card=mist[i]
  card.position=Vector3(sin(phase*1.3)*mist_spread,-.12+u*.20,cos(phase)*mist_spread*.75)
  card.material_override.set_shader_parameter("phase",phase)
  card.material_override.set_shader_parameter("mist_color",Color(.42,.19,.065,mist_density*sin(u*PI)))
# Accepted Mephisto03 Grasp finger curl, sampled open (0s) and closed (2.5s) once
# and slerped with a smooth weight: the baked clip steps index/middle at ~2s.
var finger_open={}
var finger_closed={}
const CURL_BONES=["Index.01.R","Index.02.R","Middle.01.R","Middle.02.R","Ring.01.R","Ring.02.R","Pinky.01.R","Pinky.02.R","Thumb.01.R","Thumb.02.R"]
func curl(weight:float):
 if finger_open.is_empty():
  sample("Grasp",0.0)
  for b in CURL_BONES:finger_open[b]=skeleton.get_bone_pose_rotation(skeleton.find_bone(b))
  sample("Grasp",2.5)
  for b in CURL_BONES:finger_closed[b]=skeleton.get_bone_pose_rotation(skeleton.find_bone(b))
  return
 for b in CURL_BONES:
  var i=skeleton.find_bone(b)
  skeleton.set_bone_pose_rotation(i,finger_open[b].slerp(finger_closed[b],clampf(weight,0,1)))
 skeleton.force_update_all_bone_transforms()
var hoist_sign=0.0
# Dream Grasp hoist: rotate the whole right arm about the shoulder in the fight
# plane (world Z) so the palm rises. Sign is resolved once from the result so the
# mirrored companion basis never lowers the hand by mistake.
# Per-frame solve: angle about the shoulder that puts the palm at target_y.
func solve_hoist_angle(target_y:float,lo:float,hi:float)->float:
 var shoulder=point("UpperArm.R")
 var p=point("Hand.R").lerp(point("Middle.01.R"),.65)
 var v=p-shoulder
 var length=Vector2(v.x,v.y).length()
 if length<.05:return 0.0
 var phi=atan2(v.y,v.x*view.actor().facing)
 return clampf(asin(clampf((target_y-shoulder.y)/length,-.95,.95))-phi,lo,hi)
func hoist(angle:float):
 if absf(angle)<.0005:return
 var i=skeleton.find_bone("UpperArm.R")
 var B=skeleton.global_transform.basis
 var gp=skeleton.get_bone_global_pose(i)
 if hoist_sign==0.0:
  var before=point("Hand.R").y
  skeleton.set_bone_global_pose(i,Transform3D(B.inverse()*Basis(Vector3(0,0,1),.2)*B*gp.basis,gp.origin))
  skeleton.force_update_all_bone_transforms()
  var up=point("Hand.R").y>before
  skeleton.set_bone_global_pose(i,gp);skeleton.force_update_all_bone_transforms()
  hoist_sign=1.0 if up else -1.0
  # The sign depends on facing; recompute next time facing flips.
  set_meta("hoist_facing",view.actor().facing)
 elif get_meta("hoist_facing",0.0)!=view.actor().facing:
  hoist_sign=0.0;hoist(angle);return
 skeleton.set_bone_global_pose(i,Transform3D(B.inverse()*Basis(Vector3(0,0,1),angle*hoist_sign)*B*gp.basis,gp.origin))
 skeleton.force_update_all_bone_transforms()
func point(bone:String)->Vector3:
 var index=skeleton.find_bone(bone)
 assert(index>=0,"Unknown native Mephisto03 bone "+bone)
 skeleton.force_update_all_bone_transforms()
 return skeleton.global_transform*skeleton.get_bone_global_pose(index).origin
func tick_contact(moves,previous:float,time:float):
 # Timing is calibrated against the exported native Swipe before promotion.
 var first=1.0/3.0;var last=14.0/24.0
 if time<first or previous>last:return
 var start=maxf(previous,first);var end=minf(time,last)
 var count=maxi(1,int(ceil((end-start)*120.0)))
 for step in range(count+1):
  sample("Swipe",lerpf(start,end,float(step)/count))
  var wrist=point("Hand.R")
  for digit in ["Index.01.R","Middle.01.R","Ring.01.R","Pinky.01.R"]:
   var knuckle=point(digit)
   for part in 3:moves.query_hand(wrist.lerp(knuckle,float(part)/2.0),.09,8.0,Vector3(moves.facing,.25,0),3.6,true)
 sample("Swipe",time)

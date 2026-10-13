extends RefCounted
# Review-only caster kit. Original meshes, binds and Actions are untouched.
# Other starters retain authored tuning; Meteor Heel uses documented reference timing.
const DATA={
 "DreamPalm":{"source":"PactJab","length":.75,"startup":.13,"active":.10,"end":.42,"damage":6.0,"kb":2.6,"hand":"LeftHand","radius":.27,"launch":Vector3(1,.22,0)},
 "DuskCutter":{"source":"RubberGuillotine","length":25.0/24,"startup":.23,"active":.13,"end":.62,"damage":11.0,"kb":4.4,"hand":"RightHand","radius":.30,"launch":Vector3(1,.25,0)},
 "MoonArc":{"source":"CinderLift","length":23.0/24,"startup":.18,"active":.18,"end":.55,"damage":8.0,"kb":3.4,"hand":"LeftHand","radius":.35,"launch":Vector3(.22,1,0)},
 "LowGleam":{"source":"kick","startup":.20,"active":.08,"end":.58,"damage":7.0,"kb":2.7,"hand":"RightToeBase","radius":.25,"launch":Vector3(1,.42,0)},
 "OrbitVeil":{"source":"authored","startup":.16,"active":.22,"end":.56,"damage":7.0,"kb":3.0,"hand":"LeftHand","radius":.30,"launch":Vector3(1,.4,0)},
 "StarHeel":{"source":"airkick","startup":.15,"active":.075,"end":.50,"damage":12.0,"kb":4.6,"hand":"RightToeBase","radius":.22,"launch":Vector3(1,.22,0)},
 "MoonBloom":{"source":"authored","startup":.25,"active":.17,"end":.68,"damage":11.0,"kb":4.4,"hand":"RightHand","radius":.43,"launch":Vector3(.12,1,0)},
 "FallingStar":{"source":"meteor","startup":13.0/60,"active":11.0/60,"end":44.0/60,"damage":16.0,"kb":4.0,"hand":"LeftFoot","radius":.28,"launch":Vector3.DOWN}
}
var moves
var meteor
func heel():
 if not meteor:meteor=preload("res://scripts/mephisto_meteor_heel.gd").new();meteor.basics=self
 return meteor
var airborne=false
var entry=[]
var motes:Array[MeshInstance3D]=[]
static func route(aim:Vector2,air:bool)->String:
 if air:
  if aim.y<-.1:return "MoonBloom"
  if aim.y>.1:return "FallingStar"
  return "StarHeel" if absf(aim.x)>.1 else "OrbitVeil"
 if aim.y<-.1:return "MoonArc"
 if aim.y>.1:return "LowGleam"
 return "DuskCutter" if absf(aim.x)>.1 else "DreamPalm"
func view():return moves.view()
func capture()->Array:
 var result=[]
 for i in view().native_skeleton.get_bone_count():result.append(view().native_skeleton.get_bone_pose(i))
 return result
func blend_from(seed:Array,w:float):
 if seed.is_empty():return
 var sk=view().native_skeleton
 for i in sk.get_bone_count():sk.set_bone_pose(i,seed[i].interpolate_with(sk.get_bone_pose(i),w))
 sk.force_update_all_bone_transforms()
func begin():
 airborne=not moves.actor.is_grounded();entry=capture()
 for i in 7:
  var fx=MeshInstance3D.new();var mesh=SphereMesh.new();mesh.radius=1;mesh.height=2;fx.mesh=mesh
  var mat=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.albedo_color=Color(.66,.45,1,.65)
  fx.material_override=mat;fx.visible=false;moves.actor.get_parent().add_child(fx);motes.append(fx)
func cancel():
 for fx in motes:
  if is_instance_valid(fx):fx.queue_free()
 motes.clear()
# Two-joint CCD in world space: only arm rotations, never bind/scale/weights.
func aim_arm(side:String,target:Vector3,weight:float):
 var sk=view().native_skeleton
 var h=sk.find_bone("DEF-hand."+side)
 var joints=[sk.find_bone("DEF-forearm."+side),sk.find_bone("DEF-upper_arm."+side)]
 var goal=sk.to_local(target)
 for repeat in 5:
  for j in joints:
   var pose=sk.get_bone_global_pose(j)
   var a=sk.get_bone_global_pose(h).origin-pose.origin;var b=goal-pose.origin
   if a.length()<.001 or b.length()<.001:continue
   var q=Quaternion(a.normalized(),b.normalized())
   var p=sk.get_bone_parent(j);var parent=Quaternion.IDENTITY if p<0 else sk.get_bone_global_pose(p).basis.orthonormalized().get_rotation_quaternion()
   var delta=Quaternion.IDENTITY.slerp(q,weight)
   sk.set_bone_pose_rotation(j,(parent.inverse()*delta*parent*sk.get_bone_pose_rotation(j)).normalized())
   sk.force_update_all_bone_transforms()
func source_time(t:float,d:Dictionary)->float:
 # Preserve the original contact silhouette; retime anticipation and recovery.
 var contact=.27 if d.source=="PactJab" else (.43 if d.source=="RubberGuillotine" else .40)
 if t<d.startup:return lerpf(0,contact,t/d.startup)
 if t<d.startup+d.active:return lerpf(contact,contact+.15,(t-d.startup)/d.active)
 return lerpf(contact+.15,d.length,clampf((t-d.startup-d.active)/(d.end-d.startup-d.active),0,1))
func present(t:float):
 var id=moves.move
 if not DATA.has(id):return
 var d=DATA[id];var v=view();var f=moves.facing
 v.native_skeleton.clear_bones_global_pose_override();v.native_skeleton.reset_bone_poses();v.locomotion_state=""
 v.pose_frame(704,f);v.show_native_girl(f)
 if d.source=="meteor":heel().present(t)
 elif d.source in ["PactJab","RubberGuillotine","CinderLift"]:
  v.native_pose(d.source,source_time(t,d))
 elif d.source=="kick":
  var st=lerpf(0,23.0/30,t/d.startup) if t<d.startup else (lerpf(23.0/30,25.0/30,(t-d.startup)/d.active) if t<d.startup+d.active else lerpf(25.0/30,59.0/30,clampf((t-d.startup-d.active)/(d.end-d.startup-d.active),0,1)))
  v.native_player.play("kick/GoalkeeperKick",0);v.native_player.seek(st,true);v.native_player.pause()
 elif d.source in ["airkick","airdown"]:
  var donor=moves.actor.humanoid_air_basic
  donor.move="neutral" if d.source=="airkick" else "down";donor.clip="Neutral" if d.source=="airkick" else "Down";donor.direction=f
  var start=5.0/30 if d.source=="airkick" else .4
  var stop=6.0/30 if d.source=="airkick" else .5
  var total=.5 if d.source=="airkick" else 38.0/30
  var st=lerpf(0,start,t/d.startup) if t<d.startup else (lerpf(start,stop,(t-d.startup)/d.active) if t<d.startup+d.active else lerpf(stop,total,clampf((t-d.startup-d.active)/(d.end-d.startup-d.active),0,1)))
  donor.present(st)
 else:
  v.native_pose("Idle",0)
  var envelope=smoothstep(0,d.startup,t)*(1-smoothstep(d.startup+d.active,d.end,t))
  var hip=v.girl_point("Hips");var u=clampf((t-d.startup)/d.active,0,1)
  if id=="MoonBloom":
   aim_arm("R",hip+Vector3(f*.18,1.05,0),envelope)
   aim_arm("L",hip+Vector3(f*.05,.77,.12),envelope)
  else:
   # Open a ward with both arms; swing the near hand forward while the far
   # hand counterbalances. This is authored ritual motion, not a donor claim.
   aim_arm("L",hip+Vector3(f*lerpf(.62,-.40,u),.35,.06),envelope)
   aim_arm("R",hip+Vector3(f*lerpf(-.40,.62,u),.45,-.06),envelope)
 if t<.07:blend_from(entry,smoothstep(0,.07,t))
 if t>d.end-.10 and d.source!="meteor":
  var last=capture();v.native_pose("Idle",0);blend_from(last,smoothstep(d.end-.10,d.end,t))
 v.native_skeleton.force_update_all_bone_transforms()
 v.current_clip="Playable/"+id;v.source_frame=t*60+(1 if id=="FallingStar" else 0)
 if v.companion:v.companion.sync_pose()
 update_fx(t)
func points()->Array:
 var d=DATA[moves.move];var v=view();var point=v.girl_point(d.hand)
 # The visible manifestation grows out of the hand, not an invisible cone.
 if moves.move=="MoonBloom":point+=Vector3.UP*.32
 elif moves.move=="MoonArc":point+=Vector3(moves.facing*.12,.12,0)
 elif moves.move=="DreamPalm":point+=Vector3(moves.facing*.23,0,0)
 elif moves.move in ["DuskCutter","LowGleam"]:point.z=moves.actor.global_position.z
 elif moves.move=="FallingStar":point+=Vector3(0,-.12,0)
 if moves.move=="OrbitVeil":return [v.girl_point("LeftHand"),v.girl_point("RightHand")]
 if moves.move=="LowGleam":return [point,v.girl_point(d.hand)]
 return [point]
func update_fx(t:float):
 if moves.move=="FallingStar":heel().update_fx(t);return
 var d=DATA[moves.move];var p=points()
 var active=t>=d.startup and t<=d.startup+d.active
 var charge=smoothstep(0,d.startup,t) if t<d.startup else 1-smoothstep(d.startup+d.active,d.end,t)
 for i in motes.size():
  if not is_instance_valid(motes[i]):continue
  motes[i].visible=charge>.01
  if i<p.size():
   motes[i].global_position=p[i];motes[i].scale=Vector3.ONE*d.radius*(1.0 if active else .28*charge)
   motes[i].material_override.albedo_color=Color(.79,.61,1,.70 if active else .4)
  else:
   # Non-damaging trail makes the hand/foot-to-manifestation extension explicit.
   motes[i].global_position=view().girl_point(d.hand).lerp(p[0],float(i-p.size()+1)/float(motes.size()-p.size()+1))
   motes[i].scale=Vector3.ONE*.065*charge
func tick(previous:float,t:float):
 if moves.move=="FallingStar":heel().tick(previous,t);return
 if airborne and moves.actor.is_grounded():
  moves.actor.landing_lag=maxf(moves.actor.landing_lag,.12);moves.cancel();return
 var d=DATA[moves.move]
 if t<d.startup or previous>d.startup+d.active:return
 var first=maxf(previous,d.startup);var last=minf(t,d.startup+d.active)
 var steps=maxi(1,int(ceil((last-first)*120)))
 for i in range(steps+1):
  present(lerpf(first,last,float(i)/steps))
  for point in points():
   var direction:Vector3=d.launch;direction.x*=moves.facing
   moves.query_hand(point,d.radius,d.damage,direction,d.kb)
  if moves.move in ["StarHeel","FallingStar"]:
   # Foot sweetspot first; real shin/ankle sourspot prevents close-range blind
   # spots without enlarging the toe or introducing an invisible actor cone.
   var side="Right" if moves.move=="StarHeel" else "Left"
   var knee=view().girl_point(side+"Leg");var ankle=view().girl_point(side+"Foot")
   var hip=view().girl_point(side+"UpLeg")
   for part in 5:
    var direction:Vector3=d.launch;direction.x*=moves.facing
    moves.query_hand(knee.lerp(ankle,float(part)/4),.12,6.0,direction,2.7)
    moves.query_hand(hip.lerp(knee,float(part)/4),.13,6.0,direction,2.7)
 present(t)

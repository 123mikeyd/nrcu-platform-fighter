extends RefCounted
# Original native choreography studied from Zelda Ultimate GIF; not Nintendo motion.
# Source frame 1 = elapsed zero. All geometry scales to the actual native shin.
const CLEAN=13.0/60.0
const LATE=14.0/60.0
const CLEAR=24.0/60.0
const END=44.0/60.0
const LENGTH=1.0
var owner_ref:WeakRef
var basics:
 get:return owner_ref.get_ref()
 set(value):owner_ref=weakref(value)
var debug_hitboxes=false
func view():return basics.view()
func sk():return view().native_skeleton
func world(i:int)->Transform3D:return sk().global_transform*sk().get_bone_global_pose(i)
func point(name:String)->Vector3:return world(sk().find_bone(name)).origin
func descendants(root:int)->Array:
 var result=[]
 for i in sk().get_bone_count():
  var j=i
  while j>=0:
   if j==root:result.append(i);break
   j=sk().get_bone_parent(j)
 return result
func rotate_group(indices:Array,pivot:Vector3,q:Quaternion):
 var poses=[]
 for i in indices:
  var p=world(i);p.origin=pivot+q*(p.origin-pivot);p.basis=Basis(q)*p.basis;poses.append(p)
 for n in indices.size():sk().set_bone_global_pose(indices[n],sk().global_transform.affine_inverse()*poses[n])
 sk().force_update_all_bone_transforms()
func aim(root:String,end:String,direction:Vector3):
 var i=sk().find_bone(root);var p=world(i).origin
 var from=point(end)-p
 rotate_group(descendants(i),p,Quaternion(from.normalized(),direction.normalized()))
func curve(frame:float,keys:Array)->float:
 for i in range(1,keys.size()):
  if frame<=keys[i][0]:return lerpf(keys[i-1][1],keys[i][1],smoothstep(keys[i-1][0],keys[i][0],frame))
 return keys[-1][1]
func leg(side:String,thigh:float,shin:float,face:float):
 aim("DEF-thigh."+side,"DEF-shin."+side,Vector3(face*sin(deg_to_rad(thigh)),-cos(deg_to_rad(thigh)),0))
 aim("DEF-shin."+side,"DEF-foot."+side,Vector3(face*sin(deg_to_rad(shin)),-cos(deg_to_rad(shin)),0))
 # A pointed heel, not a rotated ankle inherited from the old down-kick donor.
 aim("DEF-foot."+side,"DEF-toe."+side,Vector3(face*.50,-.86,0))
func present(t:float):
 var v=view();v.native_pose("Idle",0)
 var frame=t*60+1;var face=basics.moves.facing
 var envelope=curve(frame,[[1,0],[5,.55],[9,1],[24,1],[34,.65],[45,.18],[60,0]])
 var lean=curve(frame,[[1,0],[9,14],[13,18],[14,-5],[24,-3],[31,11],[40,8],[60,0]])
 var upper=[]
 for i in sk().get_bone_count():
  if i>=14:upper.append(i)
 var head=world(71).basis;var neck=world(70).basis
 rotate_group(upper,point("DEF-spine"),Quaternion(Vector3(0,0,1),deg_to_rad(-face*lean)))
 # Explicit full-clip head/neck orientation ownership: no imported donor track.
 # Native Idle neutral neck/head retained in world basis, translating with torso.
 for item in [[70,neck],[71,head]]:
  var p=world(item[0]);p.basis=item[1];sk().set_bone_global_pose(item[0],sk().global_transform.affine_inverse()*p)
 var seed=[]
 for i in sk().get_bone_count():seed.append(sk().get_bone_pose(i))
 var lift=curve(frame,[[1,0],[5,40],[9,77],[13,80],[14,4],[24,5],[29,43],[36,48],[45,20],[60,0]])
 var bend=curve(frame,[[1,0],[5,-55],[9,-76],[13,-80],[14,-2],[24,-3],[29,-54],[36,-52],[45,-24],[60,0]])
 leg("L",lift,bend,face)
 leg("R",curve(frame,[[1,0],[8,58],[13,70],[14,38],[24,35],[32,50],[45,18],[60,0]]),curve(frame,[[1,0],[9,-75],[13,-85],[14,-64],[24,-60],[34,-48],[45,-20],[60,0]]),face)
 var chamber=curve(frame,[[1,0],[9,1],[13,1],[14,0],[24,0],[34,.7],[45,.4],[60,0]])
 for side in ["L","R"]:
  var z=-1.0 if side=="L" else 1.0
  aim("DEF-upper_arm."+side,"DEF-forearm."+side,Vector3(face*lerpf(-.12,.55,chamber),lerpf(-.5,-.12,chamber),z*.52))
  aim("DEF-forearm."+side,"DEF-hand."+side,Vector3(face*lerpf(.25,.22,chamber),lerpf(.20 if side=="R" else -.28,.38,chamber),z*lerpf(.20,-.20,chamber)))
 # Blend all limb channels out to the SAME native neutral sample at frame60.
 for i in sk().get_bone_count():
  if i<12 or (i>=17 and i<66):sk().set_bone_pose(i,seed[i].interpolate_with(sk().get_bone_pose(i),envelope))
 sk().force_update_all_bone_transforms()
func volumes(t:float)->Array:
 # Share collision's clock-roundoff tolerance with the visible debug volume.
 t+=0.00000001
 if t<CLEAN or t>=CLEAR:return []
 var knee=view().girl_point("LeftLeg");var foot=view().girl_point("LeftFoot")
 var length=knee.distance_to(foot);var down=(foot-knee).normalized()
 # Normalized coverage: clean overlapping spheres enclose distal shin and past heel.
 # Smash foot-local x/y are NOT treated as Godot world meters.
 if t<LATE:return [{"center":foot+down*length*.12,"radius":length*.68,"damage":16.0,"kb":4.0,"direction":Vector3.DOWN,"id":0},{"center":foot-down*length*.40,"radius":length*.65,"damage":16.0,"kb":4.0,"direction":Vector3.DOWN,"id":1}]
 return [{"center":knee,"radius":length*.81,"damage":5.0,"kb":1.8,"direction":Vector3(basics.moves.facing*.08716,-.99619,0),"id":0},{"center":foot,"radius":length*.81,"damage":4.0,"kb":1.3,"direction":Vector3(basics.moves.facing*.08716,-.99619,0),"id":1}]
func autocancel(t:float)->bool:return t<3.0/60.0 or t>=39.0/60.0
func tick(previous:float,t:float):
 var m=basics.moves
 if basics.airborne and m.actor.is_grounded():
  if not autocancel(t):m.actor.landing_lag=maxf(m.actor.landing_lag,12.0/60.0)
  m.cancel();return
 # Split event intervals before sub-sampling so 14's one-frame clean cannot vanish
 # at 30 Hz or a long callback. No cross-ID sweep: omit frame15 interpolation bug.
 for interval in [[CLEAN,LATE],[LATE,CLEAR]]:
  # Inclusive onset, exclusive phase end. Tolerate floating-clock roundoff only.
  if t+0.00000001<interval[0] or previous>=interval[1]:continue
  var first=maxf(previous,interval[0]);var last=maxf(first,minf(t,interval[1]))
  var count=maxi(1,int(ceil((last-first)*240)))
  for i in count:
   var sample=lerpf(first,last,float(i)/count)
   basics.present(sample)
   for volume in volumes(sample):m.query_hand(volume.center,volume.radius,volume.damage,volume.direction,volume.kb)
 basics.present(t)
func update_fx(t:float):
 var shapes=volumes(t)
 for i in basics.motes.size():
  var fx=basics.motes[i];fx.visible=debug_hitboxes and i<shapes.size()
  if fx.visible:
   fx.global_position=shapes[i].center;fx.scale=Vector3.ONE*shapes[i].radius
   fx.material_override.albedo_color=Color(1,.12,.14,.38) if t<LATE else Color(.9,.16,1,.3)

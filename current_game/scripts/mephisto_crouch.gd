extends "res://scripts/approved_crouch.gd"
# Girl2-only authored runtime skeletal crouch. Native Idle is the bind-aware
# starting pose; analytic knees preserve limb lengths and exact foot transforms.
# No imported rest, skin, scale, movement capsule or companion edits.
var baseline: Array[Transform3D] = []
func _ready():
 actor=get_parent()
 view=actor._visual_root.get_node("MephistoVisual")
 skeleton=view.native_skeleton
 duration=.18
 view.native_pose("Idle",0)
 skeleton.clear_bones_global_pose_override()
 skeleton.force_update_all_bone_transforms()
 for i in skeleton.get_bone_count():baseline.append(skeleton.get_bone_global_pose(i))
func allowed() -> bool:
 if not super.allowed():return false
 var moves=actor.mephisto_moves
 return not moves or (moves.move.is_empty() and not moves.demon_form)
func cancel():
 if phase=="idle":return
 skeleton.clear_bones_global_pose_override()
 phase="idle";amount=0;hold_time=0
 view.current_clip=""
func present(delta:float,interrupted:bool) -> bool:
 if interrupted or not allowed():cancel();return false
 var input=actor._read_raw_controls(0)
 if input.left or input.right or input.up or input.jump or input.attack or input.special or absf(actor.velocity.x)>.2:
  cancel();return false
 var down:bool=input.down
 if phase=="idle" and not down:return false
 var old=amount
 amount=move_toward(amount,1.0 if down else 0.0,maxf(delta,0)/duration)
 if amount<=0:cancel();return false
 phase="hold" if amount>=1 else ("enter" if amount>=old else "exit")
 actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 view.sync_pose(true,Vector3.ZERO,false,false,false,actor.facing)
 view.native_pose("Idle",0)
 skeleton.clear_bones_global_pose_override()
 var w=smoothstep(0,1,amount)
 var shift=Vector3(0,-.32,-.12)*w
 var hip=baseline[skeleton.find_bone("DEF-spine")].origin
 var lean=Basis(Vector3.RIGHT,.16*w)
 var target: Array[Transform3D] = []
 for i in baseline.size():
  var t=baseline[i]
  if i>=14:
   t.origin=hip+lean*(t.origin-hip)+shift
   t.basis=lean*t.basis
  else:t.origin+=shift
  target.append(t)
 for side in ["L","R"]:
  var thigh=skeleton.find_bone("DEF-thigh."+side)
  var shin=skeleton.find_bone("DEF-shin."+side)
  var foot=skeleton.find_bone("DEF-foot."+side)
  var h=baseline[thigh].origin+shift
  var k=baseline[shin].origin
  var f=baseline[foot].origin
  var upper=baseline[thigh].origin.distance_to(k)
  var lower=k.distance_to(f)
  var axis=(f-h).normalized()
  var distance=h.distance_to(f)
  var along=(upper*upper-lower*lower+distance*distance)/(2*distance)
  var pole=(Vector3.FORWARD*-1-axis*axis.dot(Vector3.FORWARD*-1)).normalized()
  var knee=h+axis*along+pole*sqrt(maxf(0,upper*upper-along*along))
  var upper_rot=Basis(Quaternion((k-baseline[thigh].origin).normalized(),(knee-h).normalized()))
  var lower_rot=Basis(Quaternion((f-k).normalized(),(f-knee).normalized()))
  for b in [thigh,thigh+1]:
   target[b]=Transform3D(upper_rot*baseline[b].basis,h+upper_rot*(baseline[b].origin-baseline[thigh].origin))
  for b in [shin,shin+1]:
   target[b]=Transform3D(lower_rot*baseline[b].basis,knee+lower_rot*(baseline[b].origin-k))
  target[foot]=baseline[foot];target[foot+1]=baseline[foot+1]
 for i in target.size():skeleton.set_bone_global_pose_override(i,target[i],1.0,true)
 skeleton.force_update_all_bone_transforms()
 view.current_clip="Girl2/NativeCrouch"
 sync_receivers()
 return true

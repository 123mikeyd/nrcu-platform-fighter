extends RefCounted
# Editable provisional native-rig choreography. Seconds, not frame-rate ticks.
# These are animation-only pose derivatives: no rest, vertex or weight edits.
const MOVES = {
 "PactJab": {"label":"PACT JAB", "startup":.16,"active":.12,"recovery":.24,"damage":6.0,"kb":2.8,"hand":"LeftHand","from":Vector3(.08,1.50,.10),"to":Vector3(.65,1.42,.02),"launch":Vector3(1,.15,0)},
 "RubberGuillotine": {"label":"RUBBER GUILLOTINE", "startup":.42,"active":.25,"recovery":.48,"damage":11.0,"kb":4.4},
 "CinderLift": {"label":"CINDER LIFT", "startup":.23,"active":.15,"recovery":.30,"damage":9.0,"kb":4.2,"hand":"LeftHand","from":Vector3(.20,1.70,.04),"to":Vector3(.38,2.64,.04),"launch":Vector3(.18,1,0)},
 "AnkleRake": {"label":"ANKLE RAKE", "startup":.24,"active":.16,"recovery":.32,"damage":8.0,"kb":3.4,"hand":"LeftHand","from":Vector3(.0,1.32,.08),"to":Vector3(.52,1.15,.03),"launch":Vector3(1,.20,0)},
 "VeilCross": {"label":"VEIL CROSS", "startup":.15,"active":.17,"recovery":.30,"damage":7.0,"kb":3.2,"hand":"LeftHand","from":Vector3(.34,1.86,-.28),"to":Vector3(.59,1.58,.26),"launch":Vector3(1,.35,0)},
 "AirSwat": {"label":"AIR SWAT", "startup":.22,"active":.16,"recovery":.32,"damage":9.0,"kb":4.0,"hand":"LeftHand","from":Vector3(.05,2.2,.15),"to":Vector3(.65,1.80,.02),"launch":Vector3(1,.25,0)},
 "CrownHook": {"label":"CROWN HOOK", "startup":.18,"active":.16,"recovery":.29,"damage":8.0,"kb":3.8,"hand":"LeftHand","from":Vector3(.55,2.10,.02),"to":Vector3(.0,2.72,.02),"launch":Vector3(.12,1,0)},
 "FallingClaw": {"label":"FALLING CLAW", "startup":.25,"active":.17,"recovery":.35,"damage":10.0,"kb":4.0,"hand":"LeftHand","from":Vector3(.50,1.88,.05),"to":Vector3(.22,1.13,.05),"launch":Vector3(.15,-1,0)},
 "ShadowShove": {"label":"SHADOW SHOVE", "startup":.32,"active":.19,"recovery":.40,"damage":12.0,"kb":5.3,"hand":"LeftHand","from":Vector3(.05,1.66,.07),"to":Vector3(.64,1.88,.04),"launch":Vector3(1,.22,0),"both":true},
 "CloseTraverse": {"label":"CLOSE TRAVERSE", "startup":.18,"active":.23,"recovery":.38,"damage":7.0,"kb":3.1,"hand":"LeftHand","from":Vector3(.1,1.62,.08),"to":Vector3(.63,1.67,.03),"launch":Vector3(1,.15,0)},
 "CinderToss": {"label":"CINDER LIFT (TOSS)", "startup":.36,"active":.12,"recovery":.35,"damage":0.0,"kb":0.0},
 "ShadowUppercut": {"label":"SHADOW UPPERCUT", "startup":.60,"active":.22,"recovery":.48,"damage":13.0,"kb":5.2},
 "UmberPlunge": {"label":"UMBER PLUNGE", "startup":.26,"active":.22,"recovery":.44,"damage":11.0,"kb":4.4,"hand":"LeftHand","from":Vector3(.54,1.75,.04),"to":Vector3(.10,1.13,.04),"launch":Vector3(.2,-1,0),"both":true}
}
static func duration(id:String)->float:
 var d=MOVES[id]
 return d.startup+d.active+d.recovery
static func route(aim:Vector2,air:bool,special:bool)->String:
 if special:
  if aim.y < -.1:return "CinderToss"
  if aim.y > .1:return "UmberPlunge" if air else "ShadowUppercut"
  return "CloseTraverse" if absf(aim.x)>.1 else "ShadowShove"
 if air:
  if aim.y < -.1:return "CrownHook"
  if aim.y > .1:return "FallingClaw"
  return "AirSwat" if absf(aim.x)>.1 else "VeilCross"
 if aim.y < -.1:return "CinderLift"
 if aim.y > .1:return "AnkleRake"
 return "RubberGuillotine" if absf(aim.x)>.1 else "PactJab"

# CCD rotates native joints, preserving all compensated translations/scales.
static func reach(sk:Skeleton3D, hand:String, goal:Vector3):
 var wrist=sk.find_bone(hand)
 var elbow=sk.get_bone_parent(wrist)
 var shoulder=sk.get_bone_parent(elbow)
 for iteration in 7:
  for joint in [elbow,shoulder,sk.get_bone_parent(shoulder)]:
   sk.force_update_all_bone_transforms()
   var origin=sk.get_bone_global_pose(joint).origin
   var a=(sk.get_bone_global_pose(wrist).origin-origin).normalized()
   var b=(goal-origin).normalized()
   if a.length_squared()<.5 or b.length_squared()<.5:continue
   var delta=Quaternion(a,b)
   var parent=sk.get_bone_parent(joint)
   var basis=sk.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
   sk.set_bone_pose_rotation(joint,(basis.inverse()*delta*basis*sk.get_bone_pose_rotation(joint)).normalized())
 sk.force_update_all_bone_transforms()

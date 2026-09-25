extends RefCounted
const CAST=.30
const RETRACT=.28
var moves
var release_pose={}
func present():
 var v=moves.view();var t=moves.elapsed
 if moves.move=="ShadowRecover":
  var source=clampf(t/RETRACT,0,1)*.5
  if t<.14:v.native_pair_pose("ShadowRetract",source,smoothstep(0,.14,t),moves.facing,release_pose)
  else:v.native_pair_pose("ShadowRetract",source,1.0-smoothstep(.22,RETRACT,t),moves.facing)
 elif t<CAST:v.native_pair_pose("ShadowCast",t/CAST*.5,smoothstep(0,.08,t),moves.facing)
 else:v.native_pair_pose("ShadowHold",fmod(t-CAST,1.0),1.0,moves.facing)
func release():
 release_pose=moves.view().pair_snapshot()
 moves.move="ShadowRecover";moves.elapsed=0;moves.actor.attack_cooldown=RETRACT
func cancel():release_pose.clear()

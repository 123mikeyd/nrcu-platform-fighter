extends RefCounted
# Approved native GoalkeeperKick, full source timing; only ground down-basic.
const ENTRY=.18
const SOURCE=59.0/30.0
const RECOVERY=.24
const DURATION=ENTRY+SOURCE+RECOVERY
const LOW_START=ENTRY+23.0/30.0
const LOW_END=ENTRY+25.0/30.0
const RADIUS=.09
var moves
var entry_pose=[]
func view():return moves.view()
func capture():
 var pose=[];var sk=view().native_skeleton
 for i in sk.get_bone_count():pose.append(sk.get_bone_pose(i))
 return pose
func begin():entry_pose=capture()
func blend_from(pose,weight:float):
 var sk=view().native_skeleton
 for i in sk.get_bone_count():sk.set_bone_pose(i,pose[i].interpolate_with(sk.get_bone_pose(i),weight))
 sk.force_update_all_bone_transforms()
func present(time:float):
 var v=view()
 v.pose_frame(704,moves.facing);v.show_native_girl(moves.facing)
 var source=clampf(time-ENTRY,0,SOURCE)
 v.native_player.play("kick/GoalkeeperKick",0);v.native_player.seek(source,true);v.native_player.pause()
 if time<ENTRY and not entry_pose.is_empty():blend_from(entry_pose,smoothstep(0,ENTRY,time))
 elif time>ENTRY+SOURCE:
  var last=capture();v.native_pose("Idle",v.native_clock,true)
  blend_from(last,smoothstep(ENTRY+SOURCE,DURATION,time))
 v.native_skeleton.force_update_all_bone_transforms()
 v.current_clip="Girl2/GoalkeeperKick";v.source_frame=1+source*30
func tick(previous:float,time:float):
 if time<LOW_START or previous>LOW_END:return
 # Sweep actual native ankle-to-toe positions only during the low pass.
 # Sampling the source clock prevents a low pass being skipped at a slow tick.
 var first=maxf(previous,LOW_START);var last=minf(time,LOW_END)
 var steps=maxi(1,int(ceil((last-first)*240)))
 for step in range(steps+1):
  var sample=lerpf(first,last,float(step)/steps);present(sample)
  var ankle=view().girl_point("DEF-foot.R");var toe=view().girl_point("DEF-toe.R")
  for part in 5:
   moves.query_hand(ankle.lerp(toe,float(part)/4),RADIUS,8.0,Vector3(moves.facing,.3,0),3.4,true)
 present(time)

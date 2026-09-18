extends RefCounted
# Editable native-rest Teknium ForcePush derivative; original skin stays intact.
const LIB=preload("res://assets/mephisto_girl2/ember_forcepush.tres")
const SOURCE_EVENT=24.0/24.0 # Actual extended pose, after Teknium's frame16 projectile event.
const SOURCE_END=34.0/24.0
const CAST=.75
const EXPLOSION=.18
const RECOVER_END=22.0/24.0
static func mix_transform(a:Transform3D,b:Transform3D,w:float)->Transform3D:
 # Preserve native evaluated affine/shear data rather than decomposing to TRS.
 return Transform3D(Basis(a.basis.x.lerp(b.basis.x,w),a.basis.y.lerp(b.basis.y,w),a.basis.z.lerp(b.basis.z,w)),a.origin.lerp(b.origin,w))
static func present(v,phase:String,t:float):
 var source=minf(t/CAST,1.0)*SOURCE_EVENT
 var blend=smoothstep(0,.12,t)
 if phase=="EmberRelease":
  source=lerpf(SOURCE_EVENT,SOURCE_END,clampf((t-EXPLOSION)/(RECOVER_END-EXPLOSION-.16),0,1))
  blend=1.0-smoothstep(EXPLOSION+.08,RECOVER_END,t)
 v.native_skeleton.clear_bones_global_pose_override()
 v.native_pose("Idle",v.native_clock,true)
 var full=LIB.get_animation("ForcePush").get_meta("full_globals")
 var sample=clampf(source*48.0,0,full.size()-1)
 var lo=int(floor(sample));var hi=mini(lo+1,full.size()-1)
 var idle=[]
 for i in v.native_skeleton.get_bone_count():idle.append(v.native_skeleton.get_bone_global_pose(i))
 for i in v.native_skeleton.get_bone_count():
  var desired=mix_transform(full[lo][i],full[hi][i],sample-lo)
  if blend<1:desired=idle[i].interpolate_with(desired,blend)
  v.native_skeleton.set_bone_global_pose_override(i,desired,1.0,true)
 v.native_skeleton.force_update_all_bone_transforms()
 v.current_clip="Girl2/ForcePush/"+phase

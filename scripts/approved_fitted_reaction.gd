extends Node
# Exact approved v002 local samples; no mesh/rest/scale or combat policy edits.
var actor
var skeleton: Skeleton3D
var names: Array = []
var samples: Dictionary = {}
var active := false
var kind := ""
var clock := 0.0
var incoming_side := 0.0
var players: Array = []
func _ready():
 actor=get_parent()
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reactions/"+actor.character_id+"_fitted.json"))
 names=data.names
 for sk in actor._visual_root.find_children("*","Skeleton3D",true,false):
  # Girl and native recipient contract, never the separate shadow skeleton.
  if sk.get_bone_count()==names.size() and sk.find_bone("headfront")>=0:
   skeleton=sk;break
 assert(skeleton!=null,"Approved recipient skeleton contract missing")
 for role in ["head","body"]:
  samples[role]=[]
  for row in data[role]:
   var poses=[]
   for raw in row:
    poses.append(Transform3D(Basis(vec(raw[0]),vec(raw[1]),vec(raw[2])),vec(raw[3])))
   samples[role].append(poses)
 # Select only animation players in the recipient model, not its companion.
 var branch=skeleton
 while branch.get_parent()!=actor._visual_root and branch.get_parent()!=null:branch=branch.get_parent()
 players=branch.find_children("*","AnimationPlayer",true,false)
func vec(v):return Vector3(v[0],v[1],v[2])
func bone_point(bone):
 skeleton.force_update_all_bone_transforms()
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
func classify(point):
 return "head" if point.distance_squared_to(bone_point("Head")) < point.distance_squared_to(bone_point("neck")) else "body"
func begin(region,side):
 kind=region;incoming_side=side;clock=0;active=true;present_sample(0)
func present_sample(t):
 var rows=samples[kind]
 var f=clampf(t*60,0,rows.size()-1)
 for ap in players:ap.pause()
 for i in names.size():
  skeleton.set_bone_pose(skeleton.find_bone(names[i]),rows[int(f)][i].interpolate_with(rows[mini(int(f)+1,rows.size()-1)][i],f-floorf(f)))
 skeleton.force_update_all_bone_transforms()
func _physics_process(delta):
 tick(delta)
func tick(delta):
 if not active:return
 if actor.freeze_remaining>0:return
 if not actor.controls_enabled or actor.stocks<=0 or actor.magic_locked():clear();return
 clock+=delta
 if clock>(samples[kind].size()-1)/60.0:clear();return
 present_sample(clock)
func clear():
 if not active and kind.is_empty():return
 active=false;kind="";clock=0
 for ap in players:
  if not ap.assigned_animation.is_empty():ap.play()

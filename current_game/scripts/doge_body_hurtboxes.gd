extends Node3D
# Damage only. Never alter the movement body, native animation or live morphs.
var actor
var skeleton: Skeleton3D
var body: StaticBody3D
var shapes: Array[CollisionShape3D] = []
var regions: Array = []
func _ready() -> void:
 actor=get_parent()
 skeleton=actor._visual_root.find_children("*","Skeleton3D",true,false)[0]
 regions=JSON.parse_string(FileAccess.get_file_as_string("res://scripts/doge_hurtbox_fit.json")).regions
 body=StaticBody3D.new();body.name="DamageOnlyBody";body.collision_layer=4;body.collision_mask=0
 body.set_meta("hurtbox_actor",actor);add_child(body)
 for region in regions:
  region["index"]=skeleton.find_bone(region.bone)
  assert(region.index>=0,"Doge anatomy bone missing: "+region.bone)
  var shape=CollisionShape3D.new();shape.name=region.name;shape.shape=CapsuleShape3D.new();body.add_child(shape);shapes.append(shape)
 sync()
func vector(v) -> Vector3:return Vector3(v[0],v[1],v[2])
func sync() -> void:
 if not is_instance_valid(skeleton):return
 skeleton.force_update_all_bone_transforms()
 body.global_transform=Transform3D.IDENTITY
 body.collision_layer=4 if actor.controls_enabled and actor.stocks>0 else 0
 for i in regions.size():
  var r=regions[i];var bone=skeleton.global_transform*skeleton.get_bone_global_pose(r.index)
  var a=bone*vector(r.a);var b=bone*vector(r.b);var axis=b-a
  var radius=r.radius*maxf(bone.basis.x.length(),maxf(bone.basis.y.length(),bone.basis.z.length()))
  var s=shapes[i];s.shape.radius=radius;s.shape.height=axis.length()+2*radius
  s.global_transform=Transform3D(Basis.IDENTITY if axis.length_squared()<.00000001 else Basis(Quaternion(Vector3.UP,axis.normalized())),(a+b)*.5)
  s.force_update_transform()
 body.force_update_transform()

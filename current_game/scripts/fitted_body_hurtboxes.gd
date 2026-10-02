extends Node3D
# Damage only. Never alter the movement body, native animation or live morphs.
# Generic fitted receiver (same contract as doge_body_hurtboxes.gd): layer 4, hurtbox_actor meta,
# regions measured from native CPU-skinned vertices in res://scripts/<character_id>_hurtbox_fit.json.
# A region follows either a skeleton "bone" or, for rigid models (GGB), a named visual mesh "node".
var actor
var skeleton: Skeleton3D
var body: StaticBody3D
var shapes: Array[CollisionShape3D] = []
var regions: Array = []
var debug_visible := false
var meshes: Array[MeshInstance3D] = []
func _ready() -> void:
	actor=get_parent()
	var skeletons=actor._visual_root.find_children("*","Skeleton3D",true,false)
	skeleton=skeletons[0] if skeletons.size() else null
	var path:="res://scripts/%s_hurtbox_fit.json"%actor.character_id
	regions=JSON.parse_string(FileAccess.get_file_as_string(path)).regions
	body=StaticBody3D.new();body.name="DamageOnlyBody";body.collision_layer=4;body.collision_mask=0
	body.set_meta("hurtbox_actor",actor);add_child(body)
	for region in regions:
		if region.has("node"):
			region["target"]=actor._visual_root.find_child(region.node,true,false)
			assert(region.target!=null,"Fitted anatomy node missing: "+region.node)
		else:
			region["index"]=skeleton.find_bone(region.bone)
			assert(region.index>=0,"Fitted anatomy bone missing: "+region.bone)
		var shape=CollisionShape3D.new();shape.name=region.name;shape.shape=CapsuleShape3D.new();body.add_child(shape);shapes.append(shape)
		var mesh:=MeshInstance3D.new();mesh.mesh=CapsuleMesh.new()
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(1,0.08,0.7,0.22);material.no_depth_test=true
		mesh.material_override=material;mesh.visible=false;add_child(mesh);meshes.append(mesh)
	sync()
func vector(v) -> Vector3:return Vector3(v[0],v[1],v[2])
func sync() -> void:
	if is_instance_valid(skeleton):skeleton.force_update_all_bone_transforms()
	elif skeleton!=null or regions.is_empty():return
	body.global_transform=Transform3D.IDENTITY
	body.collision_layer=4 if actor.controls_enabled and actor.stocks>0 else 0
	for i in regions.size():
		var r=regions[i]
		var bone:Transform3D=r.target.global_transform if r.has("target") else skeleton.global_transform*skeleton.get_bone_global_pose(r.index)
		var a=bone*vector(r.a);var b=bone*vector(r.b);var axis=b-a
		var radius=r.radius*maxf(bone.basis.x.length(),maxf(bone.basis.y.length(),bone.basis.z.length()))
		var s=shapes[i];s.shape.radius=radius;s.shape.height=axis.length()+2*radius
		s.global_transform=Transform3D(Basis.IDENTITY if axis.length_squared()<.00000001 else Basis(Quaternion(Vector3.UP,axis.normalized())),(a+b)*.5)
		s.force_update_transform()
		meshes[i].global_transform=s.global_transform;meshes[i].mesh.radius=radius;meshes[i].mesh.height=s.shape.height
		meshes[i].visible=debug_visible and actor.visible and actor.controls_enabled
	body.force_update_transform()
func _process(_delta: float) -> void:
	if debug_visible: sync()
	elif meshes.size() and meshes[0].visible:
		for m in meshes: m.visible=false

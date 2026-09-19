extends SceneTree
var failures := 0
func check(ok: bool, msg: String):
	if not ok: failures += 1; printerr("FAIL: ",msg)
func _init(): call_deferred("run")
func run():
	var h = load("res://scripts/core/collision/generated_hurtbox.gd").new()
	h.hurtbox_id = "head"; h.bone_name = "Head"; h.radius = 0.2; h.height = 0.6
	h.local_transform = Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(1,2,3))
	check(h.validate().is_empty(), "authored rigid rotated local transform accepted")
	if h.validate().is_empty():
		var n = h.instantiate_shape()
		check(n.transform.is_equal_approx(h.local_transform), "instance preserves authored rotation")
		n.free()
	h.local_transform.basis = Basis.from_scale(Vector3(2,1,1))
	check(not h.validate().is_empty(), "nonuniform local scale rejected")
	var g = load("res://scripts/tools/generate_character_collisions.gd").new()
	var scene := Node3D.new(); root.add_child(scene)
	scene.transform = Transform3D(Basis(Vector3.UP,PI/2).scaled(Vector3.ONE*0.5), Vector3(3,4,5))
	var rig := Skeleton3D.new(); scene.add_child(rig)
	rig.add_bone("Hips"); rig.add_bone("Spine"); rig.set_bone_parent(1,0)
	rig.set_bone_rest(0,Transform3D(Basis.IDENTITY, Vector3(0,2,0)))
	rig.set_bone_rest(1,Transform3D(Basis.IDENTITY, Vector3(0,2,0)))
	var mesh := MeshInstance3D.new(); rig.add_child(mesh); mesh.skeleton = NodePath("..")
	var skin := Skin.new(); skin.add_bind(0,Transform3D.IDENTITY); skin.add_named_bind("Spine",Transform3D.IDENTITY); mesh.skin = skin
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,0,0),Vector3(1,0,0),Vector3(0,2,0)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,1,0,0,0,1,0,0,0,1,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([0.75,0.25,0,0,0.75,0.25,0,0,0.75,0.25,0,0])
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.mesh = am
	var r: Dictionary = g.analyze(scene,"weighted",2.0)
	check(r.errors.is_empty(), "blended skin with rotated scaled ancestor accepted")
	if r.errors.is_empty():
		# Blended Y = .75*2+.25*4 = 2.5. Half-scale + model origin + visual double => 10.5.
		check(r.profile.foot_origin.is_equal_approx(Vector3(0,10.5,0)), "independent blended and hierarchy foot oracle")
		check(is_equal_approx(r.profile.body_center.x,6) and is_equal_approx(r.profile.body_center.z,10), "full ancestor rotation translation and double visual scale")
		check(r.profile.hurtboxes.size() == 1 and not r.profile.warnings.is_empty(), "empty terminal bone omitted with warning")
	rig.scale = Vector3(1,2,1)
	check(not g.analyze(scene,"weighted",2.0).errors.is_empty(), "unsupported rig scale fails")
	rig.scale = Vector3.ONE; skin.set_bind_name(1,"Missing")
	check(not g.analyze(scene,"weighted",2.0).errors.is_empty(), "missing named skin bone fails")
	scene.free(); g.free()
	if failures == 0: print("PASS: core collision generator guards")
	quit(1 if failures else 0)

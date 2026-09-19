extends SceneTree
var failures := 0
func check(ok: bool, msg: String):
	if not ok: failures += 1; printerr("FAIL: ", msg)
func _init(): call_deferred("run")
func run():
	var path := "res://scripts/tools/generate_character_collisions.gd"
	check(ResourceLoader.exists(path), "real skin generator exists")
	if ResourceLoader.exists(path):
		var g = load(path).new()
		var scene := Node3D.new(); root.add_child(scene)
		var rig := Skeleton3D.new(); scene.add_child(rig)
		rig.position = Vector3(1, 0, 0)
		rig.add_bone("Hips"); rig.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)))
		var mesh := MeshInstance3D.new(); rig.add_child(mesh); mesh.skeleton = NodePath("..")
		var skin := Skin.new(); skin.add_named_bind("Hips", Transform3D(Basis.IDENTITY, Vector3(0, -1, 0))); mesh.skin = skin
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.2,0,0), Vector3(0.2,0,0), Vector3(0,2,0)])
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0])
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0])
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays); mesh.mesh = am
		var result: Dictionary = g.analyze(scene, "fixture", 2.0)
		check(result.errors.is_empty(), "known skin accepted")
		if result.errors.is_empty():
			var p = result.profile
			check(p.foot_origin.is_equal_approx(Vector3(0,2,0)), "bind then rest then ancestor then visual scale foot origin")
			var h = p.hurtboxes[0]
			check(h.bone_name == "Hips", "named skin bind resolved")
			# Local coordinates are inverse bone rest * skinned skeleton-space vertex.
			for point in [Vector3(-0.2,-1,0),Vector3(0.2,-1,0),Vector3(0,1,0)]:
				var q: Vector3 = point-h.local_transform.origin
				var axis := Vector3(0,clampf(q.y,-h.height/2+h.radius,h.height/2-h.radius),0)
				check(q.distance_to(axis) <= h.radius+0.00001, "independently known vertices inside bone capsule")
		check(not g.analyze(scene,"fixture",NAN).errors.is_empty(), "invalid scale fails")
		scene.free()
		for id in ["teknium", "ice_mage", "ggb"]:
			var meta: Dictionary = g.source_metadata(id)
			check(meta.errors.is_empty(), "read actual presenter metadata "+id)
			check(is_equal_approx(meta.scale, {"teknium":1.25,"ice_mage":1.15,"ggb":0.48186128424}[id]), "actual authored scale "+id)
			var n = load(meta.asset).instantiate(); root.add_child(n)
			var r: Dictionary = g.analyze(n,id,meta.scale)
			check(r.errors.is_empty(), "actual arrays analyzed "+id)
			if r.errors.is_empty():
				check(r.profile.validate().is_empty() and r.profile.body_height < 5.0, "units normalized including ancestor transforms "+id)
				check(r.profile.provenance.vertices > 1000, "actual surface vertices counted "+id)
				if id == "ggb": check(r.profile.hurtboxes.is_empty() and not r.profile.warnings.is_empty(), "static GGB has no fabricated bones")
			n.free()
		g.free()
	if failures == 0: print("PASS: core collision generator geometry")
	quit(1 if failures else 0)

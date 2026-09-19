extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func transforms(node: Node3D) -> Dictionary:
	var result := {".":node.transform}
	for child in node.find_children("*","Node3D",true,false): result[str(node.get_path_to(child))] = child.transform
	return result
func run() -> void:
	var path := "res://scripts/core/presentation/ggb_presenter.gd"
	if not FileAccess.file_exists(path):
		check(false,"committed GGB presenter missing")
		quit(1)
		return
	var packed = load("res://assets/ggb/ggb.glb")
	var raw = packed.instantiate()
	root.add_child(raw)
	var metadata := transforms(raw)
	var materials := []
	for mesh in raw.find_children("*","MeshInstance3D",true,false):
		var values := {}
		var material: Material = mesh.get_active_material(0)
		for property in material.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE: values[property.name] = material.get(property.name)
		materials.append(var_to_bytes(values))
	var glb_before := FileAccess.get_file_as_bytes("res://assets/ggb/ggb.glb")
	check(raw.find_children("*","AnimationPlayer",true,false).is_empty(),"source has no imported clips; do not invent source animation")
	for facing in [-1.0,1.0]:
		var v = load(path).new()
		var source = load("res://scripts/ggb_visual.gd").new()
		root.add_child(v)
		root.add_child(source)
		check(v.scale.is_equal_approx(source.scale),"approved scale preserved")
		for grounded in [true,false]:
			for tick in range(0,30):
				var delta := 0.0 if tick == 0 and grounded else 1.0/60
				source.sync_pose(grounded,Vector3(5,-1,0),false,facing,delta,false)
				v.present({"grounded":grounded,"velocity":Vector3(5,-1,0),"facing":facing},tick if grounded else tick+30)
				check(v.transform.is_equal_approx(source.transform),"root facing/placement parity")
				var expected := transforms(source.model)
				var actual := transforms(v.model)
				for key in expected: check(actual[key].is_equal_approx(expected[key]),"source node/wing attachment parity "+key)
		for i in source.meshes.size():
			check(v.meshes[i].get_active_material(0) != source.originals[i],"private material ownership")
			check(v.originals[i].albedo_texture == source.originals[i].albedo_texture,"painted texture preserved")
			check(v.originals[i].metallic == source.originals[i].metallic,"painted metallic preserved")
			check(v.originals[i].roughness == source.originals[i].roughness,"painted roughness preserved")
		v.free()
		source.free()
	check(transforms(raw) == metadata,"immutable imported transforms after duplicate playback")
	var mesh_index := 0
	for mesh in raw.find_children("*","MeshInstance3D",true,false):
		var values := {}
		var material: Material = mesh.get_active_material(0)
		for property in material.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE: values[property.name] = material.get(property.name)
		check(var_to_bytes(values) == materials[mesh_index],"immutable cached source material metadata")
		mesh_index += 1
	check(FileAccess.get_file_as_bytes("res://assets/ggb/ggb.glb") == glb_before,"immutable source asset bytes")
	raw.free()
	await process_frame
	if failures == 0: print("PASS: GGB source static model, materials, both-facing transforms and wing attachments")
	quit(1 if failures else 0)

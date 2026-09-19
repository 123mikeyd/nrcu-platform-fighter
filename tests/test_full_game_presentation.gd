extends SceneTree
## Differential oracle: actual untouched v0.2 main scene with Toy Shelf applied.
var failures := 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var original = load("res://scripts/main.gd").new()
	root.add_child(original)
	original.apply_level("toy_room")
	var stage = load("res://scripts/experimental/full_game_stage.gd").new()
	root.add_child(stage)
	var authored: Array = original.get_children().filter(func(n): return n is WorldEnvironment or n is Light3D or n is Camera3D)
	var actual: Array = stage.get_children().filter(func(n): return n is WorldEnvironment or n is Light3D or n is Camera3D)
	var source_camera: Camera3D = authored.filter(func(n): return n is Camera3D)[0]
	var preview_camera: Camera3D = actual.filter(func(n): return n is Camera3D)[0]
	check(preview_camera.projection == source_camera.projection,"original perspective projection")
	check(preview_camera.fov == source_camera.fov,"original 48 degree FOV")
	check(preview_camera.transform.is_equal_approx(source_camera.transform),"original camera inclination and position")
	check(actual.size() == authored.size(),"same environment/key/fill/camera inventory as original v0.2")
	for i in mini(actual.size(),authored.size()):
		check(actual[i].get_class() == authored[i].get_class(),"same presentation node types")
		if actual[i].get_class() != authored[i].get_class(): continue
		if authored[i] is WorldEnvironment:
			for property in authored[i].environment.get_property_list():
				if property.usage & PROPERTY_USAGE_STORAGE and not str(property.name).begins_with("resource_"):
					var a = actual[i].environment.get(property.name)
					var b = authored[i].environment.get(property.name)
					check(a.is_equal_approx(b) if a is Color else a == b,"original environment: "+property.name+" actual="+str(a)+" source="+str(b))
		elif authored[i] is Light3D:
			for property in authored[i].get_property_list():
				if str(property.name).begins_with("light_") or str(property.name).begins_with("shadow_") or property.name == "rotation":
					check(actual[i].get(property.name) == authored[i].get(property.name),"original light: "+property.name)
		elif authored[i] is Camera3D:
			check(actual[i].projection == authored[i].projection,"original perspective projection, never orthographic")
			check(actual[i].fov == authored[i].fov,"original FOV")
			check(actual[i].basis.is_equal_approx(authored[i].basis),"original view angle")
	original.free(); stage.free()
	if not failures: print("PASS: full game original v0.2 presentation parity")
	quit(1 if failures else 0)

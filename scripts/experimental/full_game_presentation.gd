extends RefCounted
## Reuse the untouched original scene's presentation factory, NOT its lifecycle.
## The temporary node never enters the tree: no fighters, input, stage or clocks.
static func install(parent: Node3D) -> Camera3D:
	var source = preload("res://scripts/main.gd").new()
	source._build_environment()
	var camera: Camera3D
	for node in source.get_children():
		source.remove_child(node)
		parent.add_child(node)
		if node is Camera3D: camera = node
	source.free()
	# Keep the authored static framing as well as its lens and inclination.
	# Full installed-body ledge routes and HUD bounds are regression-tested.
	camera.current = true
	return camera

extends Node3D
## Toy Shelf: exact original four collider dimensions, adapted group only.
var main_support: CollisionShape3D
var navigation_error := ""

func navigation_surfaces() -> Array:
	navigation_error = ""
	var surfaces := []
	for id in ["MainPlatform","Platform1","Platform2","Platform3"]:
		var body = get_node_or_null(id)
		if not body is StaticBody3D or body.collision_layer & 1 == 0:
			navigation_error = "Unsupported navigation support: " + id
			return []
		var shapes := []
		for child in body.get_children():
			if child is CollisionShape3D: shapes.append(child)
		if shapes.size() != 1 or shapes[0].disabled or not shapes[0].shape is BoxShape3D:
			navigation_error = "Navigation requires one enabled box: " + id
			return []
		var shape: CollisionShape3D = shapes[0]
		var basis := shape.global_transform.basis
		if not basis.is_finite() or not shape.global_position.is_finite() or not basis.x.is_equal_approx(Vector3(basis.x.x,0,0)) or not basis.y.is_equal_approx(Vector3(0,basis.y.y,0)) or not basis.z.is_equal_approx(Vector3(0,0,basis.z.z)) or basis.x.x <= 0 or basis.y.y <= 0 or basis.z.z <= 0:
			navigation_error = "Navigation requires finite axis-aligned supports: " + id
			return []
		var half: Vector3 = shape.shape.size * 0.5
		var low := shape.global_transform * -half
		var high := shape.global_transform * half
		surfaces.append({"id":id,"rect":Rect2(Vector2(low.x,low.y),Vector2(high.x-low.x,high.y-low.y)),"one_way":body.is_in_group("core_pass_through")})
	return surfaces

func _ready():
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("273a37")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	camera.position = Vector3(0,6,28)
	add_child(camera)
	camera.look_at(Vector3(0,3,0))
	camera.current = true
	var geometry = [[Vector3(0,-0.55,0),Vector3(18,1,5)], [Vector3(-5.2,3,0),Vector3(5,0.45,3.8)], [Vector3(5.2,3,0),Vector3(5,0.45,3.8)], [Vector3(0,6,0),Vector3(4.5,0.4,3.4)]]
	for i in geometry.size():
		var body := StaticBody3D.new()
		body.name = "MainPlatform" if i == 0 else "Platform%d" % i
		body.position = geometry[i][0]
		# Core terrain (including one-way) is bit 1; bit 2 is fighters.
		# The actor's existing group/foot-plane exceptions own ascent and drop.
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = geometry[i][1]
		body.add_child(shape)
		add_child(body)
		if i == 0: main_support = shape
		else:
			body.add_to_group("core_pass_through")
			body.set_meta("top_y", body.position.y + shape.shape.size.y * 0.5)
	var theme_node = preload("res://scripts/stage_theme.gd").new()
	theme_node.level_id = "toy_room"
	add_child(theme_node)
func ai_bounds() -> Dictionary:
	var half: Vector3 = main_support.shape.size * 0.5
	var low: Vector3 = main_support.global_transform * -half
	var high: Vector3 = main_support.global_transform * half
	return {"left":low.x,"right":high.x,"top":high.y}
func anchors() -> Array:
	var result := []
	var bounds := ai_bounds()
	for side in [-1,1]:
		var anchor = preload("res://scripts/core/stage/ledge_anchor.gd").new()
		anchor.anchor_id = "toy_room.main.left" if side == -1 else "toy_room.main.right"
		anchor.outward = side
		anchor.edge = Vector3(bounds.left if side == -1 else bounds.right,bounds.top,0)
		anchor.hang_offset = Vector3(0.65,-1.5,0)
		anchor.climb_offset = Vector3(-0.7,0.06,0)
		anchor.approach_width = 1.4
		anchor.approach_depth = 0.5
		anchor.min_foot_y = -1.8
		anchor.max_foot_y = -0.4
		result.append(anchor)
	return result

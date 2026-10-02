extends Node3D
# Cosmetic sleep indicator only: no timer, damage, input or collision ownership.
var glyphs: Array[Label3D] = []
var bubble: MeshInstance3D
var clock := 0.0
func _ready() -> void:
	for i in 3:
		var z := Label3D.new()
		z.text = "Z"
		z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		z.no_depth_test = true
		z.font_size = 72 + i * 22
		z.outline_size = 14
		z.outline_modulate = Color(0.12, 0.04, 0.22, 0.9)
		z.modulate = Color(0.78, 0.62, 1.0)
		z.pixel_size = 0.0065
		add_child(z)
		glyphs.append(z)
	bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	bubble.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.55, 1.0, 0.35)
	mat.no_depth_test = true
	bubble.material_override = mat
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubble)
func head_height(actor) -> float:
	var shapes = actor.get_hurtbox_shapes() if actor.has_method("get_hurtbox_shapes") else []
	var top := 1.9
	var found := false
	for shape in shapes:
		if shape is CollisionShape3D and shape.shape is CapsuleShape3D and not shape.disabled:
			var y: float = shape.global_position.y - actor.global_position.y + shape.shape.height * 0.5
			if not found or y > top: top = y
			found = true
	return clampf(top, 1.2, 3.2)
func present(actor) -> void:
	clock += get_physics_process_delta_time()
	var top := head_height(actor)
	var side: float = actor.facing
	position = Vector3(0, 0, 0.35)
	bubble.position = Vector3(side * 0.22, top - 0.12, 0)
	var s := 0.85 + 0.25 * sin(clock * 3.0)
	bubble.scale = Vector3.ONE * s
	for i in glyphs.size():
		var u := fmod(clock * 0.55 + float(i) / glyphs.size(), 1.0)
		var z := glyphs[i]
		z.position = Vector3(side * (0.3 + u * 0.45), top + 0.08 + u * 0.7, 0)
		z.modulate.a = sin(u * PI)
		z.outline_modulate.a = 0.9 * sin(u * PI)

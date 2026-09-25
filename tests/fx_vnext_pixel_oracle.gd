extends RefCounted
# Independent oracle: rasterize ORIGINAL scene nodes in their ORIGINAL hierarchy.
# No renderer mirror, decomposition, presentation_rect, or scope helper is used.
static func freeze(runtime) -> void:
	runtime.screen.lab_preview_pause()
	runtime.seek(1.0)
	runtime.screen.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 0.0

static func role_alpha(tree: SceneTree, runtime, roles: Array) -> Image:
	var selected: Array = []
	for key in runtime.registry.ordered_keys():
		if str(runtime.registry.context_for_key(key).get("element_role", "")) in roles:
			selected.append(runtime.registry.slot_nodes[key])
	var white := Shader.new()
	white.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR = vec4(1.0,1.0,1.0,COLOR.a); }"
	var hidden := Shader.new()
	hidden.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR = vec4(0.0); }"
	var saved: Array = []
	_isolate(runtime.screen, selected, white, hidden, saved)
	var old_transparent: bool = runtime.subvp.transparent_bg
	runtime.subvp.transparent_bg = true
	for i in 4: await tree.process_frame
	await RenderingServer.frame_post_draw
	var image: Image = runtime.subvp.get_texture().get_image()
	for state in saved:
		var node: CanvasItem = state[0]
		node.material = state[1]
		node.use_parent_material = state[2]
	runtime.subvp.transparent_bg = old_transparent
	for i in 4: await tree.process_frame
	return image

static func _isolate(node: Node, selected: Array, white: Shader, hidden: Shader, saved: Array) -> void:
	# Do not enter renderer-owned offscreen viewports.
	if node is SubViewport: return
	if node is CanvasItem:
		saved.append([node, node.material, node.use_parent_material])
		var mat := ShaderMaterial.new()
		mat.shader = white if node in selected else hidden
		node.material = mat
		node.use_parent_material = false
	for child in node.get_children(): _isolate(child, selected, white, hidden, saved)

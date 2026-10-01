extends SceneTree
# Capture only. tools/analyze_fx_pixels.py owns strict nonempty regional gates.
const Oracle = preload("res://tests/fx_vnext_pixel_oracle.gd")
var runtime
var renderer
var out_dir: String
var checks := 0
var failures := 0
var cases: Array = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
	if out_dir.is_empty(): out_dir = ProjectSettings.globalize_path("res://evidence/astra_scope")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var container := SubViewportContainer.new()
	container.size = Vector2(1280, 720)
	root.add_child(container)
	runtime = load("res://scripts/fx_vnext/fx_screen_runtime.gd").new()
	container.add_child(runtime.subvp)
	await process_frame
	check(runtime.mount("1v1", "debug", "ice_mage", "doge_man"), "real runtime mounts")
	Oracle.freeze(runtime)
	await settle()
	renderer = load("res://scripts/fx_vnext/fx_layer_renderer.gd").new(runtime.screen, runtime.registry)
	await capture_case("portraits")
	# Controlled original hierarchy, asymmetric silhouette with one BOUNDED hole.
	for key in runtime.registry.ordered_keys():
		if str(runtime.registry.context_for_key(key).get("element_role", "")) in ["primary", "echo"]:
			runtime.registry.slot_nodes[key].visible = false
	var p: TextureRect = runtime.registry.slot_nodes.primary_left
	var e: TextureRect = runtime.registry.slot_nodes.echo_left
	var group := Control.new()
	group.name = "ScopeAdversarialHierarchy"
	group.position = Vector2(400, 180)
	group.size = Vector2(340, 340)
	group.rotation = -0.12
	group.scale = Vector2(1.17, 0.83)
	group.clip_contents = true
	runtime.screen.get_node("Root").add_child(group)
	for node in [p, e]:
		node.reparent(group, false)
		node.top_level = false
		node.visible = true
		node.material = null
		node.modulate = Color.WHITE
		node.self_modulate = Color.WHITE
		node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.texture = fixture()
		node.size = Vector2(190, 260)
		node.pivot_offset = Vector2(35, 70)
		node.rotation = 0.19
		node.scale = Vector2.ONE
		# Below final passes, but primary above echo.
		node.z_index = -1 if node == p else -2
	p.position = Vector2(60, 30)
	e.position = Vector2(245, 65)
	e.scale = Vector2(-1.0, 1.0)
	e.flip_h = true
	e.modulate.a = 0.67
	await capture_case("fixture")
	# Parent fade/clip and nonuniform transform creates skew in global basis.
	group.modulate.a = 0.63
	group.size = Vector2(230, 260)
	e.position += Vector2(60, -25)
	e.self_modulate.a = 0.51
	await capture_case("moved_faded_clipped")
	group.visible = false
	await capture_case("hidden_ancestor")
	var file := FileAccess.open(out_dir.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": cases, "checks": checks, "failures": failures}, "  "))
	file.close()
	renderer.clear_all()
	print("[SCOPE-CAPTURE] done checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func capture_case(label: String) -> void:
	renderer.clear_final_composite()
	await settle()
	var primary: Image = await Oracle.role_alpha(self, runtime, ["primary"])
	primary.save_png(out_dir.path_join(label + "_primary_oracle.png"))
	var echo: Image = await Oracle.role_alpha(self, runtime, ["echo"])
	echo.save_png(out_dir.path_join(label + "_echo_preocclusion_oracle.png"))
	for scope in ["EXCLUDE_PRIMARY", "ECHO_ONLY", "PRIMARY_ONLY"]:
		var prefix: String = label + "_" + scope
		check(renderer.apply_final_composite([layer(scope, 0.0)]).get("ok", false), prefix + " neutral applies")
		renderer.set_clocks(0.0, 0.0)
		await settle()
		await capture(prefix + "_neutral")
		await settle()
		await capture(prefix + "_repeat")
		check(renderer.apply_final_composite([layer(scope, 1.0)]).get("ok", false), prefix + " active applies")
		renderer.set_clocks(0.0, 0.0)
		await settle()
		await capture(prefix + "_active")
		var pass_data: Dictionary = renderer._final_composite.passes[0]
		(pass_data.scope_viewport as SubViewport).get_texture().get_image().save_png(out_dir.path_join(prefix + "_matte.png"))
		if pass_data.has("primary_scope_viewport"):
			(pass_data.primary_scope_viewport as SubViewport).get_texture().get_image().save_png(out_dir.path_join(prefix + "_occluder.png"))
	cases.append(label)

func layer(scope: String, amount: float) -> Dictionary:
	return {"layer_id": "scope_probe", "type": "FX", "plane": "COMPOSITION_FOREGROUND", "authority": "COMPOSITION", "lane": "FINAL_COMPOSITE", "fx": {"operator": "NONE", "operator_strength": 0.0, "final_tint_amount": amount, "final_tint_color": [1.0, 0.05, 0.02, 1.0], "operator_scope": scope}}

func fixture() -> Texture2D:
	var image := Image.create(160, 220, false, Image.FORMAT_RGBA8)
	for y in 220:
		for x in 160:
			var inside := pow((x - 77.0) / 67.0, 2) + pow((y - 111.0) / 96.0, 2) < 1.0
			var hole := Vector2(x - 52, y - 74).length() < 17 or (x > 103 and y > 125 and y < 166)
			image.set_pixel(x, y, Color(0.2 + x / 400.0, 0.7, 0.9, 0.0 if not inside or hole else (0.35 if x < 35 or y > 192 else 1.0)))
	return ImageTexture.create_from_image(image)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	runtime.subvp.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))

func settle() -> void:
	for i in 6: await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[SCOPE-CAPTURE] %s %s" % ["PASS" if ok else "FAIL", label])
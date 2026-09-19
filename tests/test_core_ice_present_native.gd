extends SceneTree
## Native renderer characterization; no selectable roster or gameplay integration.
func _init() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PASS: native Ice screenshot skipped on headless display; run under xvfb-run")
		quit(0)
		return
	root.size = Vector2i(1100,650)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.055,.075,.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,2.3,7)
	camera.look_at(Vector3(0,1.1,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.7
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-35,-25,0)
	light.light_energy = 1.5
	for i in 2:
		var holder := Node3D.new()
		world.add_child(holder)
		holder.position.x = -1.4 if i == 0 else 1.4
		var v = load("res://scripts/core/presentation/ice_mage_presenter.gd").new()
		holder.add_child(v)
		var host = load("res://scripts/core/kits/ice_mage_host.gd").new()
		if i == 0: host.start_basic("native-strike",Vector2.RIGHT,false,1)
		else: host.start_special("native-rise",Vector2.UP,-1,true)
		for step in 12: host.prepare(false)
		v.present({"presentation":host.snapshot().presentation},12)
		var label := Label3D.new()
		holder.add_child(label)
		label.position.y = 2.8
		label.text = "IceStrike / + facing" if i == 0 else "Frost Rise: IceCast / - facing"
		label.font_size = 32
		label.pixel_size = .004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.verification/core/ice-presentation/native.png"
	var err := root.get_texture().get_image().save_png(path)
	world.free()
	await process_frame
	if err == OK: print("PASS: native rendered duplicate Ice source poses screenshot ",path)
	else: print("FAIL: screenshot save ",err)
	quit(0 if err == OK else 1)

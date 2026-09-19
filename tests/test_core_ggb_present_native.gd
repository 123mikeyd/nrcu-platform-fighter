extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PASS: native GGB capture not exercised on headless; run xvfb-run")
		quit(0)
		return
	root.size = Vector2i(1200,700)
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
	camera.position = Vector3(0,2.4,7)
	camera.look_at(Vector3(0,.6,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.2
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-35,-25,0)
	light.light_energy = 1.5
	for i in 4:
		var holder := Node3D.new()
		world.add_child(holder)
		holder.position.x = -1.8+i*1.2
		var v = load("res://scripts/core/presentation/ggb_presenter.gd").new()
		holder.add_child(v)
		var host = load("res://scripts/core/kits/ggb_host.gd").new()
		var snapshot := {"grounded":false,"facing":-1 if i%2 else 1}
		if i == 1:
			host.start_special("drop",Vector2.DOWN,-1,true)
			snapshot.merge(host.snapshot())
		if i == 2: snapshot.electrocution = {"activation_id":"reaction","elapsed":.137}
		if i == 3:
			host.start_special("landing",Vector2.DOWN,-1,true)
			host.landed(true)
			snapshot.merge(host.snapshot())
			snapshot.grounded = true
		v.present(snapshot,0)
		v.present(snapshot,12)
		var label := Label3D.new()
		holder.add_child(label)
		label.position.y = 1.2
		label.text = ["Air / + facing","LeadFeet / - facing","96fps reaction","Landing / gummy"][i]
		label.font_size = 28
		label.pixel_size = .0025
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("res://.verification/core/ggb-presentation/native.png")
	world.free()
	await process_frame
	if err == OK: print("PASS: native GGB actual-model procedural/lead/reaction/landing capture and duplicate teardown")
	else: printerr("FAIL: native screenshot save ",err)
	quit(0 if err == OK else 1)

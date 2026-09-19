extends "res://tests/test_core_collision_pose_policy.gd"
const Derived = preload("res://scripts/core/presentation/teknium_swing_source.gd")
const OUT := "res://.verification/core/teknium-swing-punch/"
func run():
	var host = preload("res://scripts/core/collision/collision_host.gd").new()
	check(host.configure(load("res://data/collision/generated/teknium.tres"),"swing-test").is_empty(),"host configured")
	var view = preload("res://scripts/core/presentation/teknium_presenter.gd").new(); root.add_child(view)
	var native := DisplayServer.get_name() != "headless"
	var world := Node3D.new(); root.add_child(world)
	if native:
		root.size = Vector2i(960,600)
		var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(0,1.1,6); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 3.2
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-35,-25,0)
		var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.1,.12,.16); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = .7; world.add_child(env)
	var c := context(); c.entity_id = 1; c.source_melee = true; c.strike_id = "swing"; c.strike_move = "SIDE STRIKE"
	var rows := []; var tick := 0
	for face in [-1,1]:
		c.facing = face
		for time in [0.0,.075,.115,.15,.167,.20,.25,.32]:
			c.strike_elapsed = time; host.commit(c,tick,Transform3D.IDENTITY,{}); tick += 1
			view.present_canonical(host.telemetry())
			check(view.model.visible and view.canonical.output.get("clip","") == Derived.CLIP,"canonical sink consumes authored swing")
			var r: Dictionary = host.telemetry().pose_request
			var pose: Dictionary = host.sampler.sample(r.clip,r.source_seconds,r.time_policy)
			for b in view.skeleton.get_bone_count():
				var actual: Transform3D = view.skeleton.global_transform*view.skeleton.get_bone_global_pose(b)
				check(actual.is_equal_approx(r.modelplacement*pose[str(view.skeleton.get_bone_name(b))]),"actual bone matches shared source")
			var shapes: Array = preload("res://scripts/core/combat/source_melee.gd").shapes(host,Transform3D.IDENTITY)
			check(shapes.size() == (1 if time >= .15 and time <= .20 else 0),"contact only measured extension window")
			if not shapes.is_empty(): check(shapes[0].a.is_equal_approx(view.skeleton.global_transform*view.skeleton.get_bone_global_pose(view.skeleton.find_bone("LeftHand")).origin),"visible hand is query center")
			rows.append({"face":face,"time":time,"hand":r.modelplacement*pose.LeftHand.origin,"elbow":r.modelplacement*pose.LeftForeArm.origin,"spine":pose.Spine,"shapes":shapes})
			if native:
				await process_frame; await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT+"swing-"+str(face)+"-"+str(time)+".png")
	var start: Dictionary = host.sampler.sample(Derived.CLIP,0,0)
	var windup: Dictionary = host.sampler.sample(Derived.CLIP,.075,0)
	var impact: Dictionary = host.sampler.sample(Derived.CLIP,.167,0)
	print("MEASURE hand ",windup.LeftHand.origin.distance_to(impact.LeftHand.origin)," torso ",windup.Spine.basis.get_rotation_quaternion().angle_to(impact.Spine.basis.get_rotation_quaternion()))
	check(start.Spine.basis.get_rotation_quaternion().angle_to(windup.Spine.basis.get_rotation_quaternion()) > .4,"real torso winds up at least .4 radians")
	check(windup.Spine.basis.get_rotation_quaternion().angle_to(impact.Spine.basis.get_rotation_quaternion()) > .7,"torso uncoils through impact")
	check(windup.LeftHand.origin.distance_to(impact.LeftHand.origin) > .4,"real hand arcs to extension")
	FileAccess.open(OUT+"pose-samples.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	view.free(); world.free()
	if not failures: print("PASS: Tek swing actual bones both faces windup arc canonical contact")
	quit(1 if failures else 0)

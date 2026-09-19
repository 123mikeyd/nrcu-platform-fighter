extends "res://tests/test_core_recovery_acceptance.gd"
const OUT := "res://.verification/core/melee-contact-alignment/"
var views := []
var native := false
var world: Node3D
var camera: Camera3D
func profile(character: String):
	var base = load("res://data/collision/generated/"+character+".tres")
	var merged: Dictionary = base.merged_with(load("res://data/collision/overrides/"+character+"_anatomical_v1.tres"))
	check(merged.errors.is_empty(),"anatomical override merges")
	return merged.profile
func capture(m, label: String):
	if not native: return
	var origin: Vector3 = m.fighters[1].actor.global_position
	for id in [1,2]:
		var record: Dictionary = m.collision_telemetry(id).contact_snapshot
		var r: Dictionary = record.pose_request
		var model: Node3D = views[id-1]
		model.transform = m.fighters[id].actor.global_transform*r.modelplacement
		model.position -= origin
		var ap: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
		ap.play(r.clip,0); ap.seek(r.source_seconds,true)
		model.find_children("*","Skeleton3D",true,false)[0].force_update_all_bone_transforms()
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func run():
	native = DisplayServer.get_name() != "headless"
	if native:
		root.size = Vector2i(960,600); world = Node3D.new(); root.add_child(world)
		camera = Camera3D.new(); world.add_child(camera); camera.position = Vector3(0,1.1,6); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4.5
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-35,-25,0)
		var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.1,.12,.16); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = .7; world.add_child(env)
	var records := []
	for character in ["teknium","turbofit"]:
		var other := "turbofit" if character == "teknium" else "teknium"
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,character); m.register_actor(2,b,-1,other)
		if native:
			for c in [character,other]:
				var model = load("res://assets/"+c+"/"+c+"_animations.glb").instantiate(); world.add_child(model); views.append(model)
				model.find_children("*","AnimationPlayer",true,false)[0].callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for ground in [true,false]:
			for vertical in [-1,0,1]:
				for face in [-1,1]:
					var offset := Vector3(face*1.1,0,0)
					if character == "turbofit" and not ground and vertical == 1: offset = Vector3(face*.4,-1.2,0)
					check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(0,20,0)+offset},{1:profile(character),2:profile(other)}),"merged actual match")
					# Vertical air fixture isolates combat from overlapping native bodies.
					if offset.y != 0: a.add_collision_exception_with(b); b.add_collision_exception_with(a)
					a.runtime.grounded = ground; m.fighters[1].facing = face; m.fighters[2].facing = -face
					await step(m,{1:press(Vector2(face,vertical),"attack")})
					var move: String = m.fighters[1].move_id
					var label: String = character+"-"+move.replace(" ","_")+"-"+str(face)
					if character == "turbofit" and vertical == -1: label += "-ground" if ground else "-air"
					check(not m.fighters[1].activation_id.is_empty(),"accepted real input "+label)
					check(m.events.is_empty(),"first frame no contact "+label)
					await capture(m,label+"-startup")
					var row := {"route":move,"ground":ground,"source":character,"target":other,"facing":face,"activation_tick":m.tick,"samples":[],"impact_age":-1,"impact_count":0}
					for age in range(0,45):
						if age > 0: await step(m)
						var record: Dictionary = m.collision_telemetry(1).contact_snapshot
						row.samples.append({"age":age,"source_pose":record.pose_request,"contacts":m.events.duplicate(true),"target_pose":m.collision_telemetry(2).contact_snapshot.pose_request})
						if age in [7,9,15,23]: await capture(m,label+"-age"+str(age))
						for event in m.events:
							if event.source == 1:
								row.impact_count += 1
								if row.impact_age < 0:
									row.impact_age = age; row.contact = event.duplicate(true)
									await capture(m,label+"-impact")
					check(row.impact_count == 1,"merged visible contact once "+label)
					records.append(row)
					print("ROUTE ",label," IMPACT ",row.impact_age," COUNT ",row.impact_count)
		a.free(); b.free()
		for view in views: view.free()
		views.clear()
	var file = FileAccess.open(OUT+("native" if native else "headless")+"-matrix.json",FileAccess.WRITE); file.store_string(JSON.stringify(records,"\t"))
	if native: world.free()
	if not failures: print("PASS: melee merged source contact matrix (%d checks)" % checks)
	quit(1 if failures else 0)

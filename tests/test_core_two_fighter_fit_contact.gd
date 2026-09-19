extends "res://tests/test_core_collision_snapshot.gd"
const Sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd")
const Kit = preload("res://scripts/core/kits/turbofit_kit.gd")
const ContactPose = preload("res://scripts/core/kits/turbofit_contact_pose.gd")
const OUT = "res://.verification/core/two-fighter-fit-pass/"
func run() -> void:
	var records = []
	var native = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280,720)
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	for id in ["teknium","turbofit"]:
		for facing in [-1,1]:
			for variant in ["before","after"]:
				lab.open_profile("res://data/collision/generated/"+id+".tres")
				if variant == "after": check(lab.reload_override("res://data/collision/overrides/"+id+"_anatomical_v1.tres"),"reload reviewed fit")
				var p = lab.working
				var packed = load(p.source_asset)
				var sampler = Sampler.new()
				check(sampler.configure(packed,lab.model.get_path_to(lab.skeleton),lab.model.get_path_to(lab.animation_player)) == OK,"actual target sampler")
				var service = load(BUILDER).new(); service.configure(p,p.source_asset,p.source_sha256,variant,"conservative_affine")
				var rev = revision(p,0.2); rev.clip = "Idle"
				var pose = sampler.sample("Idle",0.2,0)
				var distance = -1.0; var contact = {}; var snap = {}
				var source_origin = Vector3(0,-0.2 if "--torso" in OS.get_cmdline_user_args() else 0.45,0)
				for step in range(800,0,-1):
					var d = step*0.005
					var origin = Vector3(d*facing,0,0)
					var world = Transform3D(Basis(Vector3.UP,-facing*PI/2).scaled(Vector3.ONE*p.visual_scale),origin-p.foot_origin)
					snap = service.build(id,pose,world,rev)
					check(snap.ok,"snapshot contact fit")
					var kit = Kit.new(); kit.start("fit-contact",Vector2(facing,0),true,facing); kit.tick(5.0/30)
					var contacts = kit.contacts(1,source_origin,[{"id":2,"position":origin,"eligible":true,"geometry_mode":"generated_hurtboxes","hurtbox_snapshot":snap}])
					if not contacts.is_empty(): distance = d; contact = contacts[0]; break
				check(distance > 0 and contact.get("geometry_mode","") == "generated_hurtboxes","real AirSideKick first contact")
				if distance <= 0: continue
				lab.model.rotation.y = -facing*PI/2; lab.model.position = Vector3(distance*facing,0,0)-p.foot_origin; lab.scrub("Idle",0.2)
				lab.body_wire.position = Vector3(distance*facing,0,0)+p.body_center
				for wire in lab.hurt_wires: wire.mesh.surface_get_material(0).albedo_color = Color.MAGENTA
				var source = load("res://assets/turbofit/turbofit_animations.glb").instantiate(); lab.world.add_child(source)
				source.scale = Vector3.ONE*1.25; source.rotation.y = facing*PI/2; source.position = source_origin
				var player = source.find_children("*","AnimationPlayer",true,false)[0]
				player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				player.play("AirSideKick"); player.seek(5.0/30,true); player.advance(0)
				var center = source_origin+ContactPose.new().center("AirSideKick",5.0/30,facing)
				var sphere = lab.wire_capsule(0.22,0.44,Color.YELLOW); lab.world.add_child(sphere); sphere.position = center
				lab.camera.position = Vector3(distance*facing/2,1.4,6); lab.camera.look_at(Vector3(distance*facing/2,1.4,0)); lab.camera.size = 4.2
				var name_ = id+("-torso-contact-" if "--torso" in OS.get_cmdline_user_args() else "-contact-")+variant+"-"+str(facing)
				records.append({"target":id,"variant":variant,"facing":facing,"source_clip":"AirSideKick","source_seconds":5.0/30,"target_clip":"Idle","target_seconds":0.2,"distance":distance,"approach_step":0.005,"contact":contact,"source_sphere":center,"source_radius":0.22,"note":"real kit query; spatial first-contact at fixed active source time, NOT match damage or temporal first active frame"})
				if native:
					await process_frame; await process_frame; await RenderingServer.frame_post_draw
					lab.camera.get_viewport().get_texture().get_image().save_png(OUT+name_+".png")
					# Same native pose/camera, wire-free actual rendered visual evidence.
					for wire in lab.hurt_wires: wire.hide()
					lab.body_wire.hide(); sphere.hide()
					await process_frame; await RenderingServer.frame_post_draw
					lab.camera.get_viewport().get_texture().get_image().save_png(OUT+name_+"-visual.png")
					lab.model.hide()
					await process_frame; await RenderingServer.frame_post_draw
					lab.camera.get_viewport().get_texture().get_image().save_png(OUT+name_+"-source.png")
					lab.model.show(); source.hide()
					await process_frame; await RenderingServer.frame_post_draw
					lab.camera.get_viewport().get_texture().get_image().save_png(OUT+name_+"-target.png")
				source.free(); sphere.free()
	lab.free()
	for id in ["teknium","turbofit"]:
		for facing in [-1,1]:
			var pair = {}
			for r in records:
				if r.target == id and r.facing == facing: pair[r.variant] = r
			check(pair.size() == 2,"complete before/after first-contact pair")
			if pair.size() != 2: continue
			check(pair.after.distance <= pair.before.distance,"core tightening cannot extend tested real attack contact")
			if id == "turbofit" and not "--torso" in OS.get_cmdline_user_args():
				check(pair.before.distance-pair.after.distance >= 0.05,"Turbo upper torso early spatial contact reduced")
	var f = FileAccess.open(OUT+("first-contact-torso.json" if "--torso" in OS.get_cmdline_user_args() else "first-contact.json"),FileAccess.WRITE); f.store_string(JSON.stringify(records,"\t")); f.close()
	print("CONTACT CASES ",records.size())
	if not failures: print("PASS: actual AirSideKick spatial first contacts against merged fit")
	quit(1 if failures else 0)

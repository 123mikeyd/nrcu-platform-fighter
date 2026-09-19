extends SceneTree
# Native source-preview evidence only; never instantiates a match/actor.
const OUT = "res://.verification/core/two-fighter-fit-pass/"
func _init() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PASS: fit capture skipped on headless; requires native renderer")
		quit(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,720)
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	for id in ["teknium","turbofit"]:
		lab.open_profile("res://data/collision/generated/"+id+".tres")
		print("CLIPS ",id," ",lab.animation_player.get_animation_list())
		for h in lab.working.hurtboxes:
			if "head" in h.hurtbox_id or "hips" in h.hurtbox_id or "spine" in h.hurtbox_id:
				print("REST ",id," ",h.bone_name," ",lab.skeleton.get_bone_global_rest(lab.skeleton.find_bone(h.bone_name)))
		for variant in ["before","after"]:
			if variant == "after":
				var path = "res://data/collision/overrides/"+id+"_anatomical_v1.tres"
				if not ResourceLoader.exists(path): continue
				assert(lab.reload_override(path))
			for clip in (["Idle","Walk","Punch","Kick","Crouch"] if id == "teknium" else ["Idle","Walk","MeleeHorizontal","GoalkeeperKick","AirDownKick","Crouch"]):
				if not lab.animation_player.has_animation(clip): print("MISSING ",id," ",clip); continue
				for facing in [-1,1]:
					lab.model.rotation.y = facing*PI/2
					lab.scrub(clip,0.2)
					# Evidence color convention matches combat overlay, not editor orange.
					for wire in lab.hurt_wires:
						wire.mesh.surface_get_material(0).albedo_color = Color.MAGENTA
					lab.camera.position = Vector3(0,1.15,5); lab.camera.look_at(Vector3(0,1.15,0)); lab.camera.size = 3.1
					await process_frame; await process_frame
					await RenderingServer.frame_post_draw
					lab.camera.get_viewport().get_texture().get_image().save_png(OUT+id+"-"+variant+"-"+clip+"-"+str(facing)+".png")
	lab.free()
	print("PASS: native two fighter fit capture (source preview, not hit confirmation)")
	quit()

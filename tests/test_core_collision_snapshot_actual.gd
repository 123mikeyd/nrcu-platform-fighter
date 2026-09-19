extends "res://tests/test_core_collision_snapshot.gd"
const Sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd")
const Queries = preload("res://scripts/core/collision/hurtbox_queries.gd")
func animation_values(player: AnimationPlayer) -> Array:
	var values := []
	for name_ in player.get_animation_list():
		var a := player.get_animation(name_)
		values.append([name_,a.length,a.loop_mode])
		for t in a.get_track_count():
			values.append([a.track_get_path(t),a.track_get_type(t),a.track_is_enabled(t),a.track_get_interpolation_type(t)])
			for k in a.track_get_key_count(t): values.append([a.track_get_key_time(t,k),a.track_get_key_value(t,k),a.track_get_key_transition(t,k)])
	return values
func run() -> void:
	for id in ["teknium","ice_mage"]:
		var p: Resource = load("res://data/collision/generated/"+id+".tres")
		var packed: PackedScene = load(p.source_asset)
		var model: Node3D = packed.instantiate()
		root.add_child(model)
		var player: AnimationPlayer = model.get_node("AnimationPlayer")
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var source_before := animation_values(player)
		var profile_before := []
		for h in p.hurtboxes: profile_before.append([h.hurtbox_id,h.bone_name,h.radius,h.height,h.local_transform])
		var sampler := Sampler.new(); var other_sampler := Sampler.new()
		var skeleton := NodePath("Teknium_Master_Armature/Skeleton3D" if id == "teknium" else "Armature/Skeleton3D")
		check(sampler.configure(packed,skeleton,NodePath("AnimationPlayer")) == OK,"actual sampler configured: " + id)
		check(other_sampler.configure(packed,skeleton,NodePath("AnimationPlayer")) == OK,"duplicate actual sampler")
		var service = load(BUILDER).new(); var other = load(BUILDER).new()
		var sha := FileAccess.get_sha256(p.source_asset)
		check(service.configure(p,p.source_asset,sha,"generated-draft").is_empty(),"actual generated profile: " + id)
		check(other.configure(p,p.source_asset,sha,"generated-draft").is_empty(),"duplicate profile")
		# Generated data is tested at real clip endpoints, both facings/scales,
		# without repairing sampled basis shear or falling back to the body.
		var source_clips := ["Punch","Kick"] if id == "teknium" else ["IceStrike","IceCast"]
		for clip in source_clips:
			for seconds in [0.0,0.2,player.get_animation(clip).length]:
				for facing in [-1,1]:
					var generated_pose: Dictionary = sampler.sample(clip,seconds,0)
					var generated_rev := revision(p,seconds); generated_rev.clip = clip
					var generated_world := Transform3D(Basis(Vector3.UP,facing*PI/2).scaled(Vector3.ONE*p.visual_scale),Vector3(4,2,7))
					var generated: Dictionary = service.build(id,generated_pose,generated_world,generated_rev)
					var supported := true
					for h in p.hurtboxes:
						if Queries.capsule_from_transform(h.hurtbox_id,generated_pose[h.bone_name],2,1).is_empty() or Queries.capsule_from_transform(h.hurtbox_id,generated_world*generated_pose[h.bone_name]*h.local_transform,h.height,h.radius).is_empty(): supported = false
					check(generated.ok == supported,"actual sampler/query support boundary propagates")
					print("GENERATED ",id," clip=",clip," seconds=",seconds," facing=",facing," scale=",p.visual_scale," ok=",generated.ok," diagnostics=",generated.diagnostics)
					if not supported:
						check(generated.primitives.is_empty() and not generated.has_bounds and not generated.participation.active and not generated.diagnostics.is_empty(),"unsupported actual generated pose fails closed, never empty-success/body fallback")
					else:
						check(generated.primitives.size() == p.hurtboxes.size() and generated.has_bounds,"supported full generated set is complete")
		# Controlled native-bone-local profile: actual Hips track is supported.
		# Full generated limb sets remain separately labeled above, not silently repaired.
		var controlled = p.duplicate(true)
		controlled.hurtboxes.clear()
		var anchor = Hurtbox.new(); anchor.hurtbox_id = "hips"; anchor.bone_name = "Hips"
		anchor.radius = 5.0; anchor.height = 20.0; anchor.local_transform.origin = Vector3(150,0,0)
		controlled.hurtboxes.append(anchor)
		service.configure(controlled,p.source_asset,sha,"controlled-native-hips")
		other.configure(controlled,p.source_asset,sha,"controlled-native-hips")
		var first_ids := []; var previous_primitives := []; var changed := false; var outside_body := false
		var pose0 := {}; var revision0 := {}; var snapshot0 := {}; var world0 := Transform3D.IDENTITY
		for facing in [-1,1]:
			var world := Transform3D(Basis(Vector3.UP,facing*PI/2).scaled(Vector3.ONE*p.visual_scale),Vector3(4,2,7))
			var clips := ["Punch","Kick"] if id == "teknium" else ["IceStrike","IceCast"]
			for clip in clips:
				for seconds in [0.0,0.2,0.4]:
					var pose: Dictionary = sampler.sample(clip,seconds,Sampler.TimePolicy.CLAMP)
					var rev := revision(p,seconds); rev.clip = clip
					var snapshot: Dictionary = service.build(id,pose,world,rev)
					check(snapshot.ok and snapshot.primitives.size() == controlled.hurtboxes.size(),"controlled actual-sampler world primitives: " + id + " " + clip)
					if not snapshot.ok: print(snapshot.diagnostics); continue
					var ids := []
					for c in snapshot.primitives:
						ids.append(c.id)
						var extent := Vector3.ONE*float(c.radius)
						var lo: Vector3 = c.a.min(c.b)-extent; var hi: Vector3 = c.a.max(c.b)+extent
						check(lo.x >= snapshot.aabb.position.x-0.00001 and lo.y >= snapshot.aabb.position.y-0.00001 and lo.z >= snapshot.aabb.position.z-0.00001,"actual lower bound contains limb")
						var end: Vector3 = snapshot.aabb.end
						check(hi.x <= end.x+0.00001 and hi.y <= end.y+0.00001 and hi.z <= end.z+0.00001,"actual upper bound contains limb")
						# Body is separately actor-space, already visual-scaled by generator.
						var body := Queries.capsule_from_transform("body",Transform3D(Basis.IDENTITY,Vector3(4,2,7)+p.body_center),p.body_height,p.body_radius)
						if not Queries.sphere_overlap(c.a,0,body) or not Queries.sphere_overlap(c.b,0,body): outside_body = true
					if first_ids.is_empty(): first_ids = ids
					check(ids == first_ids,"stable actual IDs across clip/time/facing")
					if not previous_primitives.is_empty() and previous_primitives != snapshot.primitives: changed = true
					previous_primitives = snapshot.primitives
					pose0 = pose; revision0 = rev; snapshot0 = snapshot; world0 = world
		check(changed and outside_body,"controlled animated anchor represented outside movement body: " + id)
		if snapshot0.is_empty(): model.free(); continue
		var second_pose := other_sampler.sample(revision0.clip,revision0.seconds,0)
		var second: Dictionary = other.build(id,second_pose,world0,revision0)
		check(second == snapshot0,"duplicate sampler/service exact values")
		model.hide(); model.transform = Transform3D(Basis.IDENTITY,Vector3(999,999,999))
		service.reset()
		check(service.build(id,pose0,world0,revision0) == snapshot0,"hidden/moved presentation independent after cache reset")
		check(animation_values(player) == source_before,"complete animation values remain unchanged")
		model.free(); service.reset()
		check(service.build(id,sampler.sample(revision0.clip,revision0.seconds,0),world0,revision0) == snapshot0,"deleted presentation independent")
		var profile_after := []
		for h in p.hurtboxes: profile_after.append([h.hurtbox_id,h.bone_name,h.radius,h.height,h.local_transform])
		check(profile_before == profile_after,"actual resource geometry immutable")
		print("ACTUAL ",id," sha256=",sha," hurtboxes=",first_ids.size())
	if not failures: print("PASS: collision snapshot actual generated profiles and presentation independence")
	quit(1 if failures else 0)

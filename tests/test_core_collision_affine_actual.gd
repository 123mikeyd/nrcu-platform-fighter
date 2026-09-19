extends "res://tests/test_core_collision_snapshot.gd"
const Sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd")
func run() -> void:
	var records := []; var conversions := 0; var valid := 0
	for id in ["teknium","ice_mage","turbofit"]:
		var p: Resource = load("res://data/collision/generated/"+id+".tres")
		var packed: PackedScene = load(p.source_asset)
		var model = packed.instantiate()
		var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
		var skeleton: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
		var sampler = Sampler.new()
		check(sampler.configure(packed,model.get_path_to(skeleton),model.get_path_to(player)) == OK,"actual sampler configured")
		var service = load(BUILDER).new()
		var args := [p,p.source_asset,FileAccess.get_sha256(p.source_asset),"affine-draft"]
		for method in service.get_method_list():
			if method.name == "configure" and method.args.size() == 5: args.append("conservative_affine")
		check(service.callv("configure",args).is_empty(),"configure actual affine profile")
		var clips := ["Punch","Kick"] if id == "teknium" else (["IceStrike","IceCast"] if id == "ice_mage" else ["AirDownKick","AirSideKick"])
		for clip in clips:
			check(player.has_animation(clip),"real clip exists: "+clip)
			for seconds in [0.0,0.2,player.get_animation(clip).length]:
				for facing in [-1,1]:
					var pose: Dictionary = sampler.sample(clip,seconds,0)
					var world := Transform3D(Basis(Vector3.UP,facing*PI/2).scaled(Vector3.ONE*p.visual_scale),Vector3(4,2,7))
					var rev := revision(p,seconds); rev.clip = clip
					var snapshot: Dictionary = service.build(id,pose,world,rev)
					conversions += 1
					check(snapshot.ok and snapshot.primitives.size() == p.hurtboxes.size(),"full generated affine conversion: %s %s %s %s" % [id,clip,seconds,facing])
					if snapshot.ok: valid += 1
					var by_id := {}
					for c in snapshot.primitives: by_id[c.id] = c
					for h in p.hurtboxes:
						var t: Transform3D = world*pose[h.bone_name]*h.local_transform
						var columns := []
						for v in [t.basis.x,t.basis.y,t.basis.z]: columns.append([v.x,v.y,v.z])
						var rec := {"character":id,"clip":clip,"seconds":seconds,"facing":facing,"id":h.hurtbox_id,"columns":columns,"native_radius":h.radius}
						if by_id.has(h.hurtbox_id):
							var c: Dictionary = by_id[h.hurtbox_id]
							rec.radius = c.radius
							# Independent scalar-double affine point and segment-distance oracle.
							for axis in 3:
								check(float(snapshot.aabb.position[axis]) <= minf(c.a[axis],c.b[axis])-float(c.radius),"outward lower AABB")
								check(float(snapshot.aabb.end[axis]) >= maxf(c.a[axis],c.b[axis])+float(c.radius),"outward upper AABB")
							for spine in [-1.0,0.0,1.0]:
								for k in 128:
									var y := 1.0-2.0*(k+0.5)/128.0
									var r := sqrt(1.0-y*y); var angle := k*2.399963229728653
									var local := [h.radius*r*cos(angle),h.radius*y+spine*(h.height*0.5-h.radius),h.radius*r*sin(angle)]
									var point := []; var ab := []; var delta := []; var den := 0.0; var num := 0.0
									for axis in 3:
										point.append(float(t.origin[axis])+columns[0][axis]*local[0]+columns[1][axis]*local[1]+columns[2][axis]*local[2])
										ab.append(float(c.b[axis])-c.a[axis]); delta.append(point[axis]-c.a[axis])
										den += ab[axis]*ab[axis]; num += delta[axis]*ab[axis]
									var u := clampf(num/den,0,1) if den > 0 else 0.0; var d2 := 0.0
									for axis in 3: d2 += pow(delta[axis]-u*ab[axis],2)
									check(d2 <= c.radius*c.radius,"affine bone capsule surface contained")
						records.append(rec)
		model.free()
	DirAccess.make_dir_recursive_absolute("res://.verification/core/collision-affine-fix")
	var file := FileAccess.open("res://.verification/core/collision-affine-fix/matrices.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(records)); file.close()
	print("CONVERSIONS ",valid,"/",conversions," capsule records=",records.size())
	if not failures: print("PASS: actual generated affine envelopes and independent containment")
	quit(1 if failures else 0)

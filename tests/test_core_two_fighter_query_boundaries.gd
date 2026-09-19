extends "res://tests/test_core_recovery_acceptance.gd"
const Recipient = preload("res://scripts/core/collision/recipient_queries.gd")
func ball(center: Vector3, radius: float = .125) -> Dictionary:
	return {"geometry_mode":"generated_hurtboxes","hurtbox_snapshot":{"ok":true,"primitives":[{"id":"oracle","a":center,"b":center,"radius":radius}]}}
func run():
	# Independent closed-form face/cap/side tangencies, with representable guards.
	for epsilon in [-.001,0.0,.001]:
		var expected: bool = epsilon <= 0
		check((not Recipient.cone(ball(Vector3(2.625+epsilon,0,0)),Vector3.ZERO,Vector3.RIGHT,2.5).is_empty()) == expected,"cone spherical cap boundary "+str(epsilon))
		var side := Vector3(.4,sqrt(.84),0)
		var outward := Vector3(-side.y,side.x,0)
		check((not Recipient.cone(ball(side+outward*(.125+epsilon)),Vector3.ZERO,Vector3.RIGHT,2.5).is_empty()) == expected,"cone angular side boundary "+str(epsilon))
		check((not Recipient.box(ball(Vector3(1.425+epsilon,1,0)),Vector3.ZERO,Vector3(-1.3,-.4,-1),Vector3(1.3,2.6,1)).is_empty()) == expected,"box face boundary "+str(epsilon))
		check((not Recipient.cylinder_sweep(ball(Vector3(0,.625+epsilon,0)),Vector3.ZERO,0,.5,.34).is_empty()) == expected,"cylinder radial boundary "+str(epsilon))
		check((not Recipient.cylinder_sweep(ball(Vector3(.465+epsilon,0,0)),Vector3.ZERO,0,.5,.34).is_empty()) == expected,"cylinder flat cap boundary "+str(epsilon))
		check((not Recipient.sphere(ball(Vector3(1.125+epsilon,0,0)),Vector3.ZERO,Vector3.ZERO,1).is_empty()) == expected,"sphere boundary "+str(epsilon))
	var sweep: Dictionary = Recipient.cylinder_sweep(ball(Vector3(2,0,0)),Vector3.ZERO,3,.5,.375)
	check(not sweep.is_empty() and absf(sweep.get("t",-1)-.5) < .00001,"cylinder axial sweep earliest time")
	check(Recipient.cylinder_sweep(ball(Vector3(2,.8,0)),Vector3.ZERO,3,.5,.375).is_empty(),"swept cylinder radial miss")
	# Depth and cone/range must intersect jointly, not independent capsule checks.
	var p := Vector3(1,0,3)
	var projection: Vector3 = Recipient._project_sector_slab(p,Vector3.RIGHT,2.5,1.5,.4)
	check(absf(projection.z-1.5) < .00001 and projection.length() <= 2.50001 and projection.x >= projection.length()*.4-.00001,"joint sector/slab projection feasible")
	for x in [-10.0,-3.0,-1.0,0.0,1.0,3.0,10.0]:
		for y in [-10.0,-3.0,-1.0,0.0,1.0,3.0,10.0]:
			for z in [-10.0,-3.0,-1.0,0.0,1.0,3.0,10.0]:
				var sample := Vector3(x,y,z)
				var projected: Vector3 = Recipient._project_sector_slab(sample,Vector3.RIGHT,2.5,1.5,.4)
				check(absf(projected.z) <= 1.50001 and projected.length() <= 2.50001 and projected.x >= projected.length()*.4-.00001,"joint projection feasible "+str(sample))
				var worst := 0.0
				for qy in [-2.0,-1.0,0.0,1.0,2.0]:
					for qz in [-1.5,-.75,0.0,.75,1.5]:
						for qx in [.5,1.0,1.5,2.0,2.5]:
							var q := Vector3(qx,qy,qz)
							if q.length() <= 2.5 and q.x >= .4*q.length(): worst = maxf(worst,(sample-projected).dot(q-projected))
				check(worst < .0001,"projection variational inequality "+str(sample)+" residual="+str(worst))
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1,a)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3.ZERO},{1:load("res://data/collision/generated/"+character+".tres")}),"actual profile boundaries")
		m._commit_collision_poses([1])
		var snapshot: Dictionary = m.collision_telemetry(1).contact_snapshot
		var target := {"geometry_mode":"generated_hurtboxes","hurtbox_snapshot":snapshot}
		var edge := Vector3.ZERO; var minimum := INF
		for capsule in snapshot.primitives:
			for end: Vector3 in [capsule.a,capsule.b]:
				if end.x-float(capsule.radius) < minimum:
					minimum = end.x-float(capsule.radius); edge = Vector3(minimum,end.y,end.z)
		# Actual imported, affine-enclosed limbs: signed near-tangent controls.
		# The guard exceeds float32 coordinate rounding; no profile is shrunk.
		for epsilon in [-.0001,.0001]:
			var grazing := edge+Vector3(epsilon,0,0)
			var expected: bool = epsilon > 0
			for radius in [0.0,.18,.22,1.15]:
				var point := grazing-Vector3(radius,0,0)
				check((not Recipient.sphere(target,point,point,radius).is_empty()) == expected,"actual Force/grab/kick/Orb grazing "+character+str([radius,epsilon]))
			check((not Recipient.box(target,grazing-Vector3(1.3,0,0),Vector3(-1.3,-.4,-1),Vector3(1.3,2.6,1)).is_empty()) == expected,"actual recovery grazing "+character+str(epsilon))
			check((not Recipient.cylinder_sweep(target,grazing-Vector3(.34,0,0),0,.5,.34).is_empty()) == expected,"actual Wave cap grazing "+character+str(epsilon))
			for reach in [2.5,2.8,3.0]:
				check((not Recipient.cone(target,grazing-Vector3(reach,0,0),Vector3.RIGHT,reach).is_empty()) == expected,"actual basic/Chord grazing "+character+str([reach,epsilon]))
		var center: Vector3 = snapshot.primitives[0].a
		check(not Recipient.sphere(target,center,center,.18).is_empty(),"actual limb sphere interior")
		check(Recipient.sphere(target,center+Vector3(50,0,0),center+Vector3(50,0,0),.18).is_empty(),"actual limb sphere exterior")
		check(not Recipient.box(target,center,Vector3(-1,-1,-1),Vector3.ONE).is_empty(),"actual limb box interior")
		check(Recipient.box(target,center+Vector3(50,0,0),Vector3(-1,-1,-1),Vector3.ONE).is_empty(),"actual limb box exterior")
		check(not Recipient.cylinder_sweep(target,center,0,.5,.34).is_empty(),"actual limb cylinder interior")
		check(Recipient.cylinder_sweep(target,center+Vector3(50,0,0),1,.5,.34).is_empty(),"actual limb cylinder exterior")
		for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3(1,-.25,0).normalized()]:
			check(not Recipient.cone(target,center-direction, direction,2.5).is_empty(),"actual limb cone interior")
			check(Recipient.cone(target,center+direction*50,direction,2.5).is_empty(),"actual limb cone exterior")
	a.free()
	if not failures: print("PASS: two fighter query boundaries (%d checks)" % checks)
	quit(1 if failures else 0)

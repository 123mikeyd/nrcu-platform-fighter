extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var specs := {"Punch":["teknium",.6,.8],"Kick":["teknium",.7,1.0],"MeleeHorizontal":["turbofit",52.0/60,59.0/60],"MeleeBackhand":["turbofit",.7,.9],"GoalkeeperKick":["turbofit",.8,62.0/60]}
	for clip in specs:
		var spec: Array = specs[clip]
		var host = preload("res://scripts/core/collision/collision_host.gd").new()
		check(host.configure(load("res://data/collision/generated/"+spec[0]+".tres"),"boundary").is_empty(),"actual private imported sampler")
		for time in [spec[1]-1e-9,spec[1],spec[2],spec[2]+1e-9]:
			host._contact_record = {"ok":true,"pose_request":{"clip":clip,"source_seconds":time,"time_policy":0,"modelplacement":Transform3D(Basis(Vector3.UP,PI/2).scaled(Vector3.ONE*1.25),Vector3.ZERO),"pose_revision":1}}
			var shapes: Array = preload("res://scripts/core/combat/source_melee.gd").shapes(host,Transform3D.IDENTITY)
			check((not shapes.is_empty()) == (time >= spec[1] and time <= spec[2]),"exact source window double boundary "+clip+str(time))
	if not failures: print("PASS: melee window boundaries (%d checks)" % checks)
	quit(1 if failures else 0)

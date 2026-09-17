extends "res://tests/test_core_collision_pose_policy.gd"
func run() -> void:
	var policy = load(POLICY).new(); var m := metadata("teknium")
	policy.configure(m)
	var actor = load("res://scripts/core/fighter/fighter_actor.gd").new(); root.add_child(actor)
	var c := context(); c.merge(actor.telemetry(),true)
	check(policy.sample(c,0).get("ok",false),"real actor neutral action is accepted")
	actor.runtime.states.action = "landing_lock"; c.merge(actor.telemetry(),true)
	check(policy.sample(c,1).get("ok",false),"real actor landing action is accepted")
	actor.free()
	policy.configure(metadata("turbofit")); c = context(); c.action = "movement_lock"
	var kit = load("res://scripts/core/kits/turbofit_kit.gd").new(); kit.start("kick",Vector2.RIGHT,true,1.0); kit.tick(.18)
	c.presentation = kit.snapshot().presentation
	check(policy.sample(c,0).get("clip","") == "AirSideKick","committed live kit movement lock is not shielding")
	c.shielding = true
	check(policy.sample(c,0).get("clip","") == "BlockIdle","explicit shield remains above kit")
	var bad := m.duplicate(true); var alternate: Dictionary = bad.sources[0].duplicate(true)
	alternate.source_asset = "res://alternate.glb"; alternate.skeleton_placement = Transform3D(Basis.IDENTITY,Vector3.UP); bad.sources.append(alternate)
	check(not policy.configure(bad).is_empty(),"alternate root placement mismatch cannot retarget generated profile")
	if not failures: print("PASS: committed policy actor telemetry seam")
	quit(1 if failures else 0)

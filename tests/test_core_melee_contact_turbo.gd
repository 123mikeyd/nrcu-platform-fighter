extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	for clip in ["MeleeHorizontal","MeleeBackhand","GoalkeeperKick"]:
		for face in [-1,1]:
			check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(face*2.4,20,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/teknium.tres")}),"actual profiles")
			await step(m)
			var basic = preload("res://scripts/core/kits/turbofit_kit.gd").new()
			basic.start("bounded",Vector2.UP if clip == "MeleeBackhand" else Vector2(face,1 if clip == "GoalkeeperKick" else 0),false,face)
			basic.tick(.45 if clip == "GoalkeeperKick" else .28)
			check(basic.contacts(1,a.global_position,m._kit_targets(1)).is_empty(),"no source pose means no generated broadcone fallback "+clip+str(face))
	a.free(); b.free()
	if not failures: print("PASS: melee Turbo bounded (%d checks)" % checks)
	quit(1 if failures else 0)

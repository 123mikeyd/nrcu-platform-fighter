extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
	for facing in [-1,1]:
		check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(facing*1.3,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/turbofit.tres")}),"actual imported profiles")
		await step(m,{1:press(Vector2(facing,0),"attack")})
		check(m.fighters[1].move_id == "AIR STRIKE","real buffered input accepted")
		check(m.fighters[2].percent == 0,"empty-space source-time-zero punch must not damage facing "+str(facing))
		check(m.events.is_empty(),"no first-frame contact event")
	a.free(); b.free()
	if not failures: print("PASS: melee contact startup (%d checks)" % checks)
	quit(1 if failures else 0)

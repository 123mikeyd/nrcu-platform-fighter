extends "res://tests/test_core_top_support.gd"
func setup_pair(lower := "teknium", upper := "teknium", reverse := false, interaction_mode := "legacy_solid"):
	var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	if reverse: m.register_actor(2,b,-1,lower); m.register_actor(1,a,-1,upper)
	else: m.register_actor(1,a,-1,upper); m.register_actor(2,b,-1,lower)
	m.reset_with_collision_profiles({1:Vector3(0,3,0),2:Vector3.ZERO},{1:fitted(upper),2:fitted(lower)},interaction_mode)
	a.runtime.air_jumps_left = 0; a.runtime.recovery_spent = true
	return {"m":m,"a":a,"b":b,"floor":floor_node}
func acquire(f):
	var acquired = false
	for i in 70:
		await step(f.m)
		if not f.m.top_support_telemetry(1).relation.is_empty(): acquired = true; break
	check(acquired,"actual swept support acquisition prerequisite")
	return acquired
func dispose(f):
	f.a.free(); f.b.free(); f.floor.free()
func run():
	var f = setup_pair()
	await acquire(f)
	check(not f.m.top_support_telemetry(1).geometry.is_empty(),"generated mode has geometry")
	check(f.m.reset_with_body_profiles({1:Vector3(0,3,0),2:Vector3.ZERO},{1:null,2:null}),"body-only reset")
	check(f.m.top_support_telemetry(1).geometry.is_empty() and f.m.top_support_telemetry(2).geometry.is_empty(),"body-only reset retires generated support opt-in")
	dispose(f)
	if not failures: print("PASS: top support lifecycle")
	quit(1 if failures else 0)

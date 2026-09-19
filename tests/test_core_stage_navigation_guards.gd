extends "res://tests/test_core_stage_navigation.gd"
const Frame = preload("res://scripts/core/input/input_frame.gd")
func own() -> Dictionary:
	return {"id":2,"position":Vector3(-4,-0.05,0),"velocity":Vector3.ZERO,"grounded":true,"air_jumps_left":1,"can_jump":true,"team":-1,"enabled":true}
func target() -> Dictionary:
	return {"id":1,"position":Vector3(-7,3.225,0),"team":-1,"enabled":true}
func run():
	var nav = load("res://scripts/core/input/stage_navigation.gd").new()
	nav.configure(surfaces(),caps())
	var frame = nav.adapt(Frame.new(),own(),[target()],true,true)
	check(frame.pressed.get("jump",false) and frame.held.jump,"legal launch edge")
	var age: int = nav._age
	var stopped = nav.adapt(Frame.new(),own(),[target()],false,false)
	check(stopped.held.get("jump",false) and not stopped.pressed.get("jump",false),"hitstop retains held jump without new edge")
	check(nav._age==age,"hitstop freezes navigation clock")
	nav.reset()
	var approaching := own(); approaching.position.x = 5.0
	frame = nav.adapt(Frame.new(),approaching,[target()],true,true,0,0.55,true)
	check(frame.axis.x < 0,"ground approach prerequisite")
	frame = nav.adapt(Frame.new(),approaching,[target()],false,true,0,0.55,false)
	check(frame.axis == Vector2.ZERO and not frame.held.get("jump",false),"Sparring breath suspends grounded navigation approach")
	nav.reset()
	var held_special = Frame.new(); held_special.held.special = true; held_special.axis=Vector2.RIGHT
	frame = nav.adapt(held_special,approaching,[target()],true,true)
	check(not frame.held.special and frame.axis.x < 0,"uncommitted stale cast is deferred during critical navigation; still brakes")
	nav.configure(surfaces(),caps())
	check(nav._leg.is_empty() and nav._age == 0,"geometry reconfiguration clears stale intent/history")
	var low := caps(); low.full_jump_speed = 2.0; low.air_jump_speed = 1.0
	check(nav.configure(surfaces(),low),"weak authored capabilities accepted")
	check(nav.route("main","left").is_empty(),"unreachable surface omitted from graph")
	for i in 400:
		var original = Frame.new(); original.held.jump=true; original.pressed.jump=true
		original.held.attack = i%120==0; original.pressed.attack = i%120==0
		original.axis=Vector2.RIGHT
		var result = nav.adapt(original,own(),[target()],i%26==0,true)
		check(not result.held.jump and not result.pressed.get("jump",false),"unreachable target never endlessly jumps")
		check(result.held.attack == (i%120==0) and result.pressed.attack == (i%120==0),"combat budget/edges preserved")
	nav.configure(surfaces(),caps())
	for i in 24:
		frame = nav.adapt(Frame.new(),own(),[target()],false,true,24,0.55)
		check(not frame.pressed.get("jump",false),"no early Sparring target reaction")
	frame = nav.adapt(Frame.new(),own(),[target()],true,true,24,0.55)
	check(frame.pressed.get("jump",false),"delayed sparse decision can start a route")
	nav.configure(surfaces(),caps())
	var hostile := target(); hostile.team = 1
	var ally := own(); ally.team = 1
	frame = nav.adapt(Frame.new(),ally,[hostile],true,true)
	check(nav._goal.is_empty() and frame.pressed.is_empty(),"allies do not become navigation targets")
	nav.configure(surfaces(),caps())
	var attempts := 0
	for i in 1000:
		frame = nav.adapt(Frame.new(),own(),[target()],i%26==0,true)
		if frame.pressed.get("jump",false): attempts += 1
	check(attempts==3 and nav._leg.is_empty(),"rejected jumps stop after three spaced attempts, never endless spam")
	if not failures: print("PASS: navigation frozen clocks delay budgets unreachable reset and finite retry guards")
	quit(1 if failures else 0)

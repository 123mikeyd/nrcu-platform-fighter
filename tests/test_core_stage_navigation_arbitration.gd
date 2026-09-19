extends "res://tests/test_core_stage_navigation_guards.gd"
func offense():
	var f = Frame.new(); f.held.special = true; f.pressed.special = true; f.axis = Vector2.RIGHT
	return f
func run():
	var nav = load("res://scripts/core/input/stage_navigation.gd").new()
	nav.configure(surfaces(),caps())
	var f = nav.adapt(offense(),own(),[target()],true,true)
	check(not f.held.get("special",false) and not f.pressed.get("special",false),"defer new unreachable offense during critical launch")
	check(f.pressed.get("jump",false),"takeoff receives neutral combat input")
	var nearby_air := own(); nearby_air.position=Vector3(-5.9,2.3,0); nearby_air.grounded=false
	f = nav.adapt(offense(),nearby_air,[target()],false,true)
	check(f.held.special and f.pressed.special,"nearby upward combat opportunity survives an active flight")
	nav.reset()
	var locked := own(); locked.can_jump = false; locked.combat_locked = true
	f = nav.adapt(offense(),locked,[target()],true,true)
	check(f.held.special and f.pressed.special and not f.released.get("special",false),"committed combat is never cancelled")
	check(not f.pressed.get("jump",false),"lock prevents speculative jump edge")
	f = nav.adapt(Frame.new(),own(),[target()],false,true)
	check(f.pressed.get("jump",false),"waited launch resumes after committed lock")
	nav.reset()
	var near := target(); near.position=Vector3(-3,-0.05,0)
	f = nav.adapt(offense(),own(),[near],true,true)
	check(f.held.special and f.pressed.special,"reachable enemy keeps combat")
	if not failures: print("PASS: navigation voluntary offense arbitration preserves committed locks and reachable combat")
	quit(1 if failures else 0)

extends "res://tests/test_core_body_right_pressure.gd"
## The original real-input route/assertions, reversed registration and with
## actor-local hanger hitstop spanning first contact and subsequent pressure.
var pause_hanger := false
var route_hanger := 0
func run():
	registration_order = [2,1]
	for paused in [false,true]:
		pause_hanger = paused
		for parsed in [false,true]:
			for side in [1,-1]:
				route_hanger = 2 if side == 1 else 1
				for release in [false,true]:
					await route(side,release,parsed)
	if not failures: print("PASS: native pressure transaction (%d checks)" % checks)
	quit(1 if failures else 0)
func tick(m, frames := {}) -> void:
	if pause_hanger and m.tick == 242: m.fighters[route_hanger].hitstop_left = 8
	var before: int = m.fighters[route_hanger].actor.runtime.tick
	await super.tick(m,frames)
	check(m.fighter_interaction_mode == "legacy_solid", "pressure exercises native-solid compatibility")
	if pause_hanger and m.tick >= 243 and m.tick <= 250:
		check(m.hitstop_telemetry(route_hanger).stopped_this_tick, "hanger really stopped through pressure")
		check(m.fighters[route_hanger].actor.runtime.tick == before, "pressure does not advance stopped hanger")
	if pause_hanger and m.tick == 251:
		check(not m.hitstop_telemetry(route_hanger).stopped_this_tick, "hanger resumes after contact")
		check(m.fighters[route_hanger].actor.runtime.tick == before + 1, "resumed hanger advances once")

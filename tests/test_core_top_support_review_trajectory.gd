extends "res://tests/test_core_top_support_native.gd"
const Solver = preload("res://scripts/core/collision/fighter_top_support.gd")
func snap(x: float, y: float, vy: float, h := 1.9):
	return {"position":Vector3(x,y,0),"velocity":Vector3(0,vy,0),"eligible":true,"profile":{"height":h,"half_width":0.4,"foot_radius":0.12}}
func run():
	for reverse in [false,true]:
		for descent in [0.0,0.01,0.06]:
			var solver = Solver.new()
			var a = snap(0,3.94,4); var b = snap(0,2,4)
			var ae = snap(0,4.04-descent,4); var be = snap(0,2.1,4,1.98)
			solver.begin({2:b,1:a} if reverse else {1:a,2:b})
			var p = solver.solve({2:be,1:ae} if reverse else {1:ae,2:be},1)
			check(p.has(1) == (descent == 0.06),"acquisition requires physical crossing, not merely descent plus category growth")
	# A genuinely faster rising carrier crosses a still-rising rider.
	var solver = Solver.new()
	solver.begin({1:snap(0,3.94,3),2:snap(0,2,12)})
	var p = solver.solve({1:snap(0,3.99,3),2:snap(0,2.2,12,1.98)},1)
	check(p.has(1),"actual rising-carrier crossing remains eligible")
	# Horizontal footprint must overlap at physical crossing, not the earlier
	# synthetic expanded-plane crossing (t=.2 versus physical t=1).
	solver = Solver.new()
	solver.begin({1:snap(0.8,1.92,-1),2:snap(0,0,0)})
	p = solver.solve({1:snap(0,1.9,-1),2:snap(0,0,0,1.98)},1)
	check(p.has(1),"footprint evaluated at physical crossing time")
	# A shrinking plane must actually be reached, not just its old location.
	solver = Solver.new()
	solver.begin({1:snap(0,2.0,-1),2:snap(0,0,0,1.98)})
	p = solver.solve({1:snap(0,1.95,-1),2:snap(0,0,0,1.9)},1)
	check(not p.has(1),"no capture above shrinking temporal geometry")
	solver = Solver.new()
	solver.begin({1:snap(0.8,2.0,-1),2:snap(0,0,0,1.98)})
	p = solver.solve({1:snap(0,1.88,-1),2:snap(0,0,0,1.9)},1)
	check(p.has(1),"shrinking envelope requires later actual temporal crossing footprint")
	if not failures: print("PASS: physical top-support trajectory regression (%d checks)" % checks)
	quit(1 if failures else 0)

extends "res://tests/test_core_grab_slice.gd"
func run():
	for reverse in [false,true]:
		for release in [false,true]:
			var m = Match.new(); var a = Actor.new(); var b = Actor.new()
			root.add_child(a); root.add_child(b)
			if reverse: m.register_actor(2,b); m.register_actor(1,a)
			else: m.register_actor(1,a); m.register_actor(2,b)
			m.reset({1:Vector3(0,10,0),2:Vector3(1 if release else 0,10,0)})
			if release:
				var f = Frame.new(); f.pressed.special = true
				await step(m,{1:f})
				for i in 11: await step(m)
				check(m.fighters[2].caught_by == 1,"real capture before overlapping release")
				b.position = a.position
				m.cancel_action(1,"overlap release")
			var maximum := 0.0
			for i in 90:
				var ax: float = a.position.x; var bx: float = b.position.x
				await step(m)
				maximum = maxf(maximum,maxf(absf(a.position.x-ax),absf(b.position.x-bx)))
			check(b.position.x-a.position.x >= 0.78,"stable-ID exact overlap separates without input")
			print("OVERLAP_BOUND ",maximum)
			# Native penetration recovery is not limited to requested vx * dt.
			# Characterized maximum is 0.19447; bound it below half a capsule radius.
			check(maximum <= 0.2,"overlap cleanup bounded native recovery, not teleport")
			check(a.position.z == 0 and b.position.z == 0,"no overlap depth escape")
			a.free(); b.free()
	if not failures: print("PASS body overlap (%d checks)" % checks)
	quit(1 if failures else 0)

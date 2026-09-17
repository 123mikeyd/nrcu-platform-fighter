extends "res://tests/test_core_ledge_match.gd"
const OUT = "res://.verification/core/body-contact/"
var rows: Array = []
func run():
	for mover in [1,2]:
		for reverse in [false,true]:
			for direction in [-1,1]:
				var floor_body = body(Vector3(0,-0.5,0),Vector3(40,1,4))
				var m = load("res://scripts/core/match/match_simulation.gd").new()
				for id in ([2,1] if reverse else [1,2]):
					var actor = Actor.new(); actor.profile = load("res://data/characters/teknium_movement.tres")
					root.add_child(actor); m.register_actor(id,actor, -1, "turbofit" if id == mover else "ice_mage")
				var other = 3-mover
				m.reset({mover:Vector3(-3*direction,0.01,0),other:Vector3.ZERO})
				for i in 15: await tick(m)
				var crossed = false
				for i in 75:
					await tick(m,{mover:frame(false,direction)})
					crossed = crossed or (m.fighters[mover].actor.position.x-m.fighters[other].actor.position.x)*direction > 0.05
				check(not crossed,"mixed-kit body blocks both roles/orders/directions")
				rows.append({"scenario":"match_walk","mover":mover,"reverse_registration":reverse,"direction":direction,"crossed":crossed,"damage":m.fighters[other].percent})
				cleanup(m); floor_body.free()
	# Real catch/climb with a second actor occupying the destination.
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var match_instance = setup_ledge()
	await tick(match_instance,{1:frame(false,1)})
	check(match_instance.ledge_telemetry(1).anchor_id == "left","ledge probe actually catches")
	var a = match_instance.fighters[1].actor; var b = match_instance.fighters[2].actor
	b.reset_at(Vector3(0.7,0.06,0))
	var up = Frame.new(); up.axis.y = -1
	await tick(match_instance,{1:up})
	check(a.position.x < 0 and match_instance.ledge_events[1].transition == "blocked", "occupied climb cannot commit")
	rows.append({"scenario":"occupied_ledge_climb","climber":[a.position.x,a.position.y],"blocker":[b.position.x,b.position.y],"distance":a.position.distance_to(b.position),"anchor_released":match_instance.ledge_telemetry(1).anchor_id == ""})
	cleanup(match_instance); terrain.free()
	FileAccess.open(OUT+"match.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	for row in rows: print(JSON.stringify(row))
	if not failures: print("PASS body match 9 cases")
	quit(1 if failures else 0)

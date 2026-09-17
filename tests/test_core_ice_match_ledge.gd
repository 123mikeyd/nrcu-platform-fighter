extends "res://tests/test_core_ledge_match.gd"
func bolt(m, id: String):
	var target = m.fighters[1].actor
	m._commit_kit_intents([{"kind":"spawn_projectile","projectile_kind":"frost_bolt","source":2,"activation_id":id,"position":target.position+Vector3(-.5,1,0),"facing":1.0}])
func run():
	var terrain = body(Vector3(2,-.5,0),Vector3(4,1,4))
	var m = setup_ledge(); m.configure_actor_kit(1,"ice_mage"); m.configure_actor_kit(2,"ice_mage")
	m.fighters[1].actor.runtime.velocity.x = 3
	var special = Frame.new(); special.pressed.special = true
	await tick(m,{1:special})
	check(m.ledge_telemetry(1).anchor_id == "left","Ice catches real shared ledge")
	check(m.kit_telemetry(1).special.move == "","ledge cancels delayed cast episode")
	bolt(m,"protected"); await tick(m)
	check(m.fighters[1].percent == 0 and not m.fighters[1].frozen,"ledge protection consumes freeze contact")
	check(m.projectile_telemetry().is_empty(),"protected ledge bolt consumed")
	m.ledge_state.actors[1].protected_until = m.tick
	bolt(m,"unprotected"); await tick(m)
	check(m.fighters[1].frozen and m.fighters[1].percent == 4,"unprotected ledge hit freezes")
	check(m.ledge_telemetry(1).anchor_id == "","freeze releases ledge relation")
	var y: float = m.fighters[1].actor.position.y
	await tick(m)
	check(m.fighters[1].actor.position.y < y,"freeze falls after releasing ledge writer")
	cleanup(m); terrain.free()
	if not failures: print("PASS: ice match ledge (%d checks)" % checks)
	quit(1 if failures else 0)

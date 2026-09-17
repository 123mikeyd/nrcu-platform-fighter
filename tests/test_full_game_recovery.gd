extends "res://tests/test_full_game_flow.gd"
func run():
	for fighter in ["teknium","turbofit"]:
		for side in [-1,1]:
			var session = load("res://scripts/experimental/full_game_session.gd").new()
			session.input_owner = "human"; session.selected_fighters = [fighter,"teknium"]
			root.add_child(session); await frames(45)
			var actor = session.actors[0]
			var away = KEY_A if side == -1 else KEY_D
			var toward = KEY_D if side == -1 else KEY_A
			key(away,true)
			var offstage := false
			for i in 160:
				await frames(1)
				if actor.position.x*side > 10.0 and actor.position.y < -0.5: offstage = true; break
			key(away,false)
			assert(offstage,"real run off Toy Shelf edge prerequisite")
			var before: float = actor.position.y
			key(toward,true); key(KEY_W,true); key(KEY_G,true)
			await frames(4)
			key(KEY_G,false); key(KEY_W,false)
			assert(actor.runtime.recovery_spent,"real up-special commits recovery resource "+fighter)
			assert(actor.position.y > before,"recovery lifts offstage actor "+fighter)
			var returned := false
			for i in 150:
				await frames(1)
				if actor.runtime.grounded and absf(actor.position.x)<9: returned = true; break
			key(toward,false)
			assert(returned,"recovery returns to actual main support "+fighter)
			assert(session.simulation.fighters[1].stocks == 3)
			print("RECOVERY ",fighter," side=",side," real offstage return PASS")
			session.free(); await frames(2)
	print("PASS: full game both kits both side real offstage recovery")
	quit()

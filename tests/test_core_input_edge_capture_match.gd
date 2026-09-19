extends "res://tests/test_full_game_flow.gd"
var failures := 0
func check(ok, message):
	if not ok:
		failures += 1
		print("FAIL: ", message)
func run():
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	app.input_owner = "human"
	await click("StartMatch")
	await frames(130)
	check(app.state == "match", "post READY prerequisite")
	check(app.session.simulation._next_activation == 0, "unlocked no prior action")
	key(KEY_F,true); key(KEY_F,false)
	await frames(35)
	check(app.session.simulation._next_activation == 1, "between-sample pulse accepted exactly once")
	key(KEY_F,true)
	await frames(35)
	check(app.session.simulation._next_activation == 2, "held control accepted once")
	await frames(35)
	check(app.session.simulation._next_activation == 2, "hold cannot repeat")
	key(KEY_F,false)
	await frames(2)
	key(KEY_F,true); key(KEY_F,false)
	await frames(35)
	check(app.session.simulation._next_activation == 3, "release rearms subsequent pulse")
	app.free()
	await frames(3)
	if failures == 0: print("PASS core input edge capture match")
	quit(failures)

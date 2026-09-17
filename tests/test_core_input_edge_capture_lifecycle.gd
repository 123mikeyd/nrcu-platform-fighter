extends "res://tests/test_full_game_flow.gd"
var failures := 0
var checks := 0
class KeySink extends Control:
	func _gui_input(event):
		if event is InputEventKey: accept_event()
func check(ok, message):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func pulse(code):
	key(code,true); key(code,false)
func run():
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	app.input_owner = "human"
	await click("StartMatch")
	check(app.state == "ready", "READY prerequisite")
	pulse(KEY_F); key(KEY_G,true)
	await frames(110)
	var m = app.session.simulation
	check(m._next_activation == 0,"READY pulse and held special suppressed after start")
	key(KEY_G,false)
	await frames(3)
	# Different actions preserve the direction at each press, not final polling axis.
	key(KEY_A,true); pulse(KEY_F); key(KEY_A,false); key(KEY_D,true)
	await frames(2)
	check(m.fighters[1].facing == -1 and m._next_activation == 1,"match consumes press-time aim despite opposite movement at sample")
	key(KEY_D,false)
	pulse(KEY_F)
	await frames(2)
	check(not m.fighters[1].buffer.peek("attack").is_empty(),"second pulse captured while kit locked")
	await frames(40)
	check(m._next_activation == 1 and m.fighters[1].buffer.peek("attack").is_empty(),"locked pulse expires at unchanged buffer window, not replayed on unlock")
	pulse(KEY_K)
	await frames(2)
	check(m._next_activation == 2 and not m.fighters[2].activation_id.is_empty(),"human P2 has independent event routing")
	await frames(70)
	var start = m._next_activation
	# A GUI-consumed down must not leak through live held polling either.
	var sink := KeySink.new(); sink.focus_mode = Control.FOCUS_ALL
	app.add_child(sink); sink.grab_focus()
	key(KEY_F,true); key(KEY_D,true)
	await frames(3)
	check(app.session.sources[0].sample(m.tick).axis.x == 0,"GUI consumed direction cannot move through polling")
	key(KEY_F,false); key(KEY_D,false)
	await frames(3)
	check(m._next_activation == start,"GUI consumed key cannot attack through polling")
	sink.release_focus(); sink.free()
	# A release consumed by GUI still clears a previously accepted hold.
	key(KEY_F,true)
	await frames(2)
	var sink2 := KeySink.new(); sink2.focus_mode = Control.FOCUS_ALL
	app.add_child(sink2); sink2.grab_focus()
	key(KEY_F,false)
	await frames(2)
	check(not app.session.sources[0].sample(m.tick).held.get("attack",false),"GUI-consumed release cannot stick an accepted hold")
	sink2.release_focus(); sink2.free()
	await frames(40)
	start = m._next_activation
	pulse(KEY_F)
	app.pause_match()
	pulse(KEY_F); key(KEY_G,true)
	await frames(3)
	app.resume_match()
	await frames(40)
	check(m._next_activation == start,"pause clears pending pulse and resume suppresses held special")
	key(KEY_G,false)
	app._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.state == "paused","focus loss pauses owner")
	pulse(KEY_F)
	app.resume_match(); await frames(8)
	check(m._next_activation == start,"focus loss pulse cannot ghost after resume")
	# Sampling continues during hitstop, while buffer ages and actor clocks freeze.
	m.fighters[1].hitstop_left = 5
	var actor_tick = app.session.actors[0].runtime.tick
	pulse(KEY_F)
	await frames(3)
	var pending: Dictionary = m.fighters[1].buffer.peek("attack")
	check(not pending.is_empty() and pending.get("age",-1) == 0,"hitstop samples pulse and freezes its buffer age")
	check(app.session.actors[0].runtime.tick == actor_tick and m._next_activation == start,"hitstop does not advance actor or accept attack")
	await frames(40)
	check(m._next_activation == start+1,"hitstop pulse accepted once after thaw")
	pulse(KEY_F)
	app.rematch()
	pulse(KEY_F); key(KEY_F,true)
	await frames(115)
	check(m._next_activation == 0,"rematch plus READY clears queued and held actions")
	key(KEY_F,false); pulse(KEY_F)
	await frames(35)
	check(m._next_activation == 1,"release and fresh pulse after rematch works")
	var source = app.session.sources[0]
	app.show_select()
	check(not Input.joy_connection_changed.is_connected(source._on_joy_connection_changed),"session detach shuts down source hotplug callback")
	app.input_owner = "sparring_easy"
	await click("StartMatch")
	await frames(110)
	pulse(KEY_K); pulse(KEY_L); pulse(KEY_ENTER)
	Input.flush_buffered_events()
	var ignored = app.session.sources[1].sample(app.session.simulation.tick)
	check(ignored.pressed.is_empty() and not ignored.held.get("attack",false),"AI-owned P2 ignores human events")
	app.show_select(); app.input_owner = "human"
	await click("StartMatch")
	await frames(110)
	pulse(KEY_K); pulse(KEY_L); pulse(KEY_ENTER)
	Input.flush_buffered_events()
	var accepted = app.session.sources[1].sample(app.session.simulation.tick)
	check(accepted.pressed.get("attack",false) and accepted.pressed.get("special",false) and accepted.pressed.get("jump",false),"same dispatched pulses reach human P2 control")
	app.free(); await frames(3)
	if failures == 0: print("PASS core input edge capture lifecycle (%d checks)" % checks)
	quit(failures)

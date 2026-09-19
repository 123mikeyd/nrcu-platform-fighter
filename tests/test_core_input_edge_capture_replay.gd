extends "res://tests/test_full_game_flow.gd"
const Recording = preload("res://scripts/core/input/recorded_input_source.gd")
var failures := 0
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	session.input_owner = "human"
	root.add_child(session)
	session.set_physics_process(false)
	var recordings = [Recording.new(),Recording.new()]
	var traces := []
	for playback in 2:
		session.rematch()
		var trace := []
		for t in 140:
			await physics_frame
			if playback == 0:
				if t == 20:
					key(KEY_A,true); key(KEY_F,true); key(KEY_F,false); key(KEY_A,false)
				if t == 25:
					key(KEY_F,true); key(KEY_F,false) # Locked: expires, not replayed later.
				if t == 60:
					key(KEY_D,true); key(KEY_SPACE,true); key(KEY_SPACE,false)
				if t == 78: key(KEY_D,false)
				if t == 90:
					key(KEY_K,true); key(KEY_K,false)
				Input.flush_buffered_events()
			var input_frames := {}
			for slot in 2:
				var frame = session.sources[slot].sample(session.simulation.tick) if playback == 0 else recordings[slot].sample(session.simulation.tick)
				if playback == 0: recordings[slot].record(frame)
				input_frames[slot+1] = frame
			session.simulation.simulate(input_frames)
			var row := [session.simulation._next_activation]
			for id in [1,2]:
				var f: Dictionary = session.simulation.fighters[id]
				row.append([f.actor.position,f.actor.velocity,f.actor.runtime.tick,f.facing,f.move_id,f.percent,f.actor.runtime.states.action,f.actor.runtime.states.locomotion])
			trace.append(row)
		traces.append(trace)
	if traces[0] != traces[1]:
		failures += 1; print("FAIL: captured events replay identically through Match/buffer/native actors after reset")
	if recordings[0].frames[20].get("pressed_axis",{}).get("attack",[]) != [-1.0,0.0]:
		failures += 1; print("FAIL: recording contains source-captured left pulse")
	if traces[0][21][0] != 1 or traces[0][55][0] != 1:
		failures += 1; print("FAIL: replay fixture proves immediate acceptance and locked pulse expiry")
	if traces[0][70][1][0].y <= traces[0][59][1][0].y:
		failures += 1; print("FAIL: short jump pulse reaches real actor jump")
	session.free(); await frames(3)
	if failures == 0: print("PASS core input edge capture replay (4 checks, 140 ticks twice)")
	quit(failures)

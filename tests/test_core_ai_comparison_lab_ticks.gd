extends SceneTree
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; print("FAIL: ",message)
func _init(): call_deferred("run")
func send(code: Key, down: bool):
	var e = InputEventKey.new(); e.physical_keycode = code; e.keycode = code; e.pressed = down
	Input.parse_input_event(e); Input.flush_buffered_events()
func run():
	var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab)
	lab.set_physics_process(false); lab.set_p2_repo_ai(true)
	for i in 90: await physics_frame; lab._physics_process(1.0/60)
	check(lab.repo_inputs.ai.sequence > 0, "sole lab physics owner samples actual repo AI")
	var tick = lab.simulation.tick; var seq = lab.repo_inputs.ai.sequence
	lab.set_paused(true)
	for i in 4: await physics_frame; lab._physics_process(1.0/60)
	check(lab.simulation.tick == tick and lab.repo_inputs.ai.sequence == seq, "pause freezes AI and match")
	lab.step_once(); await physics_frame; lab._physics_process(1.0/60); lab._physics_process(1.0/60)
	check(lab.simulation.tick == tick + 1, "F2 commits exactly one tick")
	lab.set_paused(false); lab.reset_lab()
	await physics_frame
	send(KEY_K,true); send(KEY_ENTER,true); send(KEY_RIGHT,true)
	lab._physics_process(1.0/60)
	check(not lab.sources[1]._previous.get("attack",false), "AI ownership does not sample human P2 keyboard")
	send(KEY_K,false); send(KEY_ENTER,false); send(KEY_RIGHT,false)
	lab.set_p2_repo_ai(false)
	await physics_frame; send(KEY_F,true); lab._physics_process(1.0/60)
	send(KEY_F3,true); send(KEY_F3,false)
	check(lab.repo_inputs.ai.sequence == 0, "F3 resets repo sequence")
	for i in 5: await physics_frame; lab._physics_process(1.0/60)
	check(lab.simulation.fighters[1].move_id == "" and lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "F3 suppresses held human attack and queued edges")
	send(KEY_F,false)
	lab.free()
	if not failures: print("PASS: AI lab sole clock pause step reset and input ownership")
	quit(1 if failures else 0)

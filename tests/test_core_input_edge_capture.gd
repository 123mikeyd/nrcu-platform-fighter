extends SceneTree
const Source = preload("res://scripts/core/input/player_input_source.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
const Buffer = preload("res://scripts/core/input/input_buffer.gd")
const Recording = preload("res://scripts/core/input/recorded_input_source.gd")
var failures := 0
var checks := 0
func check(ok, message):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func key(source, code, down, echo_event = false):
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down; event.echo = echo_event
	source.feed_event(event)
func pad(source, device_id, button, down):
	var event := InputEventJoypadButton.new()
	event.device = device_id; event.button_index = button; event.pressed = down
	source.feed_event(event)
func axis(source, device_id, which, value):
	var event := InputEventJoypadMotion.new()
	event.device = device_id; event.axis = which; event.axis_value = value
	source.feed_event(event)
func sample(source, tick, stick = Vector2.ZERO):
	return source.sample_snapshot(tick, {}, {}, stick, true, true)
class EventOwner extends Node:
	var source
	func _unhandled_input(event): source.feed_event(event)
func native_key(code, down):
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func native_rebinding():
	var source = Source.new()
	source.enable_event_capture()
	var owner := EventOwner.new(); owner.source = source; root.add_child(owner)
	source.sample(0)
	# No intervening sample: native Input is already updated when the down arrives.
	source.bindings.attack = KEY_Z
	native_key(KEY_Z,true)
	var frame = source.sample(1)
	check(Input.is_physical_key_pressed(KEY_Z) and frame.pressed.get("attack",false) and frame.held.get("attack",false),"first native down after warmed in-place rebind accepted")
	check(source.sample(2).pressed.is_empty(),"new native binding drains once")
	native_key(KEY_Z,false); native_key(KEY_Z,true)
	check(source.sample(3).pressed.get("attack",false),"matched release/repress control accepted")
	native_key(KEY_Z,false)
	# An unbound key already held before rebinding must not become a fresh action.
	native_key(KEY_X,true)
	source.bindings.attack = KEY_X
	native_key(KEY_X,true)
	frame = source.sample(4)
	check(frame.pressed.is_empty() and not frame.held.get("attack",false),"genuinely preheld new binding suppressed even on duplicate down")
	native_key(KEY_X,false); native_key(KEY_X,true)
	check(source.sample(5).pressed.get("attack",false),"held-at-rebind release rearms native action")
	native_key(KEY_X,false)
	# Clear the captured old identity, but process the current event under the new one.
	native_key(KEY_X,true); native_key(KEY_X,false)
	source.bindings.attack = KEY_Z
	source.bindings.up = KEY_Z
	source.tap_jump = true
	native_key(KEY_Z,true)
	frame = source.sample(6)
	check(frame.pressed.get("attack",false) and frame.pressed.get("jump",false) and frame.pressed_axis.get("attack") == Vector2.UP,"identity transition processes current event direction and aliases")
	native_key(KEY_Z,false)
	check(source.sample(7).pressed.is_empty(),"old pending identity cannot replay after fresh press")
	native_key(KEY_Z,true); native_key(KEY_Z,false)
	source.bindings.attack = KEY_C
	check(source.sample(8).pressed.is_empty(),"rebind after capture clears old pending before sampling")
	native_key(KEY_C,true); native_key(KEY_C,false)
	check(source.sample(9).pressed.get("attack",false),"new native pulse works after sampling detects rebind")
	native_key(KEY_C,true)
	source.bindings.attack = KEY_V
	native_key(KEY_V,true)
	frame = source.sample(10)
	check(frame.pressed.get("attack",false) and frame.held.get("attack",false),"fresh binding accepted while old bound button remains held")
	native_key(KEY_C,false)
	check(source.sample(11).held.get("attack",false),"old button release cannot clear new held binding")
	native_key(KEY_V,false)
	frame = source.sample(12)
	check(not frame.held.get("attack",false) and frame.released.get("attack",false) and frame.pressed.is_empty(),"new binding release clears held without sticky old button")
	native_key(KEY_B,true)
	source.reset()
	source.sample(13)
	source.bindings.attack = KEY_B
	native_key(KEY_B,true)
	check(source.sample(14).pressed.is_empty(),"lifecycle reset retains knowledge of already-held unbound key")
	native_key(KEY_B,false); native_key(KEY_B,true)
	check(source.sample(15).pressed.get("attack",false),"unbound held across reset rearms only after release")
	native_key(KEY_B,false)
	source.shutdown(); owner.free()
func _initialize(): call_deferred("run")
func run():
	native_rebinding()
	var actions_before := InputMap.get_actions()
	var source = Source.new()
	source.enable_event_capture()
	key(source,KEY_A,true); key(source,KEY_F,true); key(source,KEY_F,false)
	key(source,KEY_A,false); key(source,KEY_D,true); key(source,KEY_G,true); key(source,KEY_G,false)
	var frame = sample(source,1)
	check(frame.pressed.get("attack",false) and frame.released.get("attack",false) and not frame.held.attack,"short pulse retains both edges, not held")
	check(frame.pressed_axis.attack == Vector2.LEFT and frame.pressed_axis.special == Vector2.RIGHT,"each action retains its press-time direction")
	check(frame.axis == Vector2.ZERO,"movement snapshot is not replaced with press-time aim")
	var buffer = Buffer.new()
	buffer.advance(frame)
	check(buffer.consume("attack").axis == Vector2.LEFT and buffer.consume("special").axis == Vector2.RIGHT,"buffer retains per-action context")
	buffer.advance(frame)
	check(buffer.debug_pending().is_empty(),"same sampled frame cannot replay consumed requests")
	check(sample(source,2).pressed.is_empty(),"interval drained exactly once")
	for i in 100:
		key(source,KEY_F,true); key(source,KEY_F,false)
	frame = sample(source,3)
	buffer.advance(frame)
	check(buffer.debug_pending().size() == 1,"hundred pulses coalesce to one action per sample")
	check(sample(source,4).pressed.is_empty(),"coalesced pulses never replay later")
	key(source,KEY_F,true)
	frame = sample(source,5)
	check(frame.pressed.attack and frame.held.attack,"held press accepted")
	key(source,KEY_F,true,true); key(source,KEY_F,true)
	check(sample(source,6).pressed.is_empty(),"echo and repeated down do not retrigger")
	key(source,KEY_F,false); key(source,KEY_F,true); key(source,KEY_F,false)
	check(sample(source,7).pressed.attack,"release rearms next pulse")
	key(source,KEY_F,true); key(source,KEY_F,false); source.reset()
	check(sample(source,8).pressed.is_empty(),"reset discards unsampled pulse")
	key(source,KEY_F,true); key(source,KEY_F,false); source.bindings.attack = KEY_Z
	check(sample(source,9).pressed.is_empty(),"in-place rebind invalidates old queued identity")
	key(source,KEY_F,true); key(source,KEY_F,false)
	check(sample(source,10).pressed.is_empty(),"old binding no longer captures")
	key(source,KEY_Z,true); key(source,KEY_Z,false)
	check(sample(source,11).pressed.attack,"new binding captures")
	var p2 = Source.new(); p2.slot = 1; p2.enable_event_capture()
	for target in [source,p2]:
		key(target,KEY_K,true); key(target,KEY_K,false)
	check(sample(source,12).pressed.is_empty() and sample(p2,12).pressed.attack,"two keyboards isolate physical identities")
	source.device = 7
	axis(source,7,JOY_AXIS_LEFT_X,0.63)
	pad(source,8,JOY_BUTTON_X,true); pad(source,8,JOY_BUTTON_X,false)
	check(sample(source,13).pressed.is_empty(),"wrong gamepad ignored")
	pad(source,7,JOY_BUTTON_X,true); pad(source,7,JOY_BUTTON_X,false)
	axis(source,7,JOY_AXIS_LEFT_X,-0.7)
	frame = sample(source,14,Vector2(-0.7,0.1))
	check(frame.source_id == "pad:7" and frame.pressed.attack,"synthetic assigned pad pulse captured")
	check(is_equal_approx(frame.axis.x,-0.7) and frame.axis.y == 0 and is_equal_approx(frame.pressed_axis.attack.x,0.63),"analog movement preserved separately from press aim")
	# Synthetic pad binding mutation follows the same prior-state contract.
	pad(source,7,JOY_BUTTON_X,true); pad(source,7,JOY_BUTTON_X,false)
	source.pad_bindings.attack = JOY_BUTTON_Y
	pad(source,7,JOY_BUTTON_Y,true)
	var rebound = sample(source,140,Vector2(-0.7,0))
	check(rebound.pressed.get("attack",false) and rebound.held.get("attack",false) and is_equal_approx(rebound.pressed_axis.attack.x,-0.7),"synthetic pad rebind clears old pending and accepts first new down with aim")
	check(sample(source,141).pressed.is_empty(),"synthetic new button drains once")
	pad(source,7,JOY_BUTTON_Y,false)
	pad(source,7,JOY_BUTTON_RIGHT_SHOULDER,true)
	source.pad_bindings.attack = JOY_BUTTON_RIGHT_SHOULDER
	pad(source,7,JOY_BUTTON_RIGHT_SHOULDER,true)
	check(sample(source,142).pressed.is_empty(),"synthetic preheld unbound button remains suppressed at rebind")
	pad(source,7,JOY_BUTTON_RIGHT_SHOULDER,false); pad(source,7,JOY_BUTTON_RIGHT_SHOULDER,true)
	check(sample(source,143).pressed.get("attack",false),"synthetic held rebind release/repress rearms")
	pad(source,7,JOY_BUTTON_RIGHT_SHOULDER,false)
	source.pad_bindings.attack = JOY_BUTTON_X
	check(sample(source,144).pressed.is_empty(),"pad rebind detected by sample clears pending")
	pad(source,7,JOY_BUTTON_X,true); pad(source,7,JOY_BUTTON_X,false)
	check(sample(source,145).pressed.get("attack",false),"pad new down after sample rebind accepted")
	var recording = Recording.new()
	recording.record(frame)
	frame.pressed_axis.attack = Vector2.UP
	var replay = recording.sample(42)
	check(is_equal_approx(replay.pressed_axis.attack.x,0.63) and replay.tick == 42,"recorded event aim detached and reticked")
	var file := "user://test_edge_capture_recording.json"
	check(recording.save_recording(file) == OK,"save event-bearing recording")
	var restored = Recording.new()
	check(restored.load_recording(file) == OK and restored.sample(14).to_dict() == recording.frames[0],"event-bearing recording disk roundtrip")
	DirAccess.remove_absolute(file)
	pad(source,7,JOY_BUTTON_X,true); pad(source,7,JOY_BUTTON_X,false)
	Input.joy_connection_changed.emit(7,false)
	frame = source.sample_snapshot(15,{}, {},Vector2.ZERO,false,true)
	check(frame.pressed.is_empty() and frame.axis == Vector2.ZERO,"disconnect flushes captured edges")
	Input.joy_connection_changed.emit(7,true)
	check(sample(source,16).pressed.is_empty(),"reconnect does not replay old pulse")
	# Deterministic snapshot API remains polling-only even for an event owner.
	source.sample_snapshot(17)
	check(source.sample_snapshot(18,{}, {JOY_BUTTON_A:true}).pressed.jump,"legacy snapshot API unchanged")
	check(not Recording._valid_frame({"tick":1,"axis":[0,0],"source_id":"pad:7","held":{},"pressed":{},"released":{},"pressed_axis":{"attack":["bad",0]}}),"malformed optional recorded aim rejected")
	source.shutdown(); p2.shutdown()
	check(not Input.joy_connection_changed.is_connected(source._on_joy_connection_changed),"shutdown disconnects global hotplug callback")
	key(p2,KEY_K,true); key(p2,KEY_K,false)
	check(sample(p2,19).pressed.is_empty(),"shutdown refuses event feed")
	check(InputMap.get_actions() == actions_before,"no global InputMap actions added or removed")
	if failures == 0: print("PASS core input edge capture (%d checks)" % checks)
	quit(failures)

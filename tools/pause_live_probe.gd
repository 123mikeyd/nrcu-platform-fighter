extends Node
# pause_live_probe (dev tool for the WP-1 pointer contract, NOT a suite runner).
#
# Runs the REAL production route in a REAL window and then observes genuine
# window-delivered pointer input (injected by tools/pause_live_probe.py through
# PostMessage -> the engine's Windows event loop), so the physical-pointer path
# of the Pause surface can be judged live:
#   * the engine's own hovered control and Input.get_mouse_position()
#   * the hand cursor's hover target / hotspot / modality
#   * the effect of a real left-click on each Pause item
#
# Prints machine-readable lines for the driver. Re-opens Pause once so both
# items can be clicked, then quits.
#
#   godot --path <repo> --resolution 1280x720 --quit-after 5400 \
#       res://tools/pause_live_probe.tscn

const VsRoute = preload("res://tests/fixtures/vs_route.gd")

const PHASE_FRAMES := 1200

func _ready() -> void:
	call_deferred("run")

func settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame

func key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event

func emit_esc() -> void:
	Input.parse_input_event(key_event(KEY_ESCAPE))
	Input.flush_buffered_events()

func hand():
	var cursor := get_tree().root.get_node_or_null("Cursor")
	return cursor.hand if cursor != null else null

func describe(pause: Control, h) -> String:
	var vp := get_tree().root
	var hovered: Control = vp.gui_get_hovered_control() if vp.has_method("gui_get_hovered_control") else null
	var hand_hover := str(h.hovered.name) if (h != null and h.hovered != null) else "<none>"
	return "state=%s engine_hovered=%s hand_hover=%s hand_mode=%s hotspot=%s mouse=%s" % [
		pause.state(),
		str(hovered.name) if hovered != null else "<none>",
		hand_hover, str(h.mode) if h != null else "?",
		str(h.hotspot.round()) if h != null else "?",
		str(get_viewport().get_mouse_position().round())]

func watch(label: String, pause: Control, arena: Node, h, frames: int) -> bool:
	# Returns true when the pause state changed (an action fired).
	var last := ""
	for _i in frames:
		await get_tree().process_frame
		if not is_instance_valid(pause):
			print("PROBE: %s_ACTION_FIRED=leaving(freed)" % label)
			return true
		var line := describe(pause, h)
		if line != last:
			last = line
			print("PROBE: %s_SEE=%s" % [label, line])
		if pause.state() != "open":
			print("PROBE: %s_ACTION_FIRED=%s" % [label, pause.state()])
			return true
	return false

func run() -> void:
	var vs = VsRoute.new()
	var host: Node = await vs.enter(get_tree())
	var arena: Node = await vs.launch(get_tree(), host, ["ggb", "ggb", "", ""], "sky")
	if arena == null:
		print("PROBE: FAILED no arena")
		get_tree().quit(1)
		return
	await settle(12)
	var pause: Control = arena.pause_overlay()
	emit_esc()
	await settle(6)
	print("PROBE: pause_state=%s paused=%s" % [pause.state(), str(get_tree().paused)])
	if not pause.is_open():
		print("PROBE: FAILED pause did not open")
		get_tree().quit(1)
		return
	var resume: Control = pause.action_resume()
	var leave: Control = pause.action_leave()
	var r_center := resume.get_global_rect().get_center()
	var l_center := leave.get_global_rect().get_center()
	print("PROBE: RESUME_CENTER=%.1f,%.1f LEAVE_CENTER=%.1f,%.1f" % [r_center.x, r_center.y, l_center.x, l_center.y])
	var h = hand()
	print("PROBE: PHASE_A_READY (pointer phase: hover both items, then click RESUME)")
	var a_fired := await watch("A", pause, arena, h, PHASE_FRAMES)
	await settle(20)
	print("PROBE: A_FIRED=%s" % str(a_fired))
	# Re-open so the second item can be exercised with the same real-pointer path.
	if is_instance_valid(pause) and not pause.is_open():
		emit_esc()
		await settle(10)
		print("PROBE: REOPENED state=%s RESUME_CENTER=%.1f,%.1f LEAVE_CENTER=%.1f,%.1f" % [
			pause.state(), r_center.x, r_center.y, l_center.x, l_center.y])
		print("PROBE: PHASE_B_READY (pointer phase: hover + click LEAVE)")
		var b_fired := await watch("B", pause, arena, h, PHASE_FRAMES)
		print("PROBE: B_FIRED=%s" % str(b_fired))
	else:
		print("PROBE: SKIP_REOPEN state=%s" % (pause.state() if is_instance_valid(pause) else "gone"))
	print("PROBE: DONE")
	get_tree().quit(0)

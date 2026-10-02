extends SceneTree
# v0.6 MobileTouch contract against the live main router (desktop emulation of touch
# events in headless Godot; this is NOT physical-phone evidence).
var arena
var pad
var failures: Array = []
var checks := 0

func _initialize() -> void:
	call_deferred("run_test")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		print("FAIL ", description)

func frames(n: int) -> void:
	for i in n: await physics_frame

func touch(index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	Input.parse_input_event(e)

func run_test() -> void:
	pad = root.get_node_or_null("MobileTouch")
	check(pad != null, "MobileTouch autoload present")
	if pad == null:
		_finish()
		return
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")
	await frames(4)
	arena = current_scene
	var slots: Array = arena.Config.default_slots()
	slots[0].character = "teknium"; slots[0].kind = "human"
	slots[1].character = "doge_man"; slots[1].kind = "human"; slots[1].device = -1
	slots[2].kind = "empty"; slots[3].kind = "empty"
	check(arena.start_match(slots, false), "freeplay starts")
	await frames(140)
	check(arena.match_active(), "match active after READY/GO")
	pad.touch_mode = true
	await frames(2)
	check(pad.gameplay_enabled, "touch gameplay enabled in a live landscape match")
	var view: Vector2 = root.get_visible_rect().size
	var zones: Dictionary = pad.regions(view)
	touch(0, zones.attack, true); await frames(2)
	check(pad.controls().attack, "attack zone press reaches controls()")
	var held: Dictionary = arena.player_one.read_controls(0)
	check(held.attack, "P1 read_controls merges the touch attack")
	touch(0, zones.attack, false); await frames(2)
	check(not pad.controls().attack, "release clears attack")
	# Pause button -> production pause_match()
	touch(1, Vector2(view.x - 90, 45), true); await frames(2)
	check(paused and arena.pause_menu.visible, "touch Pause button opens the Pause menu")
	check(not pad.gameplay_enabled, "touch controls off while paused")
	touch(1, Vector2(view.x - 90, 45), false)
	# Rotate-pause must not resume the player's own pause.
	root.size = Vector2i(720, 1280); await frames(3)
	root.size = Vector2i(1280, 720); await frames(3)
	check(paused and arena.pause_menu.visible and not pad.rotate_pause_owned, "rotate does not resume a player Pause menu")
	arena.resume_match(); await frames(3)
	check(not paused and pad.gameplay_enabled, "resume restores touch gameplay")
	# Portrait during a live fight: owned rotate pause, released on landscape.
	root.size = Vector2i(720, 1280); await frames(3)
	check(paused and pad.rotate_pause_owned and not pad.gameplay_enabled, "portrait pauses a live match (owned rotate pause)")
	root.size = Vector2i(1280, 720); await frames(3)
	check(not paused and not pad.rotate_pause_owned and pad.gameplay_enabled, "landscape releases only the rotate pause")
	# Menus: no gameplay touch on setup.
	arena.show_setup(); await frames(3)
	check(not pad.gameplay_enabled, "touch gameplay off on match setup")
	pad.touch_mode = false
	_finish()

func _finish() -> void:
	print("V06_MOBILE checks=", checks, " failures=", failures.size(), "; desktop touch emulation only")
	if failures.is_empty(): print("V06_MOBILE_COMPLETE")
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Dev Mode + pause menu contract (real frames, real main scene).
var failures := 0
var passes := 0
const CFG := "user://nrcu_settings.cfg"
func check(ok: bool, label: String) -> void:
	if ok: passes += 1
	else:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void: call_deferred("run")
func frames(n: int) -> void:
	for i in n: await physics_frame
func esc(arena) -> void:
	var e := InputEventKey.new(); e.keycode = KEY_ESCAPE; e.pressed = true
	arena._unhandled_key_input(e)
func fkey(arena, code) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.pressed = true
	arena.dev_overlay._unhandled_key_input(e)
func run() -> void:
	var backup := FileAccess.get_file_as_string(CFG) if FileAccess.file_exists(CFG) else ""
	var dev = root.get_node("DevMode")
	dev.set_enabled(false)
	root.size = Vector2i(1280, 720)
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await frames(3)
	# Esc on the setup screen keeps its old behaviour (no pause).
	check(arena.setup.visible and not arena.match_active(), "setup visible at launch, no active match")
	var slots = load("res://scripts/match_config.gd").default_slots()
	slots[0].character = "teknium"
	slots[1].kind = "human"; slots[1].character = "doge_man"
	slots[2].kind = "empty"; slots[3].kind = "empty"
	check(arena.start_match(slots, false), "freeplay starts")
	await frames(110)
	check(arena.match_active() and arena.player_one.controls_enabled, "fight live after READY/GO")
	# ---- pause / resume
	esc(arena)
	check(paused and arena.pause_menu.visible, "Esc pauses mid-match and opens menu")
	var f0: int = dev.frame
	var pos: Vector3 = arena.player_one.global_position
	await frames(10)
	check(dev.frame == f0 and arena.player_one.global_position == pos, "game frozen under pause menu")
	esc(arena)
	check(not paused and not arena.pause_menu.visible, "Esc again resumes")
	await frames(3)
	check(dev.frame > f0, "frames advance after resume")
	# ---- resume must not turn the Space used on the menu into a jump
	await frames(20)
	esc(arena)
	var space := InputEventKey.new(); space.keycode = KEY_SPACE; space.physical_keycode = KEY_SPACE; space.pressed = true
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	await process_frame
	check(Input.is_key_pressed(KEY_SPACE), "harness: Space really held while menu open")
	arena.pause_menu.resume_requested.emit()
	var y0: float = arena.player_one.global_position.y
	await frames(8)
	check(arena.player_one.global_position.y <= y0 + 0.01, "held Space from menu does not jump on resume")
	space.pressed = false; Input.parse_input_event(space)
	await frames(2)
	# ---- Options → Dev Mode
	esc(arena)
	arena.pause_menu.open_options()
	check(arena.pause_menu.options_box.visible and not arena.pause_menu.layer_box.visible, "Options open, layers hidden while Dev Mode off")
	arena.pause_menu.dev_toggle.button_pressed = true
	check(dev.enabled and arena.pause_menu.dev_toggle.button_pressed and arena.pause_menu.layer_box.visible and arena.dev_overlay.visible, "Dev Mode toggle turns overlay on and shows ON")
	var saved := ConfigFile.new(); saved.load(CFG)
	check(saved.get_value("dev", "enabled", false) == true, "Dev Mode setting saved")
	esc(arena)
	check(paused and arena.pause_menu.main_box.visible, "Esc in Options returns to pause list")
	esc(arena)
	check(not paused, "resume with Dev Mode on")
	await frames(4)
	await process_frame
	# ---- drawing
	var m: ImmediateMesh = arena.dev_overlay.mesh
	var verts := 0
	if m.get_surface_count() > 0: verts = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check(verts > 400, "hurtbox/movement wireframes drawn (%d verts)" % verts)
	var labels: Dictionary = arena.dev_overlay.state_labels
	check(labels.size() == 2, "state label per fighter")
	for f in labels: check("·" in labels[f].text and "%" in labels[f].text, "state label text: " + labels[f].text.replace("\n", " | "))
	check("DEV MODE" in arena.dev_overlay.top_label.text, "top banner")
	# ---- hit log (measured from real damage change)
	arena.player_two.receive_hit_from(8.0, Vector3.RIGHT, 3.8, arena.player_one)
	await frames(2)
	var log: Array = arena.dev_overlay.hit_log
	check(not log.is_empty() and "P1 TEKNIUM → P2 DOGE MAN" in log[0] and "8.0%" in log[0], "hit logged with attacker/victim/damage: " + (log[0] if not log.is_empty() else "none"))
	check(arena.dev_overlay.markers.size() == 1, "hit marker placed")
	# ---- freeze / frame step / speed
	fkey(arena, KEY_F2)
	check(paused and dev.frozen, "F2 freezes")
	var fz: int = dev.frame
	await frames(6)
	check(dev.frame == fz, "frozen stays frozen")
	fkey(arena, KEY_F3)
	await frames(6)
	check(dev.frame == fz + 1 and paused, "F3 steps exactly one frame (%d→%d)" % [fz, dev.frame])
	fkey(arena, KEY_F3)
	await frames(6)
	check(dev.frame == fz + 2, "second F3 steps one more")
	esc(arena)
	check(arena.pause_menu.visible, "Esc opens pause menu while frozen")
	esc(arena)
	check(paused and not arena.pause_menu.visible, "closing menu keeps training freeze")
	fkey(arena, KEY_F2)
	await frames(3)
	check(not paused and dev.frame > fz + 2, "F2 unfreezes")
	fkey(arena, KEY_F5); check(is_equal_approx(Engine.time_scale, 0.5), "F5 → 50%")
	fkey(arena, KEY_F5); check(is_equal_approx(Engine.time_scale, 0.25), "F5 → 25%")
	fkey(arena, KEY_F5); check(is_equal_approx(Engine.time_scale, 1.0), "F5 → 100%")
	# ---- reported hitbox hook (v2)
	dev.report_hitbox(arena.player_one, arena.player_one.global_position + Vector3.UP, 0.3, "active", null, 5)
	check(dev.hitboxes.size() == 1, "report_hitbox registers while Dev Mode shows hitboxes")
	await frames(8)
	check(dev.hitboxes.is_empty(), "reported hitbox expires")
	# ---- leaving the match clears pause state
	esc(arena)
	arena.pause_menu.setup_requested.emit()
	check(arena.setup.visible and not paused and not arena.pause_menu.visible, "Match Setup from pause unpauses and shows setup")
	esc(arena)
	check(not paused and not arena.pause_menu.visible, "Esc on setup never opens pause")
	# ---- off switch
	dev.set_enabled(false)
	check(not arena.dev_overlay.visible and is_equal_approx(Engine.time_scale, 1.0), "Dev Mode off hides overlay")
	dev.frozen = true; fkey(arena, KEY_F2)
	dev.frozen = false
	check(not paused, "training keys inert when Dev Mode off")
	# restore Mike's real settings file
	if backup == "": DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE); f.store_string(backup); f.close()
	print("DEV_MODE_TEST passes=%d failures=%d" % [passes, failures])
	print("DEV_MODE_TEST_COMPLETE")
	arena.queue_free()
	quit(1 if failures else 0)

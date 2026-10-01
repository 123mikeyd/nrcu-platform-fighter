extends SceneTree
# Manual review entry only. No timer, timeout, autoquit, or preview-owned game lifetime.
const Setup = preload("res://tools/fx_review_setup.gd")
const Adapter = preload("res://scripts/vs_presentation_adapter.gd")
var adapter
var shell
var hint: Label
var neutral := false
var mode: String
var scenario: String
var review_dir: String
var phase_times: Array = [0.29, 0.45, 0.81, 1.11]
var peak_time := 0.81

func _init() -> void:
	call_deferred("start_review")

func start_review() -> void:
	mode = OS.get_environment("NRCU_FX_REVIEW_MODE")
	scenario = OS.get_environment("NRCU_FX_REVIEW_SCENARIO")
	review_dir = OS.get_environment("NRCU_FX_REVIEW_DIR")
	var data := OS.get_environment("NRCU_FX_DATA_DIR")
	var drafts := OS.get_environment("NRCU_FX_DRAFT_DIR")
	if review_dir == "" or data == "" or drafts == "" or OS.get_environment("NRCU_FX_WORKSPACE_PATH") == "":
		push_error("Use tools/fx_review.py: isolated review paths are required")
		quit(2)
		return
	var seeded: Dictionary = Setup.seed(scenario, data, drafts)
	if not seeded.get("ok", false):
		push_error("Review setup failed: " + str(seeded.get("errors", [])))
		quit(2)
		return
	# Isolated recipes have their own event windows; do not open a Pattern or
	# Vacuum workspace on a neutral frame using the signature's impact time.
	if scenario != "CLASH_OVERDRIVE":
		for pass_doc in seeded.get("doc", {}).get("final_passes", []):
			if pass_doc.get("operator", "NONE") != "NONE":
				var start := float(pass_doc.event_start)
				var duration := float(pass_doc.duration)
				peak_time = start + duration * 0.5
				phase_times = [maxf(0.0, start - 0.05), start + duration * 0.25, peak_time, start + duration + 0.05]
				break
	root.title = "NRCU FX | " + scenario + " | " + mode + " | LOCAL REVIEW - not artist approved"
	if mode == "lab":
		# The game retains its fixed 16:9 canvas; only the authoring Lab uses
		# the full resizable window instead of letterboxing its control UI.
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		shell = load("res://scenes/nrcu_fx_lab_vnext.tscn").instantiate()
		root.add_child(shell)
		for i in 5: await process_frame
		shell._select_key("composition", true)
		# The review opens on the candidate from frame zero and actually plays;
		# opening at a frozen impact frame cannot communicate its timing.
		shell._seek_authoring(0.0)
		shell.runtime.screen.lab_preview_resume()
		shell._update_play_button()
	else:
		root.window_input.connect(_input)
		var hud := CanvasLayer.new()
		hud.layer = 120
		root.add_child(hud)
		hint = Label.new()
		hint.position = Vector2(12, 685)
		hint.add_theme_color_override("font_shadow_color", Color.BLACK)
		hint.add_theme_constant_override("shadow_offset_x", 2)
		hint.add_theme_constant_override("shadow_offset_y", 2)
		hud.add_child(hint)
		start_game(false)
	for i in 8: await process_frame
	var ready := {"mode": mode, "scenario": scenario, "production": data, "drafts": drafts, "workspace": OS.get_environment("NRCU_FX_WORKSPACE_PATH"), "pid": OS.get_process_id()}
	if mode == "lab":
		ready["selected_target"] = shell.selected_key
		ready["session_mode"] = shell.session.mode
		ready["composition"] = shell.session.composition
		ready["apply_enabled"] = not shell.action_apply.disabled
		ready["preview_mounted"] = shell.runtime.last_mount_ok
		ready["playhead"] = shell._authoring_playhead
		ready["screen_elapsed"] = shell.runtime.elapsed()
		ready["fx_presentation_time"] = shell.renderer.clock_state().get("presentation_time", -1.0)
	else:
		if adapter == null or not is_instance_valid(adapter.screen()):
			push_error("Review adapter did not create a screen")
			quit(2)
			return
		var binding = adapter.screen().get_node("ProductionFx")
		ready["runtime_summary"] = binding.last_summary
		ready["preview_lifetime"] = adapter.screen().has_meta("fx_preview_no_teardown")
		ready["composition"] = binding.production.load_composition().get("doc", {})
	var file := FileAccess.open(review_dir.path_join("review_ready.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(ready, "  "))
	file.close()
	# Optional evidence capture only; this does NOT close or time out the review.
	var capture_path := OS.get_environment("NRCU_FX_REVIEW_CAPTURE")
	if capture_path != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_path)
	print("[FX-REVIEW] READY mode=%s scenario=%s; persistent until window close" % [mode, scenario])

func start_game(play: bool) -> void:
	if adapter != null and is_instance_valid(adapter):
		if is_instance_valid(adapter.screen()): adapter.screen().free()
		adapter.free()
	adapter = Adapter.new()
	root.add_child(adapter)
	adapter.finished.connect(func():
		hint.text = "LOCAL ADAPTER: complete. F5 replay | 1-4 phase | N neutral/candidate | close window to stop"
		print("[FX-REVIEW] GAME_FINISHED; window remains open"))
	if not adapter.begin(Setup.match_config()):
		push_error("Review matchup unsupported: " + adapter.bypass_reason())
		return
	if play:
		adapter.signal_match_ready()
	else:
		seek_game(peak_time)
	apply_comparison()
	print("[FX-REVIEW] GAME_START playback=", play)

func seek_game(t: float) -> void:
	if adapter == null or not is_instance_valid(adapter.screen()):
		start_game(false)
	var screen = adapter.screen()
	screen.lab_preview_pause()
	screen.lab_preview_seek(t)
	var binding = screen.get_node("ProductionFx")
	binding.renderer.set_clocks(t, t)
	update_hint()
	print("[FX-REVIEW] SEEK ", t)

func apply_comparison() -> void:
	if adapter != null and is_instance_valid(adapter.screen()):
		var binding = adapter.screen().get_node("ProductionFx")
		if neutral: binding.renderer.clear_all()
		else: binding.reload_production()
	update_hint()
	print("[FX-REVIEW] NEUTRAL ", neutral)

func update_hint() -> void:
	hint.text = ("NEUTRAL" if neutral else "SAVED CANDIDATE") + " | LOCAL ADAPTER | F5 replay | Space pause/play | 1 PRE  2 Early  3 Peak  4 Recovery | N compare"

func _input(event: InputEvent) -> void:
	if mode != "game" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F5: start_game(true)
		KEY_1: seek_game(float(phase_times[0]))
		KEY_2: seek_game(float(phase_times[1]))
		KEY_3: seek_game(float(phase_times[2]))
		KEY_4: seek_game(float(phase_times[3]))
		KEY_N:
			neutral = not neutral
			apply_comparison()
		KEY_SPACE:
			if adapter != null and is_instance_valid(adapter.screen()):
				var screen = adapter.screen()
				if screen.lab_preview_is_paused():
					screen.lab_preview_resume()
					adapter.signal_match_ready()
				else: screen.lab_preview_pause()
			else: start_game(true)

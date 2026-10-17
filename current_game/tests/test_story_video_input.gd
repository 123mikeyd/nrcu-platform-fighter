extends SceneTree
const Movie = preload("res://scripts/story_video.gd")
const Ending = preload("res://scripts/story_ending.gd")
var failures := 0
var checks := 0
var done := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func run() -> void:
	var movie = Movie.new()
	root.add_child(movie)
	await process_frame
	movie.finished.connect(func(): done += 1)
	for code in [KEY_ENTER, KEY_ESCAPE]:
		movie.play_clip("witcheer_unlock")
		key(code, true)
		await process_frame
		key(code, false)
		check(not movie.active and not paused and movie.player.stream == null, "real input skip " + str(code))
	check(done == 2, "keyboard skips emitted exactly once each")
	movie.play_clip("turbofit_celebration")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	pad.device = 0
	Input.parse_input_event(pad)
	await process_frame
	pad.pressed = false
	Input.parse_input_event(pad)
	check(not movie.active and done == 3 and not paused, "controller accept skips")
	movie.play_clip("turbofit_celebration")
	movie.skip_button.pressed.emit()
	check(not movie.active and done == 4, "visible skip button callback")
	movie.play_clip("basilisk_credits")
	movie.queue_free()
	await process_frame
	check(not paused and done == 4, "exit-tree cancels without completion callback")
	var ending = Ending.new()
	root.add_child(ending)
	await process_frame
	ending.play("turbofit")
	ending._motion.kill()
	ending._begin_movies()
	key(KEY_ENTER,true)
	await process_frame
	key(KEY_ENTER,false)
	check(ending.phase == "credits" and ending.movie.active, "one Enter skips celebration only, credits remain")
	key(KEY_ESCAPE,true)
	await process_frame
	key(KEY_ESCAPE,false)
	check(not ending.visible and not paused, "second input exits credits and clears audio")
	ending.queue_free()
	await process_frame
	print("%s: movie input %d checks / %d failed" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

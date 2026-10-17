extends SceneTree
const Movie = preload("res://scripts/story_video.gd")
const Ending = preload("res://scripts/story_ending.gd")
var checks := 0
var failures := 0
var completions := 0
var capture: AudioEffectCapture
var out := ""
func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1
func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-16000, -16000)
	call_deferred("run")
func save_frame(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "native viewport image " + name_text)
	if image and not image.is_empty(): image.save_png(out.path_join(name_text + ".png"))
func audio_peak() -> float:
	var peak := 0.0
	var frames := capture.get_buffer(capture.get_frames_available())
	for sample in frames: peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak
func run() -> void:
	out = OS.get_environment("STORY_VIDEO_EVIDENCE")
	if out.is_empty():
		print("FAIL: explicit evidence directory required")
		quit(1)
		return
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(0, capture)
	var movie = Movie.new()
	root.add_child(movie)
	await process_frame
	movie.finished.connect(func(): completions += 1)
	for id in ["witcheer_unlock", "turbofit_celebration"]:
		capture.clear_buffer()
		movie.play_clip(id)
		check(movie.player.stream is VideoStreamTheora, "native Theora resource " + id)
		await create_timer(1.5).timeout
		check(movie.player.is_playing() and movie.player.stream_position > 0.8, "native playback clock advances " + id)
		var texture: Texture2D = movie.player.get_video_texture()
		check(texture != null and texture.get_width() == 854, "native decoded texture " + id)
		check(audio_peak() > 0.0001, "embedded audio mixed " + id)
		await save_frame(id)
		var limit := Time.get_ticks_msec() + 9000
		while movie.active and Time.get_ticks_msec() < limit: await process_frame
		check(not movie.active and not paused, "natural completion and pause cleanup " + id)
		check(movie.player.stream == null, "decoder/audio released " + id)
	check(completions == 2, "one finish callback per short")
	movie.skip()
	check(completions == 2, "repeated skip cannot double-complete")
	# Paused-entry ownership is restored, not forcibly unpaused.
	paused = true
	movie.play_clip("witcheer_unlock")
	movie.cancel()
	check(paused and completions == 2, "cancel preserves preexisting pause and emits nothing")
	paused = false
	movie.queue_free()
	await process_frame
	var ending = Ending.new()
	root.add_child(ending)
	await process_frame
	ending.play("turbofit")
	# Exercise real hold/fade and real natural Turbo -> credits transition.
	await create_timer(6.2).timeout
	check(ending.phase == "celebration", "real hold/fade reaches Turbo celebration")
	var limit := Time.get_ticks_msec() + 9000
	while ending.phase == "celebration" and Time.get_ticks_msec() < limit: await process_frame
	check(ending.phase == "credits" and ending.is_rolling(), "natural Turbo ending reaches shared credits")
	capture.clear_buffer()
	await create_timer(2).timeout
	check(ending.movie.player.is_playing() and ending.movie.player.stream_position > 1, "Basilisk native playback with credits")
	check(audio_peak() > 0.0001, "Basilisk embedded soundtrack mixed")
	await save_frame("credits_start")
	var previous_y: float = ending.roll.position.y
	var captured_middle := false
	var captured_end := false
	limit = Time.get_ticks_msec() + 310000
	while ending.visible and Time.get_ticks_msec() < limit:
		var pos: float = ending.movie.player.stream_position
		if pos > 155 and not captured_middle:
			check(ending.roll.position.y < previous_y, "credits scroll against actual movie position")
			await save_frame("credits_middle")
			captured_middle = true
		if pos > 285 and not captured_end:
			await save_frame("credits_end")
			captured_end = true
		await process_frame
	check(captured_middle and captured_end, "full Basilisk stream reached middle and ending")
	check(not ending.visible and not paused, "full natural credits completion restores tree")
	check(ending.movie.player.stream == null and not ending.movie.active, "full music-video audio/decoder cleanup")
	capture.clear_buffer()
	await create_timer(0.3).timeout
	check(audio_peak() < 0.00001, "audio bus silent after completion")
	ending.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("%s: native video playback %d checks / %d failed" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

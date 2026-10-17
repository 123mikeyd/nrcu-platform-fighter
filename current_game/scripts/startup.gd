extends Control
## The launch scene owns only the logo; no fighter/main preloads here.
const FRONTEND := "res://scenes/home.tscn"
const VIDEO := "res://assets/startup/nous_logo.ogv"
const HOLD := "res://assets/startup/nous_hold.png"
var video: VideoStreamPlayer
var hold: TextureRect
var status: Label
var skip: Button
var scene: PackedScene
var frontend_script: Script
var requested := false
var finished := false
var skip_requested := false
var entering := false
var failed := false
var elapsed := 0.0
var progress: Array = []
# In-memory fault-injection seam; production remains zero/no artificial wait.
var readiness_delay := 0.0
var events: Array = []
func mark(event: String) -> void:
	events.append({"event": event, "ms": Time.get_ticks_msec(), "elapsed": elapsed})
func _ready() -> void:
	get_window().title = "The Legends of Nous Research: Hermes, Breaking Containment"
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	hold = TextureRect.new()
	hold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hold.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hold.texture = load(HOLD)
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hold)
	video = VideoStreamPlayer.new()
	video.expand = true
	video.stream = load(VIDEO)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(video)
	resized.connect(_fit_video)
	_fit_video()
	status = Label.new()
	status.position = Vector2(24, 24)
	status.add_theme_color_override("font_color", Color.WHITE)
	add_child(status)
	skip = Button.new()
	skip.text = "Skip · Enter / Space / A"
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position -= Vector2(290, 52)
	skip.size = Vector2(270, 36)
	skip.pressed.connect(request_skip)
	add_child(skip)
	video.finished.connect(_video_finished)
	if get_tree().has_meta("nous_intro_seen"):
		finished = true
		skip_requested = true
	else:
		get_tree().set_meta("nous_intro_seen", true)
		video.play()
		mark("video_started")
	# Ensure the video/logo is actually drawn BEFORE even requesting frontend IO.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await get_tree().process_frame
	mark("first_frame")
	# Godot 4.7.2 leaks parser RefCounteds when these lambda-bearing scripts
	# are first compiled by a resource worker. Warm only the tiny UI script
	# after the first draw; the shelf texture stays a threaded scene dependency.
	frontend_script = load("res://scripts/home.gd")
	mark("ui_script_ready")
	_request_frontend()
	get_node("/root/FrontendCache").start()
func _exit_tree() -> void:
	# Pair an outstanding request on early close as well as normal entry.
	if requested and scene == null and ResourceLoader.load_threaded_get_status(FRONTEND) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_get(FRONTEND)
	if is_instance_valid(video):
		video.stop()
		video.stream = null
func _fit_video() -> void:
	if not video: return
	var fitted := Vector2(1120, 480) * minf(size.x / 1120.0, size.y / 480.0)
	video.size = fitted
	video.position = (size - fitted) * 0.5
func _request_frontend() -> void:
	failed = false
	# Keep asynchronous loading, but avoid dependency subthreads: with the
	# concurrent data-cache warmup they leave a zero-reference RefCounted at
	# shutdown in the native frontend regression. Explicit scene teardown did
	# not fix it; the same request without subthreads exits cleanly.
	requested = ResourceLoader.load_threaded_request(FRONTEND, "PackedScene", false) == OK
	mark("load_requested")
	if not requested: _load_failed()
func _load_failed() -> void:
	failed = true
	status.text = "Menu could not load. Press Skip to retry."
func _process(delta: float) -> void:
	elapsed += delta
	if requested and scene == null and not failed:
		var state := ResourceLoader.load_threaded_get_status(FRONTEND, progress)
		if state == ResourceLoader.THREAD_LOAD_LOADED and elapsed >= readiness_delay:
			scene = ResourceLoader.load_threaded_get(FRONTEND) as PackedScene
			mark("frontend_ready")
		elif state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_load_failed()
	if finished or skip_requested:
		if scene != null and not entering:
			entering = true
			_enter_frontend.call_deferred()
		elif not failed:
			status.text = "Loading menu%s" % ".".repeat(1 + int(elapsed * 2.0) % 3)
func request_skip() -> void:
	mark("skip")
	skip_requested = true
	# Keep the supplied final logo visible while waiting; never a black hole.
	video.stop()
	video.hide()
	if failed: _request_frontend()
func _video_finished() -> void:
	finished = true
	video.hide()
	mark("video_finished")
func _unhandled_input(event: InputEvent) -> void:
	var accepted: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]
	accepted = accepted or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START])
	if accepted:
		request_skip()
		get_viewport().set_input_as_handled()
func _enter_frontend() -> void:
	mark("enter_frontend")
	get_tree().set_meta("nous_startup_events", events.duplicate(true))
	# Home constructs a few Controls only. Heavy matches/roster are lazy as before.
	# Release decoder/audio before SceneTree queues this presentation for deletion.
	video.stop()
	video.stream = null
	# Compile the now-cached arena behind the final logo, not the first click.
	var cache = get_node("/root/FrontendCache")
	if cache.is_ready: cache.prime_scene()
	get_tree().change_scene_to_packed(scene)
	scene = null

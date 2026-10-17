extends Control
## Victory hold -> optional Turbo celebration -> Basilisk with full credit roll.
signal finished
const Credits = preload("res://scripts/story_credits.gd")
const Movie = preload("res://scripts/story_video.gd")
const HOLD := 4.0
const FADE := 1.6
const LINE := 54.0
var black: ColorRect
var roll: Control
var movie: Control
var _motion: Tween
var _scrolling := false
var _roll_height := 0.0
var _hero := ""
var phase := ""
var _fallback_elapsed := 0.0

func _ready() -> void:
	name = "StoryEnding"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://scripts/demo_style.gd").make()
	black = ColorRect.new()
	black.name = "FadeToBlack"
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	movie = Movie.new()
	add_child(movie)
	movie.finished.connect(_movie_finished)
	var window := Control.new()
	window.position = Vector2(840, 50)
	window.size = Vector2(420, 620)
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window)
	roll = Control.new()
	roll.name = "CreditsRoll"
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(roll)
	set_process(false)
	hide()

func _line(text: String, y: float, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(10, y)
	label.size = Vector2(400, LINE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	roll.add_child(label)

func _build_roll() -> void:
	for child in roll.get_children():
		roll.remove_child(child)
		child.queue_free()
	var y := 0.0
	_line(Credits.HEADING, y, 28, Color("f2d27a")); y += LINE * 1.5
	_line(Credits.SUBHEADING, y, 22, Color("f2d27a")); y += LINE * 1.5
	_line(Credits.CREATED_BY, y, 22, Color.WHITE); y += LINE * 2
	for section in Credits.SECTIONS:
		_line(section[0], y, 28, Color("f2d27a")); y += LINE * 1.5
		for i in range(1, section.size()):
			_line(section[i], y, 21, Color("e8eef2")); y += LINE
		y += LINE * 1.5
	_line(Credits.CLOSING, y, 28, Color("f2d27a")); y += LINE
	_roll_height = y

func play(hero := "") -> void:
	cancel()
	_hero = hero
	phase = "hold"
	_build_roll()
	roll.hide()
	black.modulate.a = 0
	show()
	_motion = create_tween()
	_motion.tween_interval(HOLD)
	_motion.tween_property(black, "modulate:a", 1.0, FADE)
	_motion.tween_callback(_begin_movies)

func _begin_movies() -> void:
	if not visible: return
	if _hero == "turbofit":
		phase = "celebration"
		movie.play_clip("turbofit_celebration")
	else:
		_begin_credits()

func _begin_credits() -> void:
	phase = "credits"
	_scrolling = true
	_fallback_elapsed = 0
	roll.position = Vector2.ZERO
	roll.show()
	movie.play_clip("basilisk_credits", true)
	set_process(true)

func _movie_finished() -> void:
	if phase == "celebration": _begin_credits()
	elif phase == "credits": _end()

func is_rolling() -> bool:
	return visible and _scrolling

func _process(delta: float) -> void:
	if not _scrolling: return
	# Track actual movie time, not scaled gameplay delta: credits and video end together.
	_fallback_elapsed += delta
	var seconds: float = movie.player.stream_position if movie.player.stream else _fallback_elapsed
	var length: float = movie.player.get_stream_length() if movie.player.stream else 291.883
	if length <= 0: length = 291.883
	roll.position.y = -maxf(0, _roll_height - 530) * clampf(seconds / maxf(1, length - 8), 0, 1)

func skip() -> void:
	if not visible: return
	# Skip the current presentation; Turbo's celebration never skips shared credits.
	if phase == "celebration": movie.skip()
	else: _end()

func cancel() -> void:
	if _motion and _motion.is_valid(): _motion.kill()
	if movie: movie.cancel()
	_scrolling = false
	phase = ""
	set_process(false)
	hide()

func _end() -> void:
	if not visible: return
	cancel()
	finished.emit()

func _input(event: InputEvent) -> void:
	if not visible or movie.active: return
	var pad_skip: bool = event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]
	if pad_skip or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		if event is InputEventKey and event.echo: return
		get_viewport().set_input_as_handled()
		skip()

func _exit_tree() -> void:
	cancel()

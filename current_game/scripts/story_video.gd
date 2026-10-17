extends Control
## Owned movie overlay. Cancel is silent; skip/natural completion emits once.
## No save mutations. The caller commits progression before presentation.
signal finished
const CLIPS := {
	"witcheer_unlock": "res://assets/story_video/witcheer_unlock.ogv",
	"turbofit_celebration": "res://assets/story_video/turbofit_celebration.ogv",
	"basilisk_credits": "res://assets/story_video/basilisk_credits.ogv",
}
var player: VideoStreamPlayer
var skip_button: Button
var clip_id := ""
var active := false
var credits_layout := false
var _was_paused := false
var _owns_pause := false

func _ready() -> void:
	name = "StoryVideo"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("05080e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	player = VideoStreamPlayer.new()
	player.name = "MoviePlayer"
	player.expand = true
	player.autoplay = false
	player.loop = false
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.finished.connect(_finish)
	add_child(player)
	skip_button = Button.new()
	skip_button.text = "SKIP  ·  Enter / Esc"
	skip_button.position = Vector2(30, 650)
	skip_button.size = Vector2(290, 46)
	skip_button.pressed.connect(skip)
	add_child(skip_button)
	resized.connect(_fit)
	hide()

func _fit() -> void:
	if player == null: return
	var area := Rect2(Vector2.ZERO, size)
	if credits_layout: area = Rect2(20, 110, 800, 450)
	var ratio := 854.0 / 480.0
	var fitted := Vector2(minf(area.size.x, area.size.y * ratio), minf(area.size.y, area.size.x / ratio))
	player.position = area.position + (area.size - fitted) * 0.5
	player.size = fitted

func play_clip(id: String, with_credits := false) -> void:
	cancel()
	clip_id = id
	credits_layout = with_credits
	active = true
	if not CLIPS.has(id) or not ResourceLoader.exists(CLIPS[id]):
		push_warning("Story video unavailable: " + id)
		call_deferred("_finish")
		return
	player.stream = load(CLIPS[id]) as VideoStream
	if player.stream == null:
		call_deferred("_finish")
		return
	_was_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	player.paused = false
	show()
	_fit()
	player.play()
	skip_button.grab_focus()

func cancel() -> void:
	active = false
	if player:
		player.stop()
		player.stream = null
	if _owns_pause and is_inside_tree():
		get_tree().paused = _was_paused
	_owns_pause = false
	hide()

func skip() -> void:
	if active: _finish()

func _finish() -> void:
	if not active: return
	cancel()
	finished.emit()

func _input(event: InputEvent) -> void:
	if not active: return
	var pad_skip: bool = event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]
	if pad_skip or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		if event is InputEventKey and event.echo: return
		get_viewport().set_input_as_handled()
		skip()

func _exit_tree() -> void:
	cancel()

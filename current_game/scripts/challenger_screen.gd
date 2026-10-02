extends Control
# "A NEW FIGHTER APPROACHES!" (Smash-style challenger) and the matching
# "JOINS THE BATTLE!" / "GOT AWAY" result cards. Dark fades and a slam-in
# title only: no flashing overlays (Mike's rule).
signal fight_requested(id: String)
signal later_requested
signal continue_requested

const DemoStyle = preload("res://scripts/demo_style.gd")
var challenger_id := ""
var mode := ""            # "approach" / "joined" / "escaped"
var title: Label
var subtitle: Label
var portrait: TextureRect
var mystery: Label
var primary: Button
var secondary: Button
var _motion: Tween

func _ready() -> void:
	name = "ChallengerScreen"
	theme = DemoStyle.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.012, 0.02, 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	portrait = TextureRect.new()
	portrait.name = "ChallengerPortrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.position = Vector2(440, 150)
	portrait.size = Vector2(400, 400)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	mystery = Label.new()
	mystery.text = "?"
	mystery.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mystery.position = portrait.position
	mystery.size = portrait.size
	mystery.add_theme_font_size_override("font_size", 260)
	mystery.add_theme_color_override("font_color", Color(0.16, 0.2, 0.26))
	add_child(mystery)
	title = Label.new()
	title.name = "ChallengerTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(40, 40)
	title.size = Vector2(1200, 100)
	title.pivot_offset = title.size * 0.5
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("f0d9a8"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	add_child(title)
	subtitle = Label.new()
	subtitle.name = "ChallengerSubtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(40, 555)
	subtitle.size = Vector2(1200, 40)
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color("b2c5cd"))
	add_child(subtitle)
	primary = Button.new()
	primary.name = "ChallengerPrimary"
	primary.position = Vector2(660, 610)
	primary.size = Vector2(340, 58)
	primary.pressed.connect(_on_primary)
	add_child(primary)
	secondary = Button.new()
	secondary.name = "ChallengerLater"
	secondary.text = "LATER"
	secondary.position = Vector2(280, 610)
	secondary.size = Vector2(340, 58)
	secondary.pressed.connect(func(): hide(); later_requested.emit())
	add_child(secondary)
	hide()

func _set_portrait(id: String, silhouette: bool) -> void:
	var path := "res://assets/story_art/vs/fighters/%s/primary.png" % id
	var has_art := ResourceLoader.exists(path)
	portrait.texture = load(path) if has_art else null
	portrait.flip_h = id == "ggb"
	portrait.modulate = Color(0, 0, 0, 1) if silhouette else Color.WHITE
	portrait.visible = has_art
	# No approved portrait (Bobo, Mephisto): a big "?" while hidden, name only after.
	mystery.visible = not has_art and silhouette
	mystery.text = "?"

func _animate_in() -> void:
	if _motion and _motion.is_valid(): _motion.kill()
	modulate = Color(1, 1, 1, 0)
	title.scale = Vector2(2.2, 2.2)
	primary.disabled = true
	secondary.disabled = true
	_motion = create_tween()
	_motion.tween_property(self, "modulate:a", 1.0, 0.45)
	_motion.tween_property(title, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Small rumble, not a flash.
	for offset in [Vector2(8, 0), Vector2(-6, 3), Vector2(4, -2), Vector2.ZERO]:
		_motion.tween_property(title, "position", Vector2(40, 40) + offset, 0.05)
	_motion.tween_callback(func():
		primary.disabled = false
		secondary.disabled = false
		primary.grab_focus())

func show_approach(id: String) -> void:
	challenger_id = id
	mode = "approach"
	title.text = "A NEW FIGHTER APPROACHES!"
	subtitle.text = "Beat them to add them to your roster."
	_set_portrait(id, true)
	primary.text = "FIGHT!"
	secondary.show()
	show()
	_animate_in()

func show_joined(id: String) -> void:
	challenger_id = id
	mode = "joined"
	var name_text: String = load("res://scripts/roster.gd").display_name(id).replace(" (Prototype)", "").to_upper()
	title.text = "%s JOINS THE BATTLE!" % name_text
	subtitle.text = "Now playable in versus matches and Story mode."
	_set_portrait(id, false)
	if not portrait.visible:
		mystery.visible = true
		mystery.text = name_text.left(1)
		mystery.add_theme_color_override("font_color", Color("e6bb9b"))
	primary.text = "CONTINUE"
	secondary.hide()
	show()
	_animate_in()

func show_escaped(id: String) -> void:
	challenger_id = id
	mode = "escaped"
	title.text = "THE CHALLENGER GOT AWAY..."
	subtitle.text = "They'll challenge you again after your next match."
	_set_portrait(id, true)
	primary.text = "CONTINUE"
	secondary.hide()
	show()
	_animate_in()

func _on_primary() -> void:
	hide()
	if mode == "approach": fight_requested.emit(challenger_id)
	else: continue_requested.emit()

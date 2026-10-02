extends Control
# Story VS splash (Mike 2026-09-30): hero card slides in from the left, opponent
# from the right, VS slams in. An opponent you haven't unlocked yet arrives as a
# black silhouette with "???" and is revealed as VS lands ("Who's that Pokemon").
# Slides/fades/slam only: no flashing overlays (Mike's rule).
# The match is already loaded underneath; main.gd holds READY until this ends.
signal finished

const DemoStyle = preload("res://scripts/demo_style.gd")
const SECONDS := 3.2
const REVEAL_AT := 1.15
const PORTRAIT := "res://assets/story_art/vs/fighters/%s/primary.png"
# Arts Bro accent colors (roster_presentation.json). Bobo is not in that schema:
# his crimson is taken from his in-game armor.
const ACCENT := {
	"teknium": Color8(56, 196, 126), "doge_man": Color8(218, 58, 48), "ggb": Color8(108, 150, 65),
	"ice_mage": Color8(58, 114, 150), "turbofit": Color8(108, 79, 53), "witcheer": Color8(168, 50, 52),
	"mephisto": Color8(218, 126, 74), "bobo": Color8(176, 40, 36),
}
# Side each portrait was drawn facing in from (Arts Bro optical-facing profiles;
# GGB's optical override = right). Bobo/Mephisto pictures were shot facing left.
const DRAWN_ON_LEFT := ["teknium", "turbofit"]

var hero_id := ""
var opponent_id := ""
var silhouette := false
var left_band: Polygon2D
var right_band: Polygon2D
var left_art: TextureRect
var right_art: TextureRect
var left_name: Label
var right_name: Label
var vs_mark: TextureRect
var step_label: Label
var _motion: Tween
var _skippable := false

func _ready() -> void:
	name = "StoryVsSplash"
	theme = DemoStyle.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var base := ColorRect.new()
	base.color = Color(0.015, 0.02, 0.03)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	left_band = Polygon2D.new()
	left_band.polygon = PackedVector2Array([Vector2(0, 0), Vector2(700, 0), Vector2(580, 720), Vector2(0, 720)])
	add_child(left_band)
	right_band = Polygon2D.new()
	right_band.polygon = PackedVector2Array([Vector2(708, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(588, 720)])
	add_child(right_band)
	left_art = _art("HeroPortrait")
	right_art = _art("OpponentPortrait")
	left_name = _name_label("HeroName", HORIZONTAL_ALIGNMENT_LEFT, Vector2(48, 628))
	right_name = _name_label("OpponentName", HORIZONTAL_ALIGNMENT_RIGHT, Vector2(672, 628))
	vs_mark = TextureRect.new()
	vs_mark.name = "VsMark"
	vs_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vs_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vs_mark.texture = load("res://assets/story_art/vs/ui/vs_mark.png")
	vs_mark.size = Vector2(280, 190)
	vs_mark.position = Vector2(640, 360) - vs_mark.size * 0.5
	vs_mark.pivot_offset = vs_mark.size * 0.5
	vs_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vs_mark)
	step_label = Label.new()
	step_label.name = "StoryStep"
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.position = Vector2(340, 18)
	step_label.size = Vector2(600, 40)
	step_label.add_theme_font_size_override("font_size", 22)
	step_label.add_theme_color_override("font_color", Color("b2c5cd"))
	add_child(step_label)
	hide()

func _art(node_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	# Expand mode before any texture, so a 1536px PNG can't set the minimum size.
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = Vector2(560, 600)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t

func _name_label(node_name: String, align: HorizontalAlignment, at: Vector2) -> Label:
	var l := Label.new()
	l.name = node_name
	l.horizontal_alignment = align
	l.position = at
	l.size = Vector2(560, 64)
	l.add_theme_font_size_override("font_size", 48)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 4)
	l.add_theme_constant_override("shadow_offset_y", 4)
	add_child(l)
	return l

static func display(id: String) -> String:
	return load("res://scripts/roster.gd").display_name(id).replace(" (Prototype)", "").to_upper()

func _set_card(art: TextureRect, id: String, on_left: bool) -> void:
	var path := PORTRAIT % id
	art.texture = load(path) if ResourceLoader.exists(path) else null   # Ice Mage: no picture (Mike)
	art.flip_h = (id not in DRAWN_ON_LEFT) if on_left else (id in DRAWN_ON_LEFT)

func play(hero: String, opponent: String, locked_opponent: bool, step_text: String) -> void:
	hero_id = hero
	opponent_id = opponent
	silhouette = locked_opponent and ResourceLoader.exists(PORTRAIT % opponent)
	step_label.text = step_text
	left_band.color = ACCENT.get(hero, Color("466070")).darkened(0.55)
	right_band.color = ACCENT.get(opponent, Color("466070")).darkened(0.55)
	_set_card(left_art, hero, true)
	_set_card(right_art, opponent, false)
	left_name.text = display(hero)
	right_name.text = "???" if silhouette else display(opponent)
	right_art.modulate = Color(0, 0, 0, 1) if silhouette else Color.WHITE
	if _motion and _motion.is_valid(): _motion.kill()
	modulate = Color(1, 1, 1, 0)
	left_art.position = Vector2(-620, 70)
	right_art.position = Vector2(1340, 70)
	left_name.modulate.a = 0.0
	right_name.modulate.a = 0.0
	vs_mark.scale = Vector2(2.4, 2.4)
	vs_mark.modulate.a = 0.0
	_skippable = false
	show()
	_motion = create_tween()
	_motion.tween_property(self, "modulate:a", 1.0, 0.2)
	_motion.parallel().tween_property(left_art, "position", Vector2(30, 70), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.parallel().tween_property(right_art, "position", Vector2(690, 70), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.tween_property(left_name, "modulate:a", 1.0, 0.2)
	_motion.parallel().tween_property(right_name, "modulate:a", 1.0, 0.2)
	_motion.tween_interval(maxf(0.0, REVEAL_AT - 0.85))
	# VS lands; a silhouetted challenger turns to full color as it hits.
	_motion.tween_callback(func(): _skippable = true)
	_motion.tween_property(vs_mark, "modulate:a", 1.0, 0.1)
	_motion.parallel().tween_property(vs_mark, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if silhouette:
		_motion.parallel().tween_property(right_art, "modulate", Color.WHITE, 0.45)
		_motion.parallel().tween_callback(func(): right_name.text = display(opponent_id)).set_delay(0.12)
	_motion.tween_interval(SECONDS - REVEAL_AT - 0.24 - 0.35)
	_motion.tween_property(self, "modulate:a", 0.0, 0.35)
	_motion.tween_callback(_end)

## Remaining splash time (main.gd shortens READY by the same amount on skip).
func remaining() -> float:
	if not visible or _motion == null or not _motion.is_valid(): return 0.0
	return maxf(0.0, SECONDS - _motion.get_total_elapsed_time())

func skip() -> void:
	if not visible: return
	if _motion and _motion.is_valid(): _motion.kill()
	_end()

func _end() -> void:
	hide()
	finished.emit()

func _gui_input(event: InputEvent) -> void:
	if _skippable and event is InputEventMouseButton and event.pressed:
		skip()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if visible and _skippable and event.is_action_pressed("ui_accept"):
		skip()
		get_viewport().set_input_as_handled()

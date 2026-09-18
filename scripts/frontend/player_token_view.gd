extends Control
# PlayerTokenView — Doc 04 §12/§13/§13A. One small round ownership token per
# player: player color + P1-P4 number. NO hand pose is baked in (the hand and
# the token are separate objects; the cursor service only carries this node).
#
# States are PRESENTATION ONLY — the CSS controller owns the state machine and
# drives this view via set_state():
#   UNASSIGNED / PLACED / CARRIED / RETURNING / PLACING
#
# The token art is generated in code (drawn circle + ring + number label), so
# no new sprite is baked into the hand assets and P2/P3/P4 need no duplicated
# raster art (Doc 04 §13A "token color variants").

const Tokens = preload("res://scripts/ui_tokens.gd")

enum State { UNASSIGNED, PLACED, CARRIED, RETURNING, PLACING }
const STATE_NAMES := ["UNASSIGNED", "PLACED", "CARRIED", "RETURNING", "PLACING"]

const TOKEN_SIZE := 26.0     # Doc 04 §13 reference 22-28 px
const RING_W := 2.0

@onready var token_label: Label = $TokenLabel

var player_index := 0
var state: int = State.UNASSIGNED
var _squash := Vector2.ONE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	token_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	token_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	token_label.add_theme_font_override("font", Tokens.font("bold"))
	token_label.add_theme_font_size_override("font_size", 12)
	resized.connect(_layout)
	_layout()
	_apply_state()

# --- API --------------------------------------------------------------------

func set_player(index: int) -> void:
	player_index = index % Tokens.PLAYER_COLORS.size()
	token_label.text = "P" + str(player_index + 1)
	token_label.add_theme_color_override("font_color", Tokens.INK)
	queue_redraw()

func set_state(new_state: int) -> void:
	state = clampi(new_state, 0, STATE_NAMES.size() - 1)
	_apply_state()

func state_name() -> String:
	return STATE_NAMES[state]

func player_color() -> Color:
	return Tokens.PLAYER_COLORS[player_index % Tokens.PLAYER_COLORS.size()]

func ring_color() -> Color:
	return player_color().darkened(0.45)

func token_size() -> float:
	return TOKEN_SIZE

func squash(factor: Vector2) -> void:
	_squash = factor
	scale = _squash
	queue_redraw()

func settle() -> void:
	squash(Vector2.ONE)

func _layout() -> void:
	token_label.position = Vector2.ZERO
	token_label.size = size

# --- presentation ------------------------------------------------------------

func _apply_state() -> void:
	# Presentation only: alpha/squash cues per state. Never gameplay truth.
	match state:
		State.UNASSIGNED:
			modulate.a = 0.35
			squash(Vector2.ONE)
		State.PLACED:
			modulate.a = 1.0
			squash(Vector2.ONE)
		State.CARRIED:
			modulate.a = 1.0
			squash(Vector2(0.96, 0.96))
		State.RETURNING:
			modulate.a = 0.7
			squash(Vector2.ONE)
		State.PLACING:
			modulate.a = 1.0
			squash(Vector2(1.10, 0.90))

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - RING_W * 0.5
	draw_circle(center, radius, player_color())
	draw_arc(center, radius, 0.0, TAU, 32, ring_color(), RING_W, true)
	# Small inner highlight so the token reads as a physical chip.
	draw_circle(center - Vector2(radius * 0.25, radius * 0.3), radius * 0.28, Color(1.0, 1.0, 1.0, 0.22))

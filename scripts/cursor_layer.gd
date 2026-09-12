extends CanvasLayer
# Global hand cursor (Melee grammar): replaces the OS pointer on every screen —
# home, setup, story, match. Chip carrying is used by the story character
# selection only; other screens use the plain glove poses.
const HandCursorScript = preload("res://scripts/hand_cursor.gd")

var hand: Control

func _ready() -> void:
    layer = 100
    hand = HandCursorScript.new()
    hand.name = "HandCursor"
    add_child(hand)
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

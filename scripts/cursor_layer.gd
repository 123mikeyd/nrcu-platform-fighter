extends CanvasLayer
# Global hand cursor (Melee grammar): replaces the OS pointer on every screen —
# home, setup, story, match. Chip carrying is used by the story character
# selection only; other screens use the plain glove poses.
const HandCursorScript = preload("res://scripts/hand_cursor.gd")

var hand: Control

func _ready() -> void:
    layer = 100
    # WP-1 pointer contract: this service IS the visible pointer (the OS pointer
    # is hidden below), so it must keep processing while the tree is paused -
    # otherwise the Pause overlay opens with a frozen hand, no hover and no
    # press feedback, and the player has no pointer at all. Pause is the only
    # state that pauses the tree (main.gd), and its surface is frontend scope.
    process_mode = Node.PROCESS_MODE_ALWAYS
    hand = HandCursorScript.new()
    hand.name = "HandCursor"
    add_child(hand)
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

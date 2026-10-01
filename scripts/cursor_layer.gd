extends CanvasLayer
# Global hand cursor (Melee grammar): replaces the OS pointer on every screen —
# home, setup, story, match. Chip carrying is used by the story character
# selection only; other screens use the plain glove poses.
const HandCursorScript = preload("res://scripts/hand_cursor.gd")

var hand: Control

# The authoring tool is a native-pointer island inside the game. Ownership is
# deliberately kept on this persistent autoload rather than on a mounted
# screen, so a preview remount cannot drop the claim or restore the game hand
# halfway through an authoring session.
var _native_pointer_owners: Dictionary = {}
var _native_pointer_previous_mouse_mode := Input.MOUSE_MODE_HIDDEN
var _native_pointer_previous_hand_visible := true
var _native_pointer_previous_pose := 0
var _overlay_suppressed := false
var _overlay_previous_hand_visible := true

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

func _process(_delta: float) -> void:
    if _native_pointer_owners.is_empty():
        return
    # Other screens historically write MOUSE_MODE_HIDDEN during their entry
    # choreography. While an authoring owner is active, native pointer mode is
    # authoritative and must win that same-frame remount-side write.
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if hand != null:
        hand.set_native_pointer_suppressed(true)

func acquire_native_pointer(owner) -> bool:
    # A null owner cannot be released safely and therefore cannot claim the
    # global mode. Dictionary identity gives Nodes/Objects token semantics and
    # keeps distinct scalar owners independent as well.
    if owner == null or hand == null:
        return false
    if _native_pointer_owners.has(owner):
        return false
    if _native_pointer_owners.is_empty():
        _native_pointer_previous_mouse_mode = Input.mouse_mode
        _native_pointer_previous_hand_visible = hand.visible
        _native_pointer_previous_pose = int(hand.visual)
    _native_pointer_owners[owner] = true
    hand.set_native_pointer_suppressed(true)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    return true

func release_native_pointer(owner) -> bool:
    if owner == null or not _native_pointer_owners.has(owner):
        return false
    _native_pointer_owners.erase(owner)
    if not _native_pointer_owners.is_empty():
        return true
    # Only the final owner restores the exact state captured by the first
    # owner. Intermediate releases are intentionally inert.
    if hand != null:
        hand.set_native_pointer_suppressed(false)
        hand.visible = _native_pointer_previous_hand_visible
        hand.set_visual_mode(_native_pointer_previous_pose)
    Input.mouse_mode = _native_pointer_previous_mouse_mode
    return true

func is_native_pointer_owned() -> bool:
    return not _native_pointer_owners.is_empty()

func native_pointer_owner_count() -> int:
    return _native_pointer_owners.size()

func set_overlay_suppressed(suppressed: bool) -> void:
    # VS presentation owns the top CanvasLayer for its complete lifetime. This
    # lifecycle bit is separate from native-pointer ownership and from the
    # frontend inactivity timeout: an active presentation must never be
    # contaminated by the persistent game hand.
    if hand == null or _overlay_suppressed == suppressed:
        return
    _overlay_suppressed = suppressed
    if suppressed:
        _overlay_previous_hand_visible = hand.visible
        hand.set_native_pointer_suppressed(true)
        hand.visible = false
    else:
        hand.set_native_pointer_suppressed(false)
        hand.visible = _overlay_previous_hand_visible and _native_pointer_owners.is_empty()

func is_overlay_suppressed() -> bool:
    return _overlay_suppressed

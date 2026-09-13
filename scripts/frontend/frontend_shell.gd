extends CanvasLayer
# Frontend — persistent application shell (Step 0 §1) and transition layer.
#
# Owns app-level window policy and the persistent transition layer used for
# cross-screen continuity (e.g. Title shelf → Main field crossfade) without
# cutting to black. Sits BELOW the cursor layer (1000) and above screens.
#
# hold_frame(): snapshot the current viewport and display it on this layer.
# release():     fade that hold out over `duration` seconds -> the new screen
#                underneath is revealed. One continuous surface, no black cut.

const LAYER := 880
const MIN_WINDOW := Vector2i(960, 540)

var _hold: TextureRect

func _ready() -> void:
    layer = LAYER
    _hold = TextureRect.new()
    _hold.name = "TransitionHold"
    _hold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _hold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _hold.stretch_mode = TextureRect.STRETCH_SCALE
    _hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hold.visible = false
    add_child(_hold)

func set_window_policy() -> void:
    # Application-level window policy (Doc 09 §23) — screens do not own it.
    var win := get_window()
    if win != null:
        win.min_size = MIN_WINDOW

func hold_frame() -> void:
    var vp := get_viewport()
    if vp == null:
        return
    if DisplayServer.get_name() == "headless":
        return  # nothing to capture; routing proceeds without the hold
    await RenderingServer.frame_post_draw
    var img := vp.get_texture().get_image()
    if img == null:
        return
    _hold.texture = ImageTexture.create_from_image(img)
    _hold.visible = true
    _hold.modulate.a = 1.0
    _hold.size = vp.get_visible_rect().size

func release(duration := 0.28) -> void:
    if not _hold.visible:
        return
    var tween := create_tween()
    tween.tween_property(_hold, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_callback(func() -> void:
        _hold.visible = false
        _hold.texture = null)

func is_holding() -> bool:
    return _hold != null and _hold.visible

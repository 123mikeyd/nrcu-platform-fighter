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
var _watchdog: Timer

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
    _watchdog = Timer.new()
    _watchdog.one_shot = true
    _watchdog.wait_time = 1.6
    _watchdog.timeout.connect(func() -> void:
        if _hold.visible:
            release(0.22))
    add_child(_watchdog)

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
    # The viewport readback can intermittently come back black (renderer race).
    # A black hold would trap the screen behind an opaque dark cover, so a dark
    # capture is DISCARDED: the route proceeds with a hard cut instead.
    var mean := _image_luma(img)
    if mean < 20.0:
        _hold.visible = false
        _hold.texture = null
        return
    _hold.texture = ImageTexture.create_from_image(img)
    _hold.visible = true
    _hold.modulate.a = 1.0
    _hold.size = vp.get_visible_rect().size
    _watchdog.start()

func release(duration := 0.28) -> void:
    if not _hold.visible:
        return
    if _watchdog != null and _watchdog.time_left > 0.0:
        _watchdog.stop()
    var tween := create_tween()
    tween.tween_property(_hold, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_callback(func() -> void:
        _hold.visible = false
        _hold.texture = null)

func _image_luma(img: Image) -> float:
    # Cheap average of the red channel over a bounded sample (RGBA8/RGBAF safe).
    var data := img.get_data()
    if data.size() < 8:
        return 0.0
    var total := 0.0
    var n := 0
    var step := maxi(4, int(data.size() / 40000.0) * 4)
    var i := 0
    while i < data.size() - 3:
        total += float(data[i]) + float(data[i + 1]) + float(data[i + 2])
        n += 3
        i += step
    if n == 0:
        return 0.0
    return total / float(n)

func is_holding() -> bool:
    return _hold != null and _hold.visible

extends SceneTree
var failures := 0
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        print("FAIL: " + message)
func _initialize():
    call_deferred("run")
func touch(target, index: int, point: Vector2, pressed := true):
    var e := InputEventScreenTouch.new()
    e.index = index
    e.position = point
    e.pressed = pressed
    target._input(e)
func run():
    if not ResourceLoader.exists("res://scripts/mobile_touch.gd"):
        check(false, "mobile touch provider exists")
        quit(1)
        return
    var pad = load("res://scripts/mobile_touch.gd").new()
    root.add_child(pad)
    pad.set_process(false)
    pad.touch_mode = true
    pad.set_gameplay_enabled(true)
    var zones: Dictionary = pad.regions(Vector2(1280,720))
    touch(pad, 0, zones.pad + Vector2(70,0))
    touch(pad, 1, zones.attack)
    var state: Dictionary = pad.controls()
    check(state.right and state.attack, "independent thumbs move and attack together")
    touch(pad, 1, zones.attack, false)
    check(pad.controls().right and not pad.controls().attack, "attack release preserves movement")
    touch(pad, 0, zones.pad, false)
    check(not pad.controls().right, "pad release clears movement")
    touch(pad, 4, zones.pad)
    var drag := InputEventScreenDrag.new()
    drag.index = 4
    drag.position = zones.pad + Vector2(0,-85)
    pad._input(drag)
    check(pad.controls().up, "captured pad drags into up aim")
    touch(pad, 5, zones.pad + Vector2(-80,0))
    check(not pad.controls().left, "second finger cannot steal pad")
    touch(pad, 6, zones.special)
    pad.set_gameplay_enabled(false)
    pad.set_gameplay_enabled(true)
    check(not pad.controls().special and not pad.controls().up, "menu transition cancels every contact")
    touch(pad, 7, zones.attack)
    pad.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(not pad.controls().attack, "focus loss cancels held combat")
    touch(pad, 8, zones.special)
    var cancelled := InputEventScreenTouch.new()
    cancelled.index = 8
    cancelled.position = zones.special
    cancelled.pressed = true
    cancelled.canceled = true
    pad._input(cancelled)
    check(not pad.controls().special, "OS touch cancellation does not press")
    pad.queue_free()
    print("PASS mobile touch" if failures == 0 else "FAIL mobile touch")
    quit(0 if failures == 0 else 1)

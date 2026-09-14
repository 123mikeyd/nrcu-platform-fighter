extends SceneTree
# Verifies the reusable 3D hero rig (Visual spec §10): every roster fighter
# builds a model in its own SubViewport, produces a valid AABB and gets a
# camera fit distance. Also guards the mouse-intent contract of the cursor
# layer (brief §5): screen reset never moves the pointer, and a stationary
# pointer stays inactive until real mouse motion.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var Roster = load("res://scripts/roster.gd")
    var rig = load("res://scripts/hero_rig.gd").new()
    rig.size = Vector2(560.0, 420.0)
    root.add_child(rig)
    for i in 3: await process_frame
    for id in Roster.ids():
        rig.set_fighter(str(id))
        for i in 3: await process_frame
        var box: AABB = rig.model_aabb()
        check(box.size.length() > 0.05, "hero %s builds a visible model" % id)
        check(rig.get_fit_distance() > 0.1, "hero %s gets a camera fit" % id)
        check(not rig.fighter.is_in_group("fighters"), "hero %s stays out of the fighters group" % id)
        check(not rig.fighter.is_physics_processing(), "hero %s has physics disabled" % id)
    rig.clear_fighter()
    await process_frame
    check(not rig.has_fighter(), "hero clears cleanly")
    rig.queue_free()
    await process_frame
    # Cursor contract
    var layer = load("res://scripts/cursor_layer.gd").new()
    root.add_child(layer)
    await process_frame
    var hand = layer.hand
    check(hand != null, "cursor layer exposes the hand")
    if hand != null:
        hand.reset_for_screen()
        check(not hand.is_mouse_active(), "fresh screen starts without mouse authority")
        var before: Vector2 = hand._pos
        hand.attract_to(null)
        hand._process(0.016)
        check(hand._pos.distance_to(before) < 0.75, "focus/attract never drags the hand")
        var motion := InputEventMouseMotion.new()
        motion.position = before + Vector2(40.0, 12.0)
        motion.relative = Vector2(40.0, 12.0)
        hand._input(motion)
        check(hand.is_mouse_active(), "genuine mouse motion activates the pointer")
        # MIGRATED (Doc 03 §2, WP-1a): FOCUS is claimed only by MEANINGFUL
        # frontend input — KEY_TAB used to claim it via the blanket
        # "any key => focus" rule, which the locked contract rejects.
        # A meaningful ui_* navigation key still hands authority back.
        var key := InputEventKey.new()
        key.keycode = KEY_DOWN
        key.pressed = true
        hand._input(key)
        check(not hand.is_mouse_active(), "keyboard navigation hands authority back")
        # §2 counter-proof: a modifier-only key never claims FOCUS. The hand is
        # already in focus mode here, so the claim check is the mode itself.
        var modifier := InputEventKey.new()
        modifier.keycode = KEY_SHIFT
        modifier.pressed = true
        hand.set_mode(0)
        hand._input(modifier)
        check(hand.mode == 0, "a modifier-only key never claims FOCUS")
    layer.queue_free()
    await process_frame
    if failures == 0: print("PASS: hero rig and cursor mouse-intent contract")
    quit(1 if failures else 0)

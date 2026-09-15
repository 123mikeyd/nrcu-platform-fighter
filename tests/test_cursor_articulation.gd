extends SceneTree
# Visual-only cursor articulation contract.
#
# The historical hand animation may lean and squash, but those effects belong
# to the rendered HandVisual only. The logical hotspot, authored focus target,
# carried-token geometry, pause processing, and VS visibility lifecycle remain
# owned by the existing cursor contract.

const HandScript := preload("res://scripts/hand_cursor.gd")
const AnchorScript := preload("res://scripts/frontend/cursor_anchor.gd")

var failures := 0

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for _i in count:
        await process_frame

func motion(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.relative = relative
    return event

func run() -> void:
    var hand: Control = HandScript.new()
    hand.name = "ArticulationProbe"
    root.add_child(hand)
    await frames(2)

    hand.begin_screen("articulation")
    hand.set_mode(hand.Mode.MOUSE)
    var pointer := Vector2(480.0, 260.0)
    hand._input(motion(pointer, Vector2(32.0, 0.0)))
    await frames(2)

    check(hand.hotspot == pointer,
        "mouse articulation leaves the authoritative hotspot at the exact pointer")
    check(absf(hand._lean) > 0.0001,
        "mouse motion produces a visible lean in the rendered hand")
    check(hand._hand.position == pointer,
        "the rendered hand remains positioned at the logical hotspot")
    check(hand._token_slot.position == pointer,
        "the carry layer remains positioned at the logical hotspot")

    var token := Control.new()
    token.name = "CarryGeometryProbe"
    token.size = Vector2(26.0, 26.0)
    root.add_child(token)
    hand.set_carry(token)
    var carry_pointer := Vector2(720.0, 410.0)
    hand._input(motion(carry_pointer, Vector2(24.0, 8.0)))
    await frames(2)
    var token_centre: Vector2 = token.global_position + token.size * 0.5
    check(token_centre.distance_to(hand.carry_pinch_point()) < 0.001,
        "articulation leaves the carried token centred on the existing carry geometry")
    check(hand._token_slot.position == carry_pointer,
        "articulation does not move the carried-token layer away from the hotspot")

    hand.clear_carry()
    hand.set_mode(hand.Mode.MOUSE)
    var focus_start := Vector2(180.0, 140.0)
    hand._input(motion(focus_start, Vector2(-20.0, 0.0)))
    await frames(2)
    var rendered_start: Vector2 = hand.hotspot
    var anchor: Control = AnchorScript.new()
    anchor.name = "AuthoredFocusProbe"
    anchor.place_at(Vector2(900.0, 520.0))
    root.add_child(anchor)
    await frames(2)
    var authored_target: Vector2 = anchor.get_global_rect().position
    hand.set_focus_target(anchor)
    check(hand.hotspot.distance_to(rendered_start) < 0.001,
        "focus entry still starts from the current rendered hotspot")
    for _i in 120:
        hand.step_focus_spring(1.0 / 60.0)
    check(hand.hotspot.distance_to(authored_target) < 0.001,
        "visual articulation leaves the authored focus anchor as the focus target")

    hand.set_overlay_suppressed(true)
    hand._input(motion(Vector2(300.0, 220.0), Vector2(30.0, 0.0)))
    await frames(2)
    check(hand.is_overlay_suppressed() and not hand.visible,
        "VS suppression keeps the hand hidden during pointer motion")
    hand.set_overlay_suppressed(false)
    check(hand.visible,
        "releasing VS suppression restores the hand without changing its lifecycle API")

    hand.process_mode = Node.PROCESS_MODE_ALWAYS
    root.get_tree().paused = true
    var paused_pointer := Vector2(340.0, 240.0)
    hand.set_mode(hand.Mode.MOUSE)
    hand._input(motion(paused_pointer, Vector2(18.0, 0.0)))
    await frames(2)
    check(hand.can_process(),
        "the articulated cursor remains processable while the tree is paused")
    check(hand.hotspot == paused_pointer,
        "pause liveness keeps the authoritative hotspot exact")
    root.get_tree().paused = false

    hand.queue_free()
    await frames(2)
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: cursor articulation stays visual-only")
    quit(0)

extends SceneTree
# Hand-keyed Ice Mage kit: real-input jump, double jump, Frost Rise -> helpless,
# hurt flinch, launch tumble and landing, on the live main scene.
var failures := 0
var seen := {}
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
    else:
        print("ok: " + message)
func key(code: int, down: bool):
    var e := InputEventKey.new()
    e.keycode = code
    e.physical_keycode = code
    e.pressed = down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func watch(visual, frames: int) -> Array:
    var order: Array = []
    for i in frames:
        await physics_frame
        var c: String = visual.current_clip
        if order.is_empty() or order[-1] != c: order.append(c)
    return order
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.setup.rows[0].character.select(4)
    arena.setup._start()
    arena._physics_process(arena.ready_remaining)
    var mage = arena.fighters[0]
    check(mage.character_id == "ice_mage", "Ice Mage chosen by setup")
    for other in arena.fighters.slice(1): other.set_physics_process(false)
    for other in arena.fighters.slice(1): other.position.x += 30
    var visual = mage.get_node("VisualRoot/IceMageVisual")
    for i in 45: await physics_frame
    check(mage.is_on_floor() and visual.current_clip == "Idle", "grounded Idle")
    # 1. Ground jump
    key(KEY_SPACE, true)
    var o1 = await watch(visual, 4)
    key(KEY_SPACE, false)
    o1 += await watch(visual, 80)
    print("jump order: ", o1)
    check(o1.find("ice_kit/JumpTakeoff") >= 0 and o1.find("ice_kit/JumpRise") > o1.find("ice_kit/JumpTakeoff"), "takeoff then rise")
    check(o1.find("ice_kit/FallLoop") > o1.find("ice_kit/JumpRise"), "rise then fall loop")
    check(o1.find("ice_kit/JumpLand") > o1.find("ice_kit/FallLoop") and o1[-1] == "Idle", "land then Idle")
    # 2. Double jump
    key(KEY_SPACE, true)
    await watch(visual, 4)
    key(KEY_SPACE, false)
    await watch(visual, 14)
    key(KEY_SPACE, true)
    var o2 = await watch(visual, 4)
    key(KEY_SPACE, false)
    o2 += await watch(visual, 100)
    print("double order: ", o2)
    check(mage.jumps_used == 0 and o2.find("ice_kit/JumpDouble") >= 0, "air jump plays Frost Push double jump")
    check(o2.find("ice_kit/FallLoop") > o2.find("ice_kit/JumpDouble") and o2[-1] == "Idle", "double jump falls, lands, idles")
    # 3. Frost Rise -> helpless
    key(KEY_W, true)
    key(KEY_G, true)
    var o3 = await watch(visual, 6)
    key(KEY_G, false)
    key(KEY_W, false)
    var helpless_seen := false
    var order3: Array = o3.duplicate()
    for i in 160:
        await physics_frame
        var c: String = visual.current_clip
        if order3[-1] != c: order3.append(c)
        if c == "ice_kit/HelplessFall" and mage.recovery_spent: helpless_seen = true
    print("frost rise order: ", order3)
    check(order3.find("ice_kit/FrostRise") >= 0, "up special plays FrostRise (not IceCast)")
    check(helpless_seen and order3.find("ice_kit/HelplessFall") > order3.find("ice_kit/FrostRise"), "spent recovery falls helpless")
    check(mage.is_on_floor() and order3[-1] == "Idle" and order3.find("ice_kit/JumpLand") > order3.find("ice_kit/HelplessFall"), "helpless lands and recovers")
    # 4. Small non-contact hit -> Hurt flinch
    for i in 20: await physics_frame
    mage.receive_hit(2.0, Vector3(-1, 0.1, 0), 0.5)
    await physics_frame
    check(not mage.tumble.active and mage.hitstun > 0 and visual.current_clip == "ice_kit/Hurt", "small hit plays Hurt flinch")
    for i in 60: await physics_frame
    check(visual.current_clip == "Idle", "Hurt returns to Idle")
    # 5. Strong launch -> tumble
    mage.damage_percent = 90.0
    mage.receive_hit(9.0, Vector3(1, 1, 0), 6.0)
    var o5 = await watch(visual, 6)
    check(mage.tumble.active, "strong hit enters launch tumble")
    var vx: float = mage.velocity.x
    o5 += await watch(visual, 20)
    print("tumble order: ", o5, " vx ", vx, " yaw ", visual.model.rotation.y)
    check(o5.find("ice_kit/TumbleLaunch") >= 0 and o5.find("ice_kit/TumbleLoop") > o5.find("ice_kit/TumbleLaunch"), "tumble launch then tumble loop")
    check(signf(visual.model.rotation.y) == -signf(vx) or not mage.tumble.active, "back leads the launch")
    check(mage.fitted_reaction == null or not mage.fitted_reaction.active, "fitted flinch does not freeze the tumble")
    var landed := false
    for i in 240:
        await physics_frame
        if mage.is_on_floor() and visual.current_clip == "Idle": landed = true; break
    check(landed or mage.stocks < 3, "tumble ends in landing or blast zone, then Idle")
    # 6. Contact hit keeps the approved fitted reaction in charge
    mage.position = Vector3(0, mage.position.y, 0)
    for i in 30: await physics_frame
    mage.receive_contact_hit(2.0, Vector3(-1, 0.1, 0), 0.5, mage.global_position + Vector3(0, 1.2, 0), "body")
    await physics_frame
    print("contact: fitted ", mage.fitted_reaction.active, " clip ", visual.current_clip, " stocks ", mage.stocks, " hitstun ", mage.hitstun, " dmg ", mage.damage_percent, " ctrl ", mage.controls_enabled, " revprot ", mage.is_revival_protected(), " tumble ", mage.tumble.active)
    var sk: Skeleton3D = visual.model.find_children("*", "Skeleton3D", true, false)[0]
    await physics_frame
    await physics_frame
    var f: float = clampf(mage.fitted_reaction.clock * 60, 0, mage.fitted_reaction.samples["body"].size() - 1)
    var expect: Transform3D = mage.fitted_reaction.samples["body"][int(f)][mage.fitted_reaction.names.find("Spine02")]
    var got: Transform3D = sk.get_bone_pose(sk.find_bone("Spine02"))
    check(mage.fitted_reaction.active and not visual.animation_player.is_playing() and got.origin.distance_to(expect.origin) < 0.5, "approved fitted contact reaction still owns contact hits")
    # 7. Standalone visual (victory/stage use) keeps plain locomotion
    var lone = load("res://scripts/ice_mage_visual.gd").new()
    root.add_child(lone)
    lone.sync_pose(false, Vector3.ZERO, false, false, "", 1.0, 0.0)
    check(lone.current_clip == "Idle", "standalone visual unaffected by kit")
    lone.queue_free()
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: Ice Mage hand-keyed kit: jump, double, Frost Rise, helpless, hurt, tumble, land")
    quit(1 if failures else 0)

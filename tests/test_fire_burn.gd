extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var fs = load("res://scripts/fighter.gd")
    var mage = fs.new()
    mage.character_id = "ice_mage"
    root.add_child(mage)
    mage.enable_fire_prototype()
    mage.set_physics_process(false)
    var target = fs.new()
    root.add_child(target)
    target.set_physics_process(false)
    target.position.x = 3
    check(target.has_method("apply_burn"), "fighter-owned finite burn exists")
    if failures:
        mage.queue_free(); target.queue_free(); await process_frame; quit(1); return
    mage.start_special(Vector2.RIGHT)
    mage._tick_character_move(0.19)
    check(get_nodes_in_group("projectiles").is_empty(), "no button-edge Firebolt")
    mage._tick_character_move(0.01)
    var shots = get_nodes_in_group("projectiles")
    check(shots.size() == 1, "one source-clock Firebolt at 0.2s")
    var shot = shots[0]
    shot.set_physics_process(false)
    var visual = mage.get_node("VisualRoot/IceMageVisual")
    visual.sync_pose(true, Vector3.ZERO, false, false, "", 1.0, 0, "IceCast", 0.2)
    var rig: Skeleton3D = visual.model.find_children("*", "Skeleton3D", true, false)[0]
    rig.force_update_all_bone_transforms()
    var hand := rig.global_transform * rig.get_bone_global_pose(rig.find_bone("RightHand")).origin
    hand.z = 0
    check(shot.global_position.distance_to(hand) < 0.001, "Fire release follows actual authored hand at original cast event")
    check(not shot.freeze_bolt and shot.payload_damage() == 6, "Firebolt distinct impact and no freeze")
    shot._hit_target(target)
    check(target.damage_percent == 6 and target.burn.remaining == 2 and target.freeze_remaining == 0, "impact starts burn once")
    var indicator = target.burn.get_node_or_null("FlameIndicator")
    check(indicator is Sprite3D and indicator.no_depth_test, "compact flame icon stays readable behind platforms without debug text")
    var velocity: Vector3 = target.velocity
    var stun: float = target.hitstun
    target.burn.tick(0.49)
    check(target.damage_percent == 6, "no per-frame damage")
    target.burn.tick(0.01)
    check(target.damage_percent == 7, "one discrete burn tick")
    check(target.velocity == velocity and target.hitstun == stun, "DOT neither knockback nor hitstun")
    target.burn.tick(0.25)
    target.apply_burn(mage)
    target.apply_burn(mage)
    check(target.burn.remaining == 2 and target.burn.next_tick == 0.25, "non-stacking refresh preserves tick phase")
    target.burn.tick(1.75)
    check(target.damage_percent == 11 and is_equal_approx(target.burn.remaining, 0.25) and target.burn.visible, "refresh lasts full duration after its finite tick budget is spent")
    target.burn.tick(20)
    check(target.damage_percent == 11 and target.burn.remaining == 0 and not target.burn.visible, "refresh bounded to four ticks; finite visual")
    target.burn.tick(20)
    check(target.damage_percent == 11, "expired burn cannot cause later damage")
    target.apply_freeze(mage)
    target.apply_burn(mage)
    var freeze: float = target.freeze_remaining
    target.burn.tick(0.5)
    check(target.freeze_remaining == freeze, "burn tick does not thaw or change freeze")
    target.controls_enabled = false
    check(target.burn.remaining == 0 and not target.burn.visible, "disable synchronous even without physics")
    target.controls_enabled = true
    target._clear_freeze()
    target.apply_burn(mage)
    target.lose_stock()
    check(target.burn.remaining == 0, "stock cleanup")
    target.apply_burn(mage)
    target.reset_fighter(Vector3.ZERO)
    check(target.burn.remaining == 0 and target.damage_percent == 0, "reset cleanup")
    await process_frame
    mage.reset_fighter(Vector3.ZERO)
    mage.start_special(Vector2.LEFT)
    mage._tick_character_move(0.2)
    var left_shots = get_nodes_in_group("projectiles")
    check(left_shots.size() == 1 and left_shots[0].direction == -1, "left-facing cast creates exactly one Firebolt")
    visual.sync_pose(true, Vector3.ZERO, false, false, "", -1.0, 0, "IceCast", 0.2)
    rig.force_update_all_bone_transforms()
    hand = rig.global_transform * rig.get_bone_global_pose(rig.find_bone("RightHand")).origin
    hand.z = 0
    check(left_shots[0].global_position.distance_to(hand) < 0.001, "left-facing actual hand release")
    mage.attack_cooldown = 0
    mage.start_special(Vector2.LEFT)
    mage._tick_character_move(0.2)
    check(get_nodes_in_group("projectiles").size() == 1, "dedicated cast cooldown prevents duplicate release")
    mage.lose_stock()
    await process_frame
    check(get_nodes_in_group("projectiles").is_empty(), "caster stock removes owned Fire projectiles")
    mage.start_special(Vector2.RIGHT)
    mage.receive_hit(1, Vector3.RIGHT, 1)
    mage._tick_character_move(0.2)
    check(get_nodes_in_group("projectiles").is_empty(), "windup interruption cancels pending Firebolt")
    mage.queue_free(); target.queue_free()
    await process_frame
    if failures == 0: print("PASS: actual cast/impact, finite discrete nonstacking refresh, no stun/knockback/thaw, lifecycle cleanup")
    quit(1 if failures else 0)

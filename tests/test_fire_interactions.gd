extends SceneTree
var failures := 0
var arena
var mage
var target
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func frames(n: int):
    for i in n: await physics_frame
    await process_frame
func shot():
    var p = load("res://scripts/fire_projectile.gd").new()
    p.source = mage
    p.direction = 1
    arena.add_child(p)
    p.position = mage.position + Vector3(0.85, 1, 0)
    return p
func reset_pair():
    mage.reset_fighter(Vector3(-3, 0, 0), true)
    target.reset_fighter(Vector3.ZERO, true)
    mage.team_id = -1
    target.team_id = -1
    for p in get_nodes_in_group("projectiles"): p.queue_free()
    await process_frame
func run():
    arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var slots = arena.Config.default_slots()
    slots[0].character = "witcheer"
    slots[1].character = "ice_mage"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    arena.start_match(slots, false)
    arena._physics_process(arena.ready_remaining)
    mage = arena.player_two
    target = arena.player_one
    mage.enable_fire_prototype()
    for f in arena.fighters: f.set_physics_process(false)
    await reset_pair()
    target.damage_percent = 20
    target._start_witcheer("Celebration")
    target.witcheer_elapsed = target.witcheer_moves.Celebration.contact_time
    target.witcheer_absorbing = true
    var absorbed = shot()
    await frames(16)
    check(not is_instance_valid(absorbed) and target.damage_percent == 14 and target.burn == null and target.freeze_remaining == 0, "real contact absorption heals impact payload only; consumes before burn")
    await reset_pair()
    target.shielding = true
    shot()
    await frames(16)
    check(is_equal_approx(target.damage_percent, 2.1) and target.burn == null, "real shield impact chip with no burn")
    await reset_pair()
    mage.team_id = 0
    target.team_id = 0
    shot()
    await frames(16)
    check(target.damage_percent == 0 and target.burn == null, "real sweep excludes friendly fighter")
    check(not target.apply_burn(mage) and not mage.apply_burn(mage), "direct status rejects ally/self")
    await reset_pair()
    var wall := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(0.2, 3, 3)
    shape.shape = box
    wall.add_child(shape)
    wall.position = Vector3(-1, 1, 0)
    arena.add_child(wall)
    await frames(2)
    shot()
    await frames(16)
    check(target.damage_percent == 0 and target.burn == null, "terrain consumes projectile before fighter")
    wall.queue_free()
    await reset_pair()
    var reflected = shot()
    reflected.position = Vector3(-0.95, 1, 0)
    reflected.lifetime = 0.3
    reflected.reflect(target, Color.BLUE)
    check(reflected.source == target and reflected.direction == -1 and reflected.lifetime == 0.3 and not reflected.freeze_bolt, "reflection retains Fire payload and finite TTL")
    await frames(16)
    check(mage.damage_percent == 6 and mage.burn != null and mage.burn.remaining > 0 and target.damage_percent == 0, "reflected Fire actually ignites original owner")
    await reset_pair()
    var p = shot()
    p.set_physics_process(false)
    p._hit_target(target)
    p._hit_target(target)
    check(target.damage_percent == 6, "duplicate sink cannot reapply impact")
    target.burn.tick(0.25)
    var other = load("res://scripts/fighter.gd").new()
    other.character_id = "ice_mage"
    arena.add_child(other)
    other.set_physics_process(false)
    other.enable_fire_prototype()
    other.apply_burn(mage)
    other.burn.tick(0.5)
    check(other.burn != target.burn and other.damage_percent == 1 and target.damage_percent == 6, "duplicate victims have independent burn clocks")
    var a = mage.get_node("VisualRoot/IceMageVisual").model.find_children("*", "MeshInstance3D", true, false)[0].get_active_material(0)
    var b = other.get_node("VisualRoot/IceMageVisual").model.find_children("*", "MeshInstance3D", true, false)[0].get_active_material(0)
    check(a != b, "duplicate Fire materials independent")
    target.burn.tick(0.25)
    check(target.damage_percent == 7, "duplicate victim tick stays on original phase")
    var before: float = target.freeze_immunity
    target.cancel_for_grab()
    target.burn.tick(0.5)
    check(target.damage_percent == 8 and target.freeze_immunity == before and target.caught_by == null, "burn does not contaminate grab/freeze state")
    arena.show_setup()
    other.controls_enabled = false
    check(not target.burn.visible and not other.burn.visible, "finite local VFX cleared on controls disable")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: real swept absorption/shield/team/terrain/reflection, duplicate contacts/materials/status, grab isolation and cleanup")
    quit(1 if failures else 0)

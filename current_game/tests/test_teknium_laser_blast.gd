extends "res://tests/test_teknium_kit_rework.gd"
# Laser Blast (Tek neutral special, 2026-09-28). Real key input through the ordinary match.
func laser_fx(kit, n): return kit.fx.get(n) if kit.fx.has(n) else null
func run():
    arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
    var ids = load("res://scripts/match_config.gd").CHARACTERS
    for i in 2:
        arena.setup.rows[i].character.select(ids.find("teknium" if i == 0 else "doge_man"))
        arena.setup.rows[i].kind.select(0)
    arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
    arena.setup._refresh(); arena.setup._start(); await frames(150)
    f = arena.fighters[0]; target = arena.fighters[1]
    var kit = f.teknium_specials
    var view = f._visual_root.get_node("TekniumVisual")
    var hz := float(Engine.physics_ticks_per_second)
    var fire_ticks := int(ceil(kit.L_FIRE * hz))
    print("INFO physics_hz=", hz, " fire_ticks=", fire_ticks)
    # 1. Ground: both facings, fixed telegraph, one 22 hit, gun in hand, line then beam, small ledge-safe slide.
    for direction in [-1, 1]:
        await reset_case(); f.facing = direction
        target.reset_fighter(Vector3(-2 + direction * 4, 0, 0), true); await frames(8)
        var start_x: float = f.global_position.x
        key(KEY_G, true)   # held from the start: holding must neither cancel nor extend the charge
        await frames(2)
        check(kit.phase == "laser" and not f.charging, "neutral G starts Laser Blast (no old charge) " + str(direction))
        await frames(12)
        check(view.laser_gun.visible, "holo gun is visible in his hand " + str(direction))
        check(view.current_clip == "laser/LaserBlast", "LaserBlast clip drives the pose " + str(direction))
        await frames(20)
        check(laser_fx(kit, "line") != null and laser_fx(kit, "line").visible, "telegraph line visible during charge " + str(direction))
        check(target.damage_percent == 0, "no damage during telegraph " + str(direction))
        check(absf(f.global_position.x - start_x) < 0.05, "stands still while charging " + str(direction))
        # hold G to prove the charge is fixed length (holding does not extend)
        key(KEY_G, true)
        await frames(fire_ticks - 34 + 3)
        check(laser_fx(kit, "core").visible, "beam fires on the fixed frame even while G is held " + str(direction))
        check(target.damage_percent == kit.L_DAMAGE, "beam hits target in front once for 22 " + str(direction))
        key(KEY_G, false)
        await frames(40)
        check(target.damage_percent == kit.L_DAMAGE, "beam cannot hit twice " + str(direction))
        var slide: float = (f.global_position.x - start_x) * -direction
        check(slide > 0.25 and slide < 0.8, "ground recoil pushes back a smidge (%.2f) %d" % [slide, direction])
        await frames(30)
        check(kit.phase == "idle" and not view.laser_gun.visible, "move ends, gun gone " + str(direction))
    # 2. Target behind is not hit.
    await reset_case(); f.facing = 1
    target.reset_fighter(Vector3(-5, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(fire_ticks + 10)
    check(target.damage_percent == 0, "laser misses target behind")
    await frames(60)
    # 3. Jump before flash cancels: no blast, he jumps.
    await reset_case(); f.facing = 1
    target.reset_fighter(Vector3(2, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(30)
    key(KEY_SPACE, true); await frames(2); key(KEY_SPACE, false)
    check(kit.phase == "idle" and f.velocity.y > 0, "fresh jump during telegraph cancels and jumps")
    await frames(fire_ticks)
    check(target.damage_percent == 0 and not laser_fx(kit, "core").visible, "cancelled laser never fires")
    check(not view.laser_gun.visible, "gun holo-fades after cancel")
    check(kit.stored_charge == 0 and not f.charging, "cancelled laser stores nothing")
    await frames(60)
    # 3b. Fresh special press before flash cancels in place; the next laser starts from zero (no storage).
    await reset_case(); f.facing = 1
    target.reset_fighter(Vector3(2, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(40)
    key(KEY_G, true); await frames(2); key(KEY_G, false)
    check(kit.phase == "idle" and f.is_grounded(), "fresh special press during telegraph cancels in place")
    check(kit.stored_charge == 0 and not f.charging, "special cancel stores nothing")
    await frames(fire_ticks)
    check(target.damage_percent == 0, "special-cancelled laser never fires")
    await frames(20)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(3)
    check(kit.phase == "laser" and kit.elapsed < 0.2, "next laser restarts the full charge from zero")
    await frames(int(ceil(kit.L_FLASH * hz)) - 20)
    check(target.damage_percent == 0, "restarted laser has not fired early")
    await frames(30)
    check(target.damage_percent == kit.L_DAMAGE, "restarted laser fires on the full fixed timing")
    await frames(60)
    # 3c. Special press after the white flash is committed.
    await reset_case(); f.facing = 1
    target.reset_fighter(Vector3(2, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false)
    await frames(int(ceil(kit.L_FLASH * hz)) + 1 - 2)
    key(KEY_G, true); await frames(3); key(KEY_G, false)
    check(kit.phase == "laser", "special press after the flash does not cancel")
    await frames(20)
    check(target.damage_percent == kit.L_DAMAGE, "blast after flash still hits")
    await frames(60)
    # 4. Jump after the white flash does NOT cancel (committed).
    await reset_case(); f.facing = 1
    target.reset_fighter(Vector3(2, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false)
    await frames(int(ceil(kit.L_FLASH * hz)) + 1 - 2)
    key(KEY_SPACE, true); await frames(3); key(KEY_SPACE, false)
    check(kit.phase == "laser", "jump after the flash is committed (no cancel)")
    await frames(20)
    check(target.damage_percent == kit.L_DAMAGE, "committed blast still hits")
    await frames(60)
    # 5. Air: slow fall while charging, bigger shove than ground; held jump from takeoff never cancels.
    await reset_case(); f.facing = 1
    f.reset_fighter(Vector3(-2, 10, 0), true); await frames(2)
    key(KEY_SPACE, true); await frames(3)
    var air_x: float = f.global_position.x
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(25)
    check(kit.phase == "laser", "held jump from before the move does not cancel it")
    check(f.velocity.y >= -1.3 and f.velocity.y <= 0.01, "air: slow fall while charging (vy=%.2f)" % f.velocity.y)
    key(KEY_SPACE, false)
    await frames(fire_ticks)
    var air_slide: float = air_x - f.global_position.x
    check(air_slide > 0.9, "air recoil shoves him back further than ground (%.2f)" % air_slide)
    await frames(80)
    # 6. Ledge safety on the ground: custom small platform, pushed toward its edge, stays on.
    await reset_case(); f.facing = 1
    var plat = StaticBody3D.new(); var pc = CollisionShape3D.new(); var pb = BoxShape3D.new()
    pb.size = Vector3(3.0, 0.4, 4.0); pc.shape = pb; plat.add_child(pc); arena.add_child(plat); plat.position = Vector3(-6, 7.8, 0)
    f.reset_fighter(Vector3(-7.3, 8.3, 0), true); await frames(30)
    var was_grounded: bool = f.is_grounded()
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(fire_ticks + 40)
    check(was_grounded and f.is_grounded() and f.global_position.x > -7.6 and f.global_position.y > 7.9, "ground pushback stops at the ledge (x=%.2f, grounded=%s)" % [f.global_position.x, str(f.is_grounded())])
    await frames(40); plat.queue_free(); await frames(2)
    # 7. Hit interrupts cleanly.
    await reset_case(); f.facing = 1
    target.reset_fighter(Vector3(2, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(20)
    f.receive_hit_from(2, Vector3.LEFT, 1, target); await frames(fire_ticks)
    check(kit.phase == "idle" and target.damage_percent == 0 and not laser_fx(kit, "line").visible, "hit interrupts laser: no ghost blast, FX cleared")
    # 8. Wall blocks the beam; teammates are safe.
    await reset_case(); f.facing = 1
    var wall = StaticBody3D.new(); var col = CollisionShape3D.new(); var box = BoxShape3D.new()
    box.size = Vector3(.25, 9, 4); col.shape = box; wall.add_child(col); arena.add_child(wall); wall.position = Vector3(0, 3, 0)
    target.reset_fighter(Vector3(1.5, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(fire_ticks + 10)
    check(target.damage_percent == 0, "stage wall blocks the beam")
    wall.queue_free(); await frames(60)
    await reset_case(); f.team_id = 1; target.team_id = 1; f.facing = 1
    target.reset_fighter(Vector3(1, 0, 0), true); await frames(8)
    key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(fire_ticks + 10)
    check(target.damage_percent == 0, "laser cannot damage a teammate")
    f.team_id = -1; target.team_id = -1
    await frames(60)
    # 9. Disable/stock loss clear it.
    for mode in ["disable", "stock"]:
        await reset_case()
        key(KEY_G, true); await frames(2); key(KEY_G, false); await frames(20)
        if mode == "disable": f.controls_enabled = false
        else: f.lose_stock()
        await frames(3)
        check(kit.phase == "idle" and not laser_fx(kit, "line").visible, "laser cleared on " + mode)
        f.controls_enabled = true
    for code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_G, KEY_SPACE, KEY_E, KEY_F]: key(code, false)
    arena.queue_free(); await frames(3)
    print("TEKNIUM_LASER_COMPLETE checks=%d failures=%d" % [checks, fails])
    quit(1 if fails else 0)

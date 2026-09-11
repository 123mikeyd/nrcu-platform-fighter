extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    seed(100)
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var slots = arena.Config.default_slots()
    slots[1].character = "ice_mage"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    arena.start_match(slots, false)
    var mage = arena.fighters[1]
    var target = arena.fighters[0]
    mage.enable_fire_prototype()
    arena._physics_process(arena.ready_remaining)
    mage.reset_fighter(Vector3(1.5, 0, 0))
    target.reset_fighter(Vector3(0, 0, 0))
    # Passive human uses real physics; close opponent must reserve a special.
    var cast_seen := false
    var burning := false
    for i in 300:
        await physics_frame
        await process_frame
        cast_seen = cast_seen or mage.ice_attack_clip == "IceCast"
        burning = burning or (target.burn != null and target.burn.remaining > 0)
    check(cast_seen, "real close Fire bot casts instead of basic starvation")
    check(burning and target.damage_percent > 0, "real Fire bot projectile collision ignites P1")
    print("BOT TRACE damage=", target.damage_percent, " cast=", cast_seen, " burn=", burning)
    arena.show_setup()
    check(target.burn == null or target.burn.remaining == 0, "setup immediate cleanup")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: real production Fire bot cast/hit/burn and safe setup cleanup")
    quit(1 if failures else 0)

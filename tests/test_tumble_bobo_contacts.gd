extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok, message):
    if not ok:
        failures += 1
        print("FAIL: ", message)
func run():
    var b = load("res://scripts/bobo_fighter.gd").new()
    root.add_child(b)
    b.set_physics_process(false)
    await process_frame
    check(b.has_method("query_thrust_contacts"), "two source-derived actual claw windows query physical capsules")
    if b.has_method("query_thrust_contacts"):
        var target = load("res://scripts/fighter.gd").new()
        target.character_id = "ggb"
        root.add_child(target)
        target.set_physics_process(false)
        await process_frame
        for direction in [-1.0, 1.0]:
            b.cancel_thrust_slash()
            b.thrust_rest = 0
            b.begin_thrust_slash(direction)
            # Place real capsule on measured per-claw surface, not global radius.
            for hit in 2:
                var event: Dictionary = b.thrust_manifest.hits[hit]
                b.thrust_elapsed = float(event.contact_time)
                b._update_move_visuals(0)
                var center: Vector3 = b.thrust_claw_center(hit)
                target.position = center - Vector3.UP * 0.95
                target.velocity = Vector3.ZERO
                await physics_frame
                await process_frame
                target.damage_percent=999
                var before: float = target.damage_percent
                b.query_thrust_contacts()
                check(target.damage_percent == before + float(event.damage), "actual claw capsule hit %d facing %s" % [hit,direction])
                check(not target.tumble.active if hit==0 else target.tumble.active,"first capped swipe stays weak; second may launch")
                check(target.last_damage_source==b,"claw credits Bobo")
                b.query_thrust_contacts()
                check(target.damage_percent == before + float(event.damage), "per-target per-hit latch")
            b.cancel_thrust_slash()
            b.thrust_rest = 0
            b.begin_thrust_slash(direction)
            target.position = Vector3(direction * 8, 0, 0)
            await physics_frame
            await process_frame
            var before: float = target.damage_percent
            b.thrust_elapsed = float(b.thrust_manifest.hits[0].contact_time)
            b.query_thrust_contacts()
            check(target.damage_percent == before, "no global/invisible range")
        target.queue_free()
    b.queue_free()
    await process_frame
    print("PASS: Bobo high-percent launch contacts" if not failures else "FAIL: Bobo high-percent launch contacts")
    quit(1 if failures else 0)

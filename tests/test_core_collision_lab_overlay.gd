extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.select_fighter(1,"turbofit"); lab.set_generated_collision_enabled(true)
    check(lab.has_method("set_collision_snapshot_phase"),"explicit current vs contact overlay selection")
    if not lab.has_method("set_collision_snapshot_phase"):
        lab.free(); quit(1); return
    lab.set_collision_shapes_visible(true)
    await tick(lab)
    check(lab.collision_debug.has_method("capsule_lines"),"published primitive line converter")
    if not lab.collision_debug.has_method("capsule_lines"):
        lab.free(); quit(1); return
    for phase in ["current_pose","contact_snapshot"]:
        check(lab.set_collision_snapshot_phase(phase),"phase selection")
        var record: Dictionary = lab.simulation.collision_telemetry(2)
        if phase == "contact_snapshot": record = record.contact_snapshot
        var entry: Dictionary = lab.collision_debug.entries.get("hurtboxes:2",{})
        check(not entry.is_empty(),"generated hurtboxes separate from native body entry")
        if entry.is_empty(): continue
        check(entry.primitives == record.primitives and entry.phase == phase,"exact detached published primitives and phase")
        check(entry.color != lab.collision_debug.FIGHTER_COLOR and entry.color != lab.collision_debug.TERRAIN_COLOR,"hurtbox distinct color")
        check(entry.points.size() > 0,"actual lines")
    check(not lab.set_collision_snapshot_phase("guess"),"unknown phase refused")
    var primitive := {"a":Vector3(1,2,3),"b":Vector3(1,4,3),"radius":.5}
    var points: PackedVector3Array = lab.collision_debug.capsule_lines(primitive)
    var bounds := AABB(points[0],Vector3.ZERO)
    for point in points: bounds = bounds.expand(point)
    check(bounds.position.is_equal_approx(Vector3(.5,1.5,2.5)) and bounds.end.is_equal_approx(Vector3(1.5,4.5,3.5)),"surface extrema use endpoints plus radius not movement body")
    lab.set_generated_collision_enabled(false)
    check(not lab.collision_debug.entries.has("hurtboxes:2"),"optout removes stale hurtbox geometry")
    lab.free()
    if not failures: print("PASS: published snapshot overlay phase separation geometry and cleanup")
    quit(1 if failures else 0)

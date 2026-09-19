extends "res://tests/test_core_combat_lab.gd"
func normalized(value):
    if value is Dictionary:
        var result := {}
        for k in value:
            if k == "generation": continue
            result[k] = normalized(value[k])
            if k in ["activation_id","recovery_id"] and value[k] is String and not value[k].is_empty():
                var parts: PackedStringArray = value[k].split(":")
                if parts.size() > 1:
                    parts[0] = "GEN"
                    result[k] = ":".join(parts)
        return result
    if value is Array:
        var result := []
        for v in value: result.append(normalized(v))
        return result
    return value
func scenario(lab) -> Array:
    lab.reset_lab()
    var trace := []
    for i in range(40): await tick(lab)
    key(KEY_G,true)
    for i in range(30):
        await tick(lab)
        trace.append(normalized(lab.get_snapshot()))
    key(KEY_G,false)
    await tick(lab)
    check(lab.simulation.fighters[2].percent > 10 and lab.simulation.fighters[1].percent == 0,"physical held release damages opponent never source")
    trace.append(normalized(lab.get_snapshot()))
    for i in range(70):
        await tick(lab)
        trace.append(normalized(lab.get_snapshot()))
    lab.reset_lab()
    lab.actors[1].position.x = 8
    for i in range(40): await tick(lab)
    key(KEY_D,true)
    key(KEY_G,true)
    await tick(lab)
    key(KEY_D,false)
    key(KEY_G,false)
    check(lab.simulation.projectile_telemetry().size() == 1,"physical Wave emits once")
    for i in range(150):
        await tick(lab)
        trace.append(normalized(lab.get_snapshot()))
    check(lab.simulation.projectile_telemetry().is_empty() and lab.projectile_visuals.is_empty(),"finite detached lifetime completes")
    return trace
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0,"turbofit")
    for opponent in ["teknium","turbofit"]:
        lab.select_fighter(1,opponent)
        var first := await scenario(lab)
        for v in lab.imported_visuals: v.hide()
        var hidden := await scenario(lab)
        check(first == hidden,"hidden mixed/duplicate trace exactly equal")
        for v in lab.imported_visuals: v.free()
        var absent := await scenario(lab)
        check(first == absent,"deleted actual presenters mixed/duplicate trace exactly equal")
        # Restore via supported selection seam rather than a presentation writer.
        lab.select_fighter(0,"teknium")
        lab.select_fighter(0,"turbofit")
        lab.select_fighter(1,"turbofit" if opponent == "teknium" else "teknium")
        lab.select_fighter(1,opponent)
    lab.free()
    if not failures: print("PASS: physical charge Wave source immunity exact visible hidden absent mixed duplicate traces")
    quit(1 if failures else 0)

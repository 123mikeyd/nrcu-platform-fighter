extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    current_scene = lab
    lab.set_physics_process(false)
    var text := ""
    for label in lab.find_children("*", "Label", true, false): text += label.text
    check("G" in text and "L" in text and "FORCE PUSH" in text, "UI advertises horizontal G/L force")
    check("recovery" in text and "full freeze" in text and "defense" in text and "stocks" in text, "UI explicitly bounds scope")
    check(lab.get_snapshot().has("projectiles"), "snapshot exposes detached projectile telemetry")
    for i in range(40): await tick(lab)
    key(KEY_D, true)
    key(KEY_G, true)
    for i in range(15): await tick(lab)
    key(KEY_D, false)
    key(KEY_G, false)
    var snapshot: Dictionary = lab.get_snapshot()
    check(snapshot.actors[0].get("force_age", -1) == 15, "telemetry exposes committed force age")
    if snapshot.has("projectiles"):
        check(snapshot.projectiles.size() == 1 and snapshot.projectiles[0].position.size() == 3, "snapshot exposes full world projectile position")
        snapshot.projectiles.clear()
        check(lab.simulation.projectiles.size() == 1, "diagnostic snapshot cannot mutate authoritative shots")
    lab._process(0)
    check("shots" in lab.telemetry_label.text, "visible projectile telemetry")
    var sim = lab.simulation
    lab.back_to_movement()
    await process_frame
    await process_frame
    check(sim.projectiles.is_empty() and sim.fighters.is_empty(), "navigation clears active shots and actor references")
    current_scene.free()
    current_scene = null
    if failures == 0: print("PASS: FORCE PUSH scope, telemetry and live-shot navigation cleanup")
    quit(1 if failures else 0)

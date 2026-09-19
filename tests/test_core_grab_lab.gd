extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for slot in range(2):
        lab.reset_lab()
        for i in range(40): await tick(lab)
        var direction := KEY_D if slot == 0 else KEY_LEFT
        key(direction, true)
        await tick(lab)
        key(direction, false)
        for i in range(12): await tick(lab)
        lab.actors[slot].position.x = 0
        lab.actors[1-slot].position.x = 1.1 if slot == 0 else -1.1
        var special := KEY_G if slot == 0 else KEY_L
        key(special, true)
        await tick(lab)
        var f: Dictionary = lab.simulation.fighters[slot+1]
        check(f.grab != null, "physical exact neutral special accepts grab")
        check(lab.imported_visuals[slot].animation_player.assigned_animation == "GrabStart", "committed startup renders GrabStart")
        for age in range(2, 131):
            await tick(lab)
            if age == 12: check(lab.simulation.fighters[2-slot].caught_by == slot+1, "real capture both facings")
            if age == 22:
                check(lab.imported_visuals[slot].animation_player.assigned_animation == "GrabLoop", "hold renders GrabLoop")
                check(lab.imported_visuals[1-slot].animation_player.assigned_animation == "Electrocution", "matching hold victim renders source Electrocution")
            if age == 97:
                check(lab.simulation.fighters[2-slot].percent == 10, "five real percent-only ordinals")
                check(lab.imported_visuals[slot].animation_player.assigned_animation == "GrabEnd", "ending renders GrabEnd")
                check(lab.imported_visuals[1-slot].animation_player.assigned_animation != "Electrocution", "ending immediately clears victim clip")
            if age == 110:
                check(lab.simulation.fighters[2-slot].caught_by == 0, "release at source boundary")
                check(lab.simulation.fighters[2-slot].grab_immune_until > lab.simulation.tick, "release grants immunity")
        for i in range(220): await tick(lab)
        check(f.grab == null and lab.simulation.fighters[2-slot].percent == 10, "held special cannot retrigger")
        key(special, false)
    lab.free()
    if failures == 0: print("PASS: grab lab physical G/L capture hold ending immunity held suppression")
    quit(1 if failures else 0)

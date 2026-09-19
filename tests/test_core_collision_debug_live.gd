extends "res://tests/test_core_collision_debug.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_paused(true)
    lab.set_collision_shapes_visible(true)
    check(lab.collision_debug.has_method("refresh"), "live overlay refresh API exists")
    if not lab.collision_debug.has_method("refresh"):
        lab.free()
        quit(1)
        return
    var debug = lab.collision_debug
    debug.refresh()
    check(debug.entries.size() == 3, "two live capsules and one real stage box")
    var capsule = lab.actors[0].get_node("CoreCapsule")
    var terrain: CollisionShape3D
    for node in lab.find_children("*", "CollisionShape3D", true, false):
        if node.get_parent() is StaticBody3D: terrain = node
    print("GEOMETRY: shapes=", debug.entries.size(), " capsule radius=", capsule.shape.radius, " height=", capsule.shape.height, " local offset=", capsule.position, " capsule vertices=", debug.world_lines(capsule).size(), " stage size=", terrain.shape.size, " stage vertices=", debug.world_lines(terrain).size())
    var original: Transform3D = terrain.get_parent().transform
    terrain.get_parent().transform = Transform3D(Basis.from_euler(Vector3(.2, .4, .1)).scaled(Vector3(1.1, .9, 1.3)), Vector3(3, -2, 1))
    debug.refresh()
    check(debug.entries[terrain.get_instance_id()].points == debug.world_lines(terrain), "actual stage rotated/scaled transform read live")
    terrain.get_parent().transform = original
    lab.actors[0].add_collision_exception_with(lab.actors[1])
    debug.refresh()
    check(debug.entries.size() == 3 and lab.actors[1] in lab.actors[0].get_collision_exceptions(), "pair exception retained; shape membership not pair-contact promise")
    lab.actors[0].remove_collision_exception_with(lab.actors[1])
    var extra := CollisionShape3D.new()
    extra.shape = SphereShape3D.new()
    terrain.get_parent().add_child(extra)
    debug.refresh()
    check(debug.entries.size() == 4, "new actual collision node discovered")
    extra.free()
    debug.refresh()
    check(debug.entries.size() == 3, "freed collision node removed without stale entry")
    for iteration in range(3):
        lab.select_fighter(0, "ice_mage" if iteration % 2 == 0 else "teknium")
        lab.select_fighter(1, lab.selected_fighters[0])
        lab.reset_lab()
        debug.refresh()
        check(debug.entries.size() == 3, "duplicate selection/reset never duplicates geometry")
    lab.actors[0].position += Vector3(2, 4, 0)
    debug.refresh()
    check(debug.entries[capsule.get_instance_id()].points == debug.world_lines(capsule), "paused actual head offset and world pose")
    capsule.disabled = true
    debug.refresh()
    check(not debug.entries.has(capsule.get_instance_id()), "disabled shape hidden immediately")
    capsule.disabled = false
    lab.actors[0].collision_layer = 0
    debug.refresh()
    check(debug.entries.size() == 2, "zero-layer body hidden")
    lab.actors[0].collision_layer = 2
    lab.simulation.set_enabled(1, false)
    debug.refresh()
    check(debug.entries.size() == 2, "match nonparticipant hidden even if engine layer remains")
    lab.reset_lab()
    debug.refresh()
    check(debug.entries.size() == 3, "reset restores participants while paused")
    var snapshot: Dictionary = lab.get_snapshot().duplicate(true)
    debug.refresh()
    lab.set_collision_shapes_visible(false)
    lab.set_collision_shapes_visible(true)
    debug.refresh()
    check(lab.get_snapshot() == snapshot, "read-only refresh/toggle")
    check(debug.find_child("BodyTerrainLines", true, false).material_override.no_depth_test, "wireframe visible through model")
    var legend = lab.find_child("CollisionLegend", true, false)
    check(legend != null and "cyan solid bodies" in legend.text and "green terrain" in legend.text and "attack queries not shown" in legend.text, "honest visible scope legend")
    lab.free()
    if failures == 0: print("PASS: collision debug live resources, lifecycle, disabled filtering and read-only overlay")
    quit(1 if failures else 0)

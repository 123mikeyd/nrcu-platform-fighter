extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var fs = load("res://scripts/fighter.gd")
    var caster = fs.new()
    root.add_child(caster)
    caster.set_physics_process(false)
    var heights := []
    for identity in ["teknium", "ggb"]:
        var victim = fs.new()
        victim.character_id = identity
        root.add_child(victim)
        victim.set_physics_process(false)
        victim.apply_burn(caster)
        var burn = victim.burn
        check(burn.visible and burn.indicator.is_visible_in_tree(), "active icon visible")
        check(burn.find_children("*", "Label3D", false, false).is_empty(), "no debug banner")
        check(burn.embers.size() == 7 and burn.get_child_count() == 8, "bounded sprites only, no crude meshes/lights")
        heights.append(burn.indicator.position.y)
        var damage: float = victim.damage_percent
        var remaining: float = burn.remaining
        var next: float = burn.next_tick
        var pos: Vector3 = burn.embers[0].position
        burn._process(0.15)
        check(burn.embers[0].position.y > pos.y, "embers visibly rise on independent cosmetic clock")
        check(victim.damage_percent == damage and burn.remaining == remaining and burn.next_tick == next and burn.total_ticks == 0, "render frames cannot spend damage or duration")
        for ember in burn.embers:
            check(not ember.no_depth_test and ember.modulate.a <= 0.68, "restrained world-depth embers")
        burn.tick(1.85)
        burn._process(0)
        check(burn.indicator.modulate.a > 0 and burn.indicator.modulate.a < 0.6, "smooth final fade while still active")
        burn.tick(0.15)
        check(not burn.visible and not burn.is_processing() and victim.damage_percent == 4, "expiry clears presentation and four ticks only")
        for i in 20:
            victim.apply_burn(caster)
            burn.clear()
        check(burn.get_child_count() == 8 and not burn.indicator.is_visible_in_tree(), "refresh/clear reuse bounded nodes without residue")
        victim.queue_free()
    check(heights[1] < heights[0], "small GGB indicator follows actual body bounds")
    caster.queue_free()
    await process_frame
    if failures == 0: print("PASS: burn presentation lifecycle, bounded rising embers, depth, scale, fade and independent clock")
    quit(1 if failures else 0)

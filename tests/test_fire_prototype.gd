extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var fighter = load("res://scripts/fighter.gd")
    var ice = fighter.new()
    ice.character_id = "ice_mage"
    root.add_child(ice)
    ice.set_physics_process(false)
    check(ice.has_method("enable_fire_prototype"), "explicit internal Fire prototype opt-in exists")
    if failures:
        ice.queue_free()
        await process_frame
        quit(1)
        return
    var fire = fighter.new()
    fire.character_id = "ice_mage"
    root.add_child(fire)
    fire.set_physics_process(false)
    fire.enable_fire_prototype()
    var iv = ice.get_node("VisualRoot/IceMageVisual")
    var fv = fire.get_node("VisualRoot/IceMageVisual")
    var im = iv.model.find_children("*", "MeshInstance3D", true, false)
    var fm = fv.model.find_children("*", "MeshInstance3D", true, false)
    check(im.size() == fm.size(), "same mesh inventory")
    for i in im.size():
        check(im[i].mesh == fm[i].mesh, "exact original mesh resource reused")
        for s in im[i].mesh.get_surface_count():
            var a = im[i].get_active_material(s)
            var b = fm[i].get_active_material(s)
            print("MATERIAL ", im[i].name, " ", a.albedo_color, " texture=", a.albedo_texture)
            check(a != b and a is StandardMaterial3D and b is ShaderMaterial, "Fire-only material and original Ice material independent")
            check(b.get_shader_parameter("source_texture") == a.albedo_texture, "original texture read-only")
            check(not a.emission_enabled, "Ice emission unchanged")
    check(not ice.prototype_fire and fire.prototype_fire, "per-instance opt-in")
    check("fire_mage" not in load("res://scripts/roster.gd").ids(), "no public roster expansion")
    check("fire_mage" not in load("res://scripts/match_config.gd").CHARACTERS, "no normal selection expansion")
    ice.queue_free()
    fire.queue_free()
    await process_frame
    if failures == 0: print("PASS: internal Fire variant and read-only original mesh/texture; separate instance materials; no roster expansion")
    quit(1 if failures else 0)

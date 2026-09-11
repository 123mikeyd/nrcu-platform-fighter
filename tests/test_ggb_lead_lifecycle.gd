extends SceneTree
var failed=false
func check(ok:bool,msg:String):
    if not ok:
        printerr("FAIL: "+msg)
        failed=true
func _initialize():call_deferred("run")
func run():
    var F=load("res://scripts/fighter.gd")
    var a=F.new()
    var b=F.new()
    a.character_id="ggb"
    b.character_id="ggb"
    root.add_child(a)
    root.add_child(b)
    a.set_physics_process(false)
    b.set_physics_process(false)
    var v=a.get_node("VisualRoot/GGBVisual")
    var other=b.get_node("VisualRoot/GGBVisual")
    if not v.has_method("set_lead"):
        printerr("FAIL: same-body lead material lifecycle missing")
        a.free();b.free();quit(1);return
    var original=v.meshes[0].get_active_material(0)
    var mesh=v.meshes[0].mesh
    check(original!=other.meshes[0].get_active_material(0),"per-instance originals")
    for action in ["hit","reset","stock","menu","freeze"]:
        a.reset_fighter(Vector3(0,4,0),true)
        a.start_special(Vector2.DOWN)
        check(v.is_lead,"down special immediately enters lead: "+action)
        var lead=v.meshes[0].get_active_material(0)
        check(lead!=original and lead.roughness>=0.8 and lead.metallic>=0.5,"matte metallic not chrome")
        check(lead.albedo_texture==null and lead.albedo_color.r<0.5 and lead.albedo_color.r==lead.albedo_color.g,"lead gray not global flash")
        check(v.meshes[0].mesh==mesh,"unchanged body silhouette")
        check(other.meshes[0].get_active_material(0)==other.originals[0] and not other.is_lead,"no other-instance contamination")
        var wing=v.wings[0].transform
        v.sync_pose(false,Vector3(0,-24,0),true,1,0.1,false)
        check(wing.is_equal_approx(v.wings[0].transform),"lead wings tucked and held")
        match action:
            "hit":a.receive_hit(8,Vector3.UP,4)
            "reset":a.reset_fighter(Vector3.ZERO,true)
            "stock":a.lose_stock()
            "menu":
                a.controls_enabled=false
                a._physics_process(0.016)
            "freeze":
                b.position=Vector3(4,4,0)
                a.apply_freeze(b)
        check(not a.drop_committed and not v.is_lead,"interruption clears committed lead: "+action)
        for i in v.meshes.size():check(v.meshes[i].get_active_material(0)==v.originals[i],"full material restored: "+action)
    a.free();b.free()
    if not failed:print("PASS: GGB same-body lead, tucking, per-instance isolation and hit/reset/stock/menu/freeze restoration")
    quit(1 if failed else 0)

extends SceneTree
var failed=false
func check(ok:bool,msg:String):
    if not ok:
        printerr("FAIL: "+msg)
        failed=true
func _initialize(): call_deferred("run")
func run():
    var f=load("res://scripts/fighter.gd").new()
    f.character_id="ggb"
    root.add_child(f)
    f.set_physics_process(false)
    var v=f.get_node_or_null("VisualRoot/GGBVisual")
    check(v!=null,"GGB must use source mesh, not yellow primitive")
    if v==null:
        f.free()
        quit(1)
        return
    check(v.meshes.size()==3,"one body and two reviewed detachable wings")
    check(v.wings.size()==2,"two original hinge helpers")
    check(v.meshes[0].get_active_material(0).albedo_texture.get_width()==4096,"original 4K painted signature")
    var wing=v.wings[0]
    v.sync_pose(false,Vector3(0,5,0),false,1,0.04,false)
    var first=wing.transform
    v.sync_pose(false,Vector3(0,5,0),false,1,0.04,false)
    check(not first.is_equal_approx(wing.transform),"flight wing flap changes geometry")
    var idle=v.wings[0].rotation.z
    v.sync_pose(true,Vector3.ZERO,false,1,0.04,false)
    check(absf(v.wings[0].rotation.z-idle)>0.001,"idle also has subtle flap")
    check(f.get_node("VisualRoot").get_child_count()==1,"no residual capsule/overalls")
    f.free()
    if not failed:print("PASS: GGB source mesh, texture, wings, no placeholder")
    quit(1 if failed else 0)

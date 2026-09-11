extends SceneTree
var failed=false
func check(ok:bool,msg:String):
    if not ok:
        printerr("FAIL: "+msg)
        failed=true
func key(code:int,pressed:bool):
    var e=InputEventKey.new()
    e.physical_keycode=code
    e.keycode=code
    e.pressed=pressed
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func frames(n:int):
    for i in n:await physics_frame
    await process_frame
func _initialize():call_deferred("run")
func run():
    var stage=Node3D.new()
    root.add_child(stage)
    var floor_body=StaticBody3D.new()
    var c=CollisionShape3D.new()
    c.shape=BoxShape3D.new()
    c.shape.size=Vector3(20,1,10)
    floor_body.add_child(c)
    floor_body.position.y=-0.5
    stage.add_child(floor_body)
    var f=load("res://scripts/fighter.gd").new()
    f.character_id="ggb"
    f.position.y=4
    stage.add_child(f)
    var v=f.get_node("VisualRoot/GGBVisual")
    key(KEY_S,true);key(KEY_G,true)
    await frames(2)
    key(KEY_G,false);key(KEY_S,false)
    check(f.drop_committed and v.is_lead and f.velocity.y<=-23.9,"real S+G airborne lead plunge")
    check(not f.try_jump(),"no jump cancel during plunge")
    await frames(20)
    check(f.is_on_floor() and not f.drop_committed and not v.is_lead,"real post-slide landing reverts")
    check(f.landing_lag>0 and f.attack_flash_time==0,"impact lag without global flash")
    check(stage.find_children("GGBDustImpact*","Node3D",true,false).size()==1,"one compact dust impact on actual contact")
    await frames(50)
    check(stage.find_children("GGBDustImpact*","Node3D",true,false).is_empty(),"impact cleans itself")
    key(KEY_S,true);key(KEY_G,true)
    await frames(2)
    key(KEY_G,false);key(KEY_S,false)
    check(not f.drop_committed and not v.is_lead and f.landing_lag>0,"ground S+G slam never stuck lead")
    check(stage.find_children("GGBDustImpact*","Node3D",true,false).size()==1,"ground slam dust once")
    f.lose_stock()
    check(stage.find_children("GGBDustImpact*","Node3D",true,false).is_empty(),"stock clears owned dust immediately")
    stage.free()
    if not failed:print("PASS: real keyboard S+G physics plunge/landing/ground slam and compact impact lifecycle")
    quit(1 if failed else 0)

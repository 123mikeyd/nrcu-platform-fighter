extends SceneTree
var failed=false
func check(ok:bool,msg:String):
    if not ok:printerr("FAIL: "+msg);failed=true
func _initialize():call_deferred("run")
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var config=load("res://scripts/match_config.gd")
    var slots=config.default_slots()
    slots[0].character="ggb"
    slots[2].kind="empty"
    slots[3].kind="empty"
    arena.start_match(slots,false)
    arena.fighters[1].set_physics_process(false)
    arena.fighters[1].position=Vector3(12,0,0)
    var f=arena.fighters[0]
    f.reset_fighter(Vector3(-5.2,6,0),true)
    await physics_frame
    await process_frame
    f.start_special(Vector2.DOWN)
    var contact=false
    for i in 45:
        await physics_frame
        await process_frame
        if f.is_on_floor():contact=true;break
    check(contact and absf(f.position.y-3.225)<0.06,"heavy plunge lands on actual pass-through platform")
    check(not f.drop_committed and not f.get_node("VisualRoot/GGBVisual").is_lead,"platform contact restores gummy")
    check(f.landing_lag>0.5 and f.jumps_used==0 and f.float_remaining==1.2,"contact restores movement resources and applies slam lag")
    f.reset_fighter(Vector3(0,4,0),true)
    f.velocity.y=-3
    f._jump_was_down=true
    var e=InputEventKey.new()
    e.keycode=KEY_SPACE;e.physical_keycode=KEY_SPACE;e.pressed=true
    Input.parse_input_event(e);Input.flush_buffered_events()
    var wing=f.get_node("VisualRoot/GGBVisual").wings[0]
    var before=wing.transform
    for i in 5:await physics_frame
    await process_frame
    check(f.velocity.y>=-1.51 and f.float_remaining<1.2,"actual held Space floats GGB")
    check(not before.is_equal_approx(wing.transform),"float drives visible wing articulation")
    e.pressed=false;Input.parse_input_event(e);Input.flush_buffered_events()
    arena.queue_free()
    await process_frame
    if not failed:print("PASS: GGB real upper-platform landing and keyboard float with wing articulation")
    quit(1 if failed else 0)

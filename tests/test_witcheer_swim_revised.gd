extends SceneTree
var fails:=0
func _initialize():call_deferred("run")
func ck(ok:bool,msg:String):
    if not ok:fails+=1;printerr("FAIL: "+msg)
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer";root.add_child(f);f.set_physics_process(false);f.position.y=3
    f.start_special(Vector2.UP)
    ck(f.witcheer_clip=="AirSwim","W+G swim route")
    ck(f.recovery_spent,"swim once-airtime recovery")
    if f.witcheer_clip=="AirSwim":
        f._tick_witcheer(1.4);f.velocity.y=-20;f._drive_witcheer()
        ck(f.witcheer_clip=="AirSwim","swim lasts beyond old 1.2s")
        ck(f.velocity.y>0 and f.velocity.y<2,"gentle upward swim")
        ck(absf(f.get_node("VisualRoot/WitcheerVisual").animation_player.get_animation("AirSwim").length-2.0)<0.001,"extended source swim clip 2s")
        f._tick_witcheer(0.61);ck(f.witcheer_clip.is_empty(),"finite 2s swim")
        f.attack_cooldown=0;f.start_special(Vector2.UP);ck(f.witcheer_clip.is_empty(),"no second swim midair")
        f.receive_hit(1,Vector3.RIGHT,1);ck(f.recovery_spent,"interrupt never refreshes swim")
    f.queue_free();await process_frame;print("PASS swim revision" if fails==0 else "swim failures %d"%fails);quit(0 if fails==0 else 1)

extends SceneTree
var fails:=0
func _initialize():call_deferred("run")
func ck(ok:bool,msg:String):
    if not ok:fails+=1;printerr("FAIL: "+msg)
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer";root.add_child(f);f.set_physics_process(false)
    f.start_special(Vector2.RIGHT);ck(f.witcheer_clip=="Toss","A/D+G toss route")
    if f.witcheer_clip=="Toss":
        var source_contact=20.8/24.0;var release=source_contact/3.0
        f._tick_witcheer(release-0.001);ck(get_nodes_in_group("projectiles").is_empty(),"no early coin")
        f._tick_witcheer(0.001);ck(get_nodes_in_group("projectiles").size()==1,"coin releases at accelerated anticipation end")
        var v=f.get_node("VisualRoot/WitcheerVisual");var actual=v.hand_world()
        v.show_move("Toss",source_contact,f.facing);ck(v.hand_world().distance_to(actual)<0.00001,"exact original hand release pose")
        f._tick_witcheer(0.2);f._update_move_visuals();actual=v.hand_world();v.show_move("Toss",source_contact+0.2,f.facing)
        ck(v.hand_world().distance_to(actual)<0.00001,"followthrough resumes original source speed")
        f._tick_witcheer(0.44);ck(f.witcheer_clip.is_empty(),"finite piecewise toss clock")
    f.reset_fighter(Vector3.ZERO,true);f.queue_free();await process_frame
    print("PASS toss piecewise clock" if fails==0 else "toss failures %d"%fails);quit(0 if fails==0 else 1)

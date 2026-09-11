extends SceneTree
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok: bool,msg: String):
    checks+=1
    if not ok:failures+=1;printerr("FAIL: "+msg)
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer"
    var v=load("res://scripts/fighter.gd").new();v.character_id="witcheer"
    root.add_child(f);root.add_child(v);f.set_physics_process(false);v.set_physics_process(false)
    var visual=f.get_node("VisualRoot/WitcheerVisual")
    for air in [false,true]:
        for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
            f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(1.4,0,0),true)
            f.basic_attack(aim,air)
            var expected=("SpinRise" if aim.y<0 else "JumpPunch") if air else ("CaneSweep" if aim.y>0 else "HighKick")
            check(f.witcheer_clip==expected,"basic mapping "+str(aim)+" air="+str(air))
            check(v.damage_percent==0,"no button-edge hit")
            if f.witcheer_clip!=expected:continue
            var m=f.witcheer_moves[expected]
            v.position=Vector3(f.facing*1.4,0,0)
            f._tick_witcheer(float(m.contact_time)-0.01)
            check(v.damage_percent==0,"no pre-contact damage "+expected)
            f._tick_witcheer(0.01);f._update_move_visuals()
            check(v.damage_percent==float(m.damage),"source contact damage "+expected)
            check(visual.current_clip==expected,"source clip presented "+expected)
            check(visual.get_node_or_null("ContactAccent")!=null and visual.get_node("ContactAccent").visible,"restrained contact accent at hit")
            f._tick_witcheer(0.02)
            check(v.damage_percent==float(m.damage),"one strike only")
            f._tick_witcheer(3)
            check(f.witcheer_clip.is_empty(),"finite end")
    for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
        f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(1.4,0,0),true)
        f.start_special(aim)
        var expected="AirSwim" if aim.y<0 else ("Celebration" if aim.y>0 else ("Toss" if aim.x!=0 else "Celebration"))
        check(f.witcheer_clip==expected,"special mapping "+str(aim))
        check(not f.charging,"no inherited charge")
        if f.witcheer_clip!=expected:continue
        check(v.damage_percent==0,"special no button-edge damage")
        var m=f.witcheer_moves[expected]
        f._tick_witcheer(float(m.contact_time));f._update_move_visuals()
        check(visual.current_clip==expected,"special clip shown")
        if expected=="Toss":check(get_nodes_in_group("projectiles").size()==1,"one toss at release")
        if expected=="AirSwim":check(f.recovery_spent and f.velocity.y>0,"recovery lift/resource")
        f._tick_witcheer(3);check(f.witcheer_clip.is_empty(),"special finite")
        f.reset_fighter(Vector3.ZERO,true)
        await process_frame
    for interrupt in ["hit","freeze","grab","stock","reset","setup"]:
        f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(1.4,0,0),true)
        f.basic_attack(Vector2.ZERO,false)
        match interrupt:
            "hit":f.receive_hit(1,Vector3.RIGHT,1)
            "freeze":f.apply_freeze(v)
            "grab":f.cancel_for_grab()
            "stock":f.lose_stock()
            "reset":f.reset_fighter(Vector3.ZERO,true)
            "setup":f.controls_enabled=false;f._update_move_visuals()
        check(f.witcheer_clip.is_empty(),"immediate cancel "+interrupt)
        f._tick_witcheer(2)
        check(v.damage_percent==0,"no late hit "+interrupt)
    f.queue_free();v.queue_free();await process_frame
    print(("PASS " if failures==0 else "FAIL ")+"WITCHEER KIT: %d checks, %d failures"%[checks,failures])
    quit(0 if failures==0 else 1)

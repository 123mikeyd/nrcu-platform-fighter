extends SceneTree
var failures:=0
func check(ok,message):
    if not ok:failures+=1;print("FAIL: ",message)
func _initialize():call_deferred("run")
func fighter(pos:Vector3):
    var f=load("res://scripts/fighter.gd").new();root.add_child(f);f.set_physics_process(false);f.position=pos;return f
func run():
    for direction in [1.0,-1.0]:
        for mode in ["shield","team","far","freeze","immunity","hit","utility","caster_freeze","victim_freeze","caster_stock","victim_stock","reset","menu","victim_menu","remove","duplicate","resources","whiff","bot"]:
            var f=fighter(Vector3.ZERO);f.facing=direction
            var v=fighter(Vector3(direction*1.35,0,0));var other=fighter(Vector3(direction*1.7,0,0));other.team_id=2;f.team_id=2
            if mode=="shield":v.shielding=true
            if mode=="team":v.team_id=2
            if mode=="far":v.position.x=direction*4
            if mode=="freeze":v.freeze_remaining=1
            if mode=="immunity":v.grab_immunity=1
            if mode=="whiff":v.position.x=-direction*1.35
            if mode=="resources":v.jumps_used=2;v.recovery_spent=true;v.tackle_spent=true;v.float_remaining=0.4
            await physics_frame;await process_frame
            if mode=="bot":
                f.control_type="bot";f._bot.sequence=5
                var intent=f.read_controls(0.016)
                check(intent.special and not intent.left and not intent.right and not intent.attack,"bot deliberately uses close neutral grab")

            f.start_special(Vector2.ZERO);var m=f.teknium_magic;m.tick(0.20)
            if mode in ["shield","team","far","freeze","immunity","whiff"]:
                check(v.caught_by==null,"capture exclusion "+mode)
                m.tick(2);check(v.damage_percent==0 and m.phase=="idle","whiff no damage or stuck ending "+mode)
            else:

                check(v.caught_by==m,"eligible capture "+mode+str(direction))
                if is_instance_valid(v.caught_by):v._update_move_visuals()
                check(other.caught_by==null,"one eligible victim only")
                match mode:
                    "hit":f.receive_hit(1,Vector3.RIGHT,1)
                    "utility":f.receive_hit(0,Vector3.RIGHT,1)
                    "caster_freeze":f.apply_freeze(v)
                    "victim_freeze":v.apply_freeze(f)
                    "caster_stock":f.lose_stock()
                    "victim_stock":v.lose_stock()
                    "reset":f.reset_fighter(Vector3.ZERO)
                    "menu":f.controls_enabled=false
                    "victim_menu":v.controls_enabled=false
                    "remove":f.queue_free();await process_frame
                    "duplicate":
                        other.team_id=-1;other.position=Vector3(direction*0.05,0,0);other.facing=direction;other.start_special(Vector2.ZERO);other.teknium_magic.tick(0.20)
                        check(v.caught_by==m and other.teknium_magic.victim==null,"duplicate caster cannot stack capture")
                        m.cancel()
                    "resources":
                        v.basic_attack(Vector2.ZERO,false);v.start_special(Vector2.UP)
                        check(v.jumps_used==2 and v.recovery_spent and v.tackle_spent and v.float_remaining==0.4,"no hidden resource refresh")
                        check(v.freeze_remaining==0 and v.freeze_immunity==0,"caught is not freeze or immunity")
                        m.cancel()
                    "bot":m.cancel()
                check(v.caught_by==null,"immediate lifecycle release "+mode)
                check(v._visual_root.position==Vector3.ZERO,"restore restrained visual offset")
                if mode=="resources":check(v.get_node("VisualRoot/TekniumVisual").animation_player.is_playing(),"release resumes victim pose")
            if is_instance_valid(f):f.queue_free()
            v.queue_free();other.queue_free();await process_frame
    if failures==0:print("PASS: grab both facings, shield/team/range/freeze/immunity, interruptions, lifecycle, duplicates, resources, bots")
    quit(0 if failures==0 else 1)

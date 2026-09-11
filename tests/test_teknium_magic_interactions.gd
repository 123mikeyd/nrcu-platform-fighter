extends SceneTree
var failures:=0
func check(ok,message):
    if not ok:failures+=1;print("FAIL: ",message)
func _initialize():call_deferred("run")
func fighter(pos:Vector3,id="teknium"):
    var f=load("res://scripts/fighter.gd").new();f.character_id=id;root.add_child(f);f.set_physics_process(false);f.position=pos;return f
func obstacle(pos:Vector3,size:Vector3):
    var body=StaticBody3D.new();var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=size;col.shape=box;body.add_child(col);root.add_child(body);body.position=pos;return body
func run():
    for mode in ["shield","team","wall","floor","reflect","order","grabwall","closest"]:
        var f=fighter(Vector3.ZERO);var v=fighter(Vector3(3,0,0),"turbofit");var other=fighter(Vector3(5,0,0));var wall
        if mode=="shield":v.shielding=true
        if mode=="team":f.team_id=2;v.team_id=2
        if mode=="wall":wall=obstacle(Vector3(2,1.4,0),Vector3(0.15,2.8,3))
        if mode=="floor":wall=obstacle(Vector3(2.3,0.7,0),Vector3(0.5,1.6,3))
        if mode=="order":wall=obstacle(Vector3(4,1.4,0),Vector3(0.15,2.8,3))
        if mode=="grabwall":
            v.position.x=1.35;wall=obstacle(Vector3(0.8,1.2,0),Vector3(0.1,2.4,3))
        if mode=="closest":v.position.x=1.6;other.position.x=1.3
        await physics_frame;await process_frame
        if mode in ["grabwall","closest"]:
            f.start_special(Vector2.ZERO);f.teknium_magic.tick(0.20)
            if mode=="grabwall":check(v.caught_by==null,"terrain blocks arm reach even when hand crosses wall")
            else:check(other.caught_by==f.teknium_magic and v.caught_by==null,"closest eligible capsule only")
            f.cancel_magic()
        else:
            f.start_special(Vector2.RIGHT);f.teknium_magic.tick(0.25)
            var shot=get_nodes_in_group("projectiles")[0];shot.set_physics_process(false)
            if mode=="reflect":
                shot.position=Vector3(2.2,1,0);var before=shot.lifetime
                v.start_special(Vector2.DOWN)
                check(shot.source==v and shot.direction==-1,"real SoundOrb transfers allegiance and reverses force")
                check(shot.lifetime==before and shot.color==Color(0.82,0.94,1,0.12),"reflection retains TTL and pale force identity")
            for i in 70:
                shot._physics_process(1.0/120.0)
                if shot.is_queued_for_deletion():break
            match mode:
                "shield":check(is_equal_approx(v.damage_percent,2.8) and v.freeze_remaining==0,"shield applies normal projectile mitigation")
                "team":check(v.damage_percent==0 and other.damage_percent==8,"passes teammate then hits hostile")
                "wall","floor":check(v.damage_percent==0 and shot.is_queued_for_deletion(),"terrain/floor obstruction before hurtbody")
                "reflect":check(f.damage_percent==8 and v.damage_percent==0,"reflected force hits original caster")
                "order":check(v.damage_percent==8 and other.damage_percent==0,"near victim precedes farther wall")
            shot.queue_free()
        f.queue_free();v.queue_free();other.queue_free()
        if is_instance_valid(wall):wall.queue_free()
        await process_frame
    if failures==0:print("PASS: force shield/team/terrain/floor/contact ordering/SoundOrb reflection; grab terrain and closest victim")
    quit(0 if failures==0 else 1)

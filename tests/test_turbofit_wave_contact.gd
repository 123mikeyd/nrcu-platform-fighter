extends SceneTree
var failures := 0
func check(ok,message):
    if not ok: failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func fighter(pos:Vector3, team := -1):
    var f=load("res://scripts/fighter.gd").new();f.character_id="turbofit"
    root.add_child(f);f.set_physics_process(false);f.position=pos;f.team_id=team;return f
func shot(f):
    var s=load("res://scripts/turbofit_sound_wave.gd").new();s.source=f;root.add_child(s);s.position=f.position+Vector3(0.8,1,0);return s
func clean():
    for n in get_nodes_in_group("projectiles")+get_nodes_in_group("fighters")+get_nodes_in_group("test_walls"):n.queue_free()
    await process_frame
func run():
    for sign_x in [1.0,-1.0]:
        var f=fighter(Vector3.ZERO);var victim=fighter(Vector3(sign_x*3,0,0))
        await physics_frame;await process_frame
        var s=shot(f);s.direction=sign_x;s.position.x=sign_x*0.8
        for i in 28:await physics_frame;await process_frame
        check(victim.damage_percent==11,"real wave capsule contact both facings")
        check(not is_instance_valid(s),"one impact consumes wave")
        for i in 10:await physics_frame;await process_frame
        check(victim.damage_percent==11,"no repeated damage")
        await clean()
    var f=fighter(Vector3.ZERO,0);var ally=fighter(Vector3(1.4,0,0),0);var enemy=fighter(Vector3(3,0,0),1)
    await physics_frame;await process_frame
    shot(f)
    for i in 28:await physics_frame;await process_frame
    check(ally.damage_percent==0 and enemy.damage_percent==11,"overlapping ally excluded from sweep")
    await clean()
    f=fighter(Vector3.ZERO);enemy=fighter(Vector3(3,0,0));enemy.shielding=true
    await physics_frame;await process_frame
    shot(f)
    for i in 28:await physics_frame;await process_frame
    check(enemy.damage_percent==0,"shield absorbs pulse without damage")
    await clean()
    f=fighter(Vector3.ZERO);enemy=fighter(Vector3(3,0,0))
    var wall=StaticBody3D.new();wall.add_to_group("test_walls");var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(0.08,5,5);shape.shape=box;wall.add_child(shape);root.add_child(wall);wall.position=Vector3(2,1,0)
    await physics_frame;await process_frame
    var s=shot(f)
    for i in 28:await physics_frame;await process_frame
    check(enemy.damage_percent==0 and not is_instance_valid(s),"thin terrain blocks volume before enemy")
    await clean()
    f=fighter(Vector3.ZERO);enemy=fighter(Vector3(10,0,0))
    s=shot(f);s.set_physics_process(false);s._physics_process(0.7)
    enemy.position=s.position-Vector3.UP
    await physics_frame;await process_frame
    s._physics_process(0.05)
    check(enemy.damage_percent==0,"fading wave cannot hit even an overlapping hurtbody")
    await clean()
    # Real reflected collision changes team filtering, not only a source field.
    f=fighter(Vector3.ZERO,0);enemy=fighter(Vector3(4,0,0),1);ally=fighter(Vector3(1.5,0,0),1)
    await physics_frame;await process_frame
    s=shot(f);s.position=Vector3(2.4,1,0);s.reflect(enemy,Color.RED)
    for i in 26:await physics_frame;await process_frame
    check(f.damage_percent==11 and ally.damage_percent==0 and enemy.damage_percent==0,"reflected wave hits old owner and excludes new team")
    await clean()
    # Expanded outer volume connects beyond the old center ray.
    f=fighter(Vector3.ZERO);enemy=fighter(Vector3(3,0,0.85))
    await physics_frame;await process_frame
    shot(f)
    for i in 28:await physics_frame;await process_frame
    check(enemy.damage_percent==11,"growing visible radial pressure volume hits off-center capsule")
    await clean()
    if failures==0:print("PASS TurboFit wave real physics contact / teams / shield / terrain / fade")
    quit(1 if failures else 0)

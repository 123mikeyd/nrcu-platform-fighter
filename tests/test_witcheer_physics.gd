extends SceneTree
const OUT="res://.verification/evidence/witcheer_physics/"
var failures:=0
var checks:=0
var arena
var f
var v
var visual
var render:=false
func _initialize():call_deferred("run")
func check(ok: bool,msg: String):
    checks+=1
    if not ok:failures+=1;printerr("FAIL: "+msg)
func key(code: int,pressed: bool):
    var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
    Input.parse_input_event(e);Input.flush_buffered_events()
func frames(n: int):
    for i in n:await physics_frame
func release():
    for code in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_F,KEY_G,KEY_SPACE]:key(code,false)
func prepare(face: float=1.0, height: float=0.0):
    release()
    f.reset_fighter(Vector3(-2,height,0),true);v.reset_fighter(Vector3(-2+face*1.8,0,0),true)
    f.facing=face;f.set_physics_process(true);v.set_physics_process(false)
    await frames(4)
func shot(label: String):
    if not render:return
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(OUT+"kit_"+label+".png")
func press(code: int):
    key(code,true);await frames(2);key(code,false)
func run():
    render="--capture" in OS.get_cmdline_user_args()
    arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
    load("res://tools/play_witcheer.gd").configure(arena);arena.setup._start()
    f=arena.fighters[0];v=arena.fighters[1];visual=f.get_node("VisualRoot/WitcheerVisual")
    for other in arena.fighters:
        other.control_type="human";other.input_device=99;other.set_physics_process(false)
    f.input_device=-1
    f.set_physics_process(true)
    await frames(60)
    for face in [1.0,-1.0]:
        await prepare(face)
        check(f.is_grounded(),"real terrain support")
        await press(KEY_F)
        check(f.witcheer_clip=="HighKick" and v.damage_percent==0,"F commits source windup")
        await frames(25)
        check(v.damage_percent==8,"ground F actual contact both facings")
        check(visual.current_clip=="HighKick" and visual.model.rotation.y*face>0,"kick pose/yaw")
        await shot("kick_"+str(face))
        await frames(50)
        check(f.witcheer_clip.is_empty(),"ground attack ends")
        await prepare(face)
        key(KEY_S,true);await press(KEY_F);key(KEY_S,false);await frames(29)
        check(v.damage_percent==9,"S+F source sweep damages grounded target")
        await shot("sweep_"+str(face))
        await prepare(face)
        await press(KEY_SPACE);await frames(18);await press(KEY_F)
        check(f.witcheer_clip=="JumpPunch","real jump then F routes aerial")
        await frames(28)
        print("PUNCH PROBE face=",face," f=",f.position," victim=",v.position," elapsed=",f.witcheer_elapsed," damage=",v.damage_percent)
        check(v.damage_percent==9,"air punch hits standing target at real jump timing")
        await shot("punch_"+str(face))
        await frames(80)
        check(f.is_grounded() and f.witcheer_clip.is_empty(),"air attack real landing cancel")
        await prepare(face)
        key(KEY_D if face>0 else KEY_A,true);key(KEY_G,true);await frames(2);key(KEY_G,false);key(KEY_D if face>0 else KEY_A,false)
        check(f.witcheer_clip=="Toss" and get_nodes_in_group("projectiles").is_empty(),"side G delayed toss")
        await frames(12)
        check(v.damage_percent==0,"before toss release")
        await frames(5);await shot("toss_"+str(face));await frames(15)
        check(v.damage_percent==11,"real toss projectile contacts standing target")
        await prepare(face,2.0)
        f.position.x=-face*5;v.position.x=14
        var x: float=f.position.x
        var y: float=f.position.y
        key(KEY_W,true);await press(KEY_G);key(KEY_W,false)
        check(f.witcheer_clip=="AirSwim","up G swim route")
        await frames(32)
        check((f.position.x-x)*face>2,"swim moves horizontally both facings")
        await shot("swim_"+str(face))
        check(f.recovery_spent and f.position.y>y,"once-per-airtime swim spent and rises gently")
        await frames(90)
        check(f.witcheer_clip.is_empty(),"swim finite/landing")
        await prepare(face)
        f.position.x=-face*5;v.position.x=14
        var floor_y:float=f.position.y
        key(KEY_W,true);await press(KEY_G);key(KEY_W,false)
        print("GROUND SWIM ",face," clip=",f.witcheer_clip," spent=",f.recovery_spent," pos=",f.position," vel=",f.velocity," floor=",f.is_grounded()," cooldown=",f.attack_cooldown," lag=",f.landing_lag)
        check(f.witcheer_clip=="AirSwim" and f.recovery_spent and f.position.y>floor_y,"ground swim lifts without false reset")
        await frames(32);await shot("rise_"+str(face))
        check(f.recovery_spent,"air recovery still spent")
        await frames(190)
        check(f.is_grounded() and not f.recovery_spent,"real landing restores recovery")
        await prepare(face)
        v.position.x=f.position.x-face*1.7
        key(KEY_S,true);await press(KEY_G);key(KEY_S,false);await frames(29)
        check(v.damage_percent==0 and f.witcheer_absorbing,"down G dance has no clearing damage")
        await shot("dance_"+str(face));await frames(15)
        check(v.damage_percent==0,"no dance melee damage")
    await prepare()
    f.position.x=-5;v.position.x=14
    var takeoff_y:float=f.position.y
    key(KEY_W,true);await press(KEY_G);key(KEY_W,false)
    check(f.witcheer_clip=="AirSwim" and f.position.y>takeoff_y,"ground up G launches swim")
    await frames(220)
    check(f.is_grounded() and not f.recovery_spent,"ground-started swim refreshes only on landing")
    await prepare()
    await press(KEY_SPACE);await frames(5)
    key(KEY_W,true);await press(KEY_G);key(KEY_W,false)
    check(f.witcheer_clip=="AirSwim" and f.recovery_spent and f.jumps_used==2,"airborne W+G spends recovery")
    await prepare()
    await press(KEY_SPACE);await frames(5)
    key(KEY_S,true);await press(KEY_G);key(KEY_S,false)
    check(f.witcheer_clip=="Celebration" and f.witcheer_absorbing,"airborne S+G dances rather than drops")
    await prepare()
    await press(KEY_SPACE);await frames(5);await press(KEY_G)
    check(f.witcheer_clip=="Celebration" and not f.witcheer_absorbing,"airborne neutral G non-absorbing celebration")
    # Late descending air attack must land and cancel before strike.
    await prepare(1,0.3);f.velocity.y=-3
    await press(KEY_F);await frames(35)
    check(f.is_grounded() and f.witcheer_clip.is_empty() and v.damage_percent==0,"late aerial landing cancels pending hit")
    await prepare()
    await press(KEY_F);check(f.apply_freeze(v),"freeze interrupts")
    key(KEY_F,true);await frames(70)
    check(f.freeze_remaining==0 and f.witcheer_clip.is_empty(),"held F cannot auto-fire on thaw")
    key(KEY_F,false);await frames(2)
    v.position=Vector3(8,0,0)
    key(KEY_D,true);await frames(12)
    check(visual.current_clip=="Run" and visual.animation_player.is_playing(),"Run resumes after thaw")
    key(KEY_D,false)
    await prepare();await press(KEY_G);f.lose_stock();await frames(100)
    check(get_nodes_in_group("projectiles").is_empty(),"stock interruption prevents delayed shot")
    release();arena.show_setup();await frames(3)
    check(arena.setup.visible and not f.controls_enabled and f.witcheer_clip.is_empty(),"safe setup clears kit")
    await shot("ready_setup")
    arena.queue_free();await process_frame
    print(("PASS " if failures==0 else "FAIL ")+"WITCHEER KEYBOARD PHYSICS: %d checks, %d failures; rendered=%s"%[checks,failures,str(render)])
    quit(0 if failures==0 else 1)

extends SceneTree
var failures:=0
func check(ok,message):
    if not ok:failures+=1;print("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
    var f=load("res://scripts/fighter.gd").new();root.add_child(f);f.set_physics_process(false)
    var v=load("res://scripts/fighter.gd").new();root.add_child(v);v.set_physics_process(false);v.position=Vector3(1.35,0,0)
    await physics_frame;await process_frame
    f.start_special(Vector2.ZERO)
    check(not f.charging,"neutral press replaces charge")
    var m=f.get_node("TekniumMagic")
    if not m.has_method("start_grab"):
        check(false,"grab clock missing")
    else:
        m.tick(0.199);check(v.caught_by==null and v.damage_percent==0,"no capture/damage before24")
        m.tick(0.001);check(v.caught_by==m,"close capsule captured at24")
        check(v.damage_percent==0,"no button/contact damage")
        check(not v.try_jump(),"caught direct jump gate")
        m.tick(4.0/24.0);check(m.phase=="hold","startup reaches28")
        for i in 5:
            m.tick(0.25)
            if i==0:
                check(m.arcs.visible and m.get("arc_width") != null and m.get("arc_width") >= 0.018,"electric arcs have bounded visible-width strokes, not subpixel lines")
        check(m.phase=="ending" and v.damage_percent==10,"five nonstack hold-only ticks then ending")
        check(v.caught_by==m,"finishing retains until64")
        m.tick(4.0/24.0);check(v.caught_by==m,"not released before64")
        m.tick(1.0/24.0);check(v.caught_by==null,"release at64")
        check(v.damage_percent==10 and v.grab_immunity>0,"no finisher damage plus repeat immunity")
        m.tick(8.0/24.0);check(m.phase=="idle","finishes72")
    f.queue_free();v.queue_free();await process_frame
    var cooldown_probe=load("res://scripts/fighter.gd").new();root.add_child(cooldown_probe);cooldown_probe.set_physics_process(false)
    cooldown_probe.start_special(Vector2.ZERO);cooldown_probe.teknium_magic.tick(1.0)
    check(is_equal_approx(cooldown_probe.teknium_magic.cooldown,2.5),"cooldown advances once across phase boundary")
    cooldown_probe.queue_free();await process_frame
    if failures==0:print("PASS: delayed close grab, full hold loop, ticks and release64")
    quit(0 if failures==0 else 1)

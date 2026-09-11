extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok,message):
    if not ok:failures+=1;print("FAIL: ",message)
func key(code,down):
    var e=InputEventKey.new();e.keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func run():
    for controller in ["human","bot"]:
        var f=load("res://scripts/fighter.gd").new();f.player_index=3;root.add_child(f);f.set_physics_process(false)
        var v=load("res://scripts/fighter.gd").new();v.player_index=1;root.add_child(v);v.set_physics_process(false);v.position=Vector3(1.35,0,0)
        await physics_frame;await process_frame
        f.start_special(Vector2.ZERO);f.teknium_magic.tick(0.20)
        check(v.caught_by!=null,"captured input fixture")
        v.control_type=controller
        for code in [KEY_D,KEY_SPACE,KEY_F,KEY_G,KEY_E]:key(code,true)
        if controller=="bot":
            v._bot.timer=10;v._bot.intent={"left":false,"right":true,"up":false,"down":false,"jump":true,"attack":true,"special":true,"shield":true}
        await physics_frame
        v._physics_process(1.0/60.0)
        check(v.jumps_used==0 and v.last_move=="" and not v.shielding and v.teknium_magic.phase=="idle",controller+" captured attack/jump/special/shield gated")
        check(v.freeze_remaining==0 and v.freeze_immunity==0,controller+" caught has no freeze immunity")
        f.cancel_magic();v._physics_process(1.0/60.0)
        check(v.jumps_used==0 and v.teknium_magic.phase=="idle",controller+" held keys do not retrigger on release")
        check(v.velocity.y<0,controller+" gravity resumes after release")
        for code in [KEY_D,KEY_SPACE,KEY_F,KEY_G,KEY_E]:key(code,false)
        f.queue_free();v.queue_free();await process_frame
    var f=load("res://scripts/fighter.gd").new();root.add_child(f);f.set_physics_process(false)
    var v=load("res://scripts/fighter.gd").new();root.add_child(v);v.set_physics_process(false);v.position=Vector3(1.35,0,0)
    await physics_frame;await process_frame
    f.start_special(Vector2.ZERO);f.teknium_magic.tick(0.20);v.queue_free();await process_frame
    check(f.teknium_magic.phase=="idle" and f.teknium_magic.victim==null,"victim removal immediately releases caster")
    f.queue_free();await process_frame
    if failures==0:print("PASS: real caught keyboard and bot input latching, gravity, no freeze side effects, victim removal")
    quit(0 if failures==0 else 1)

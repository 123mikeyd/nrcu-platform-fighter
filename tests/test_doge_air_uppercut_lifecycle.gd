extends SceneTree
const F=preload("res://scripts/fighter.gd")
var failures:=0
func ck(ok: bool,msg: String):
    if not ok:failures+=1;printerr("FAIL: "+msg)
func _initialize():call_deferred("run")
func run():
    var dog=F.new();dog.character_id="doge_man";root.add_child(dog);dog.set_physics_process(false)
    var other=F.new();other.character_id="doge_man";other.player_index=2;root.add_child(other);other.set_physics_process(false)
    var caster=F.new();caster.player_index=3;root.add_child(caster);caster.set_physics_process(false)
    var v=dog._visual_root.get_node("DogeVisual")
    var duplicate=other._visual_root.get_node("DogeVisual")
    for sink in ["hit","freeze","disable","reset","stock","cancel","grab"]:
        dog.reset_fighter(Vector3(0,4,0),true)
        dog.velocity=Vector3.ZERO;dog.jumps_used=1;dog.recovery_spent=true
        dog.basic_attack(Vector2.UP,true);dog._update_move_visuals()
        ck(v.air_uppercut and not duplicate.air_uppercut,"independent duplicate state")
        ck(v.animation_player.get_animation("Uppercut")!=duplicate.animation_player.get_animation("Uppercut"),"independent clip resources")
        var pose:float=v.animation_player.current_animation_position
        if sink=="hit":dog.receive_hit(3,Vector3.UP,3)
        if sink=="disable":dog.controls_enabled=false
        if sink=="reset":dog.reset_fighter(Vector3(0,4,0),true)
        if sink=="stock":dog.lose_stock()
        if sink=="cancel":dog._cancel_doge_attack()
        if sink=="freeze":
            ck(dog.apply_freeze(caster),"freeze accepted")
            ck(is_equal_approx(v.animation_player.current_animation_position,pose) and not v.animation_player.is_playing(),"freeze retains exact contact pose")
            dog._thaw()
        if sink=="grab":
            caster.reset_fighter(Vector3(-1.35,4,0),true)
            caster.facing=1
            await physics_frame;await process_frame
            caster.start_special(Vector2.ZERO)
            caster.teknium_magic.tick(0.20+4.0/24.0+0.35)
            dog._update_move_visuals()
            ck(v.current_clip=="Electrocution","real electric grab replaces uppercut")
            caster.cancel_magic()
        dog._update_move_visuals()
        ck(not v.air_uppercut and v.current_clip!="Uppercut","no stale clip after "+sink)
        if sink in ["freeze","hit","cancel","grab"]:ck(dog.jumps_used==1 and dog.recovery_spent,"interruption does not refund air resources: "+sink)
    dog.queue_free();other.queue_free();caster.queue_free();await process_frame
    if failures==0:print("PASS Doge air uppercut interruption lifecycle and duplicate isolation")
    quit(1 if failures else 0)

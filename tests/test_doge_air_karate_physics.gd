extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
var records := []
func check(ok: bool, text: String):
    if not ok: failures += 1; printerr("FAIL: "+text)
func _initialize(): call_deferred("run")
func key(code: int, down: bool):
    var e := InputEventKey.new()
    e.keycode = code; e.pressed = down
    Input.parse_input_event(e); Input.flush_buffered_events()
func ticks(n: int):
    for i in n: await physics_frame; await process_frame
func point(v, name: String) -> Vector3:
    var s: Skeleton3D = v.model.find_children("*","Skeleton3D",true,false)[0]
    s.force_update_all_bone_transforms()
    return s.global_transform * s.get_bone_global_pose(s.find_bone(name)).origin
func run():
    var stage := Node3D.new(); root.add_child(stage)
    var floor := StaticBody3D.new(); floor.collision_layer = 2
    var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size=Vector3(28,1,4); shape.shape=box
    floor.position.y=-.5; floor.add_child(shape); stage.add_child(floor)
    var dog=F.new(); dog.character_id="doge_man"; stage.add_child(dog)
    var enemy=F.new(); enemy.character_id="ice_mage"; enemy.player_index=2; stage.add_child(enemy)
    var view=dog._visual_root.get_node("DogeVisual")
    for facing in [1.0,-1.0]:
        for delay in [2,12,24,32]:
            for distance in [0.9,1.2,1.6,2.5]:
                dog.reset_fighter(Vector3(0,.02,0),true); enemy.reset_fighter(Vector3(facing*distance,.02,0),true)
                dog.facing=facing
                await ticks(8)
                key(KEY_SPACE,true); await ticks(2); key(KEY_SPACE,false); await ticks(delay)
                check(not dog.is_grounded(),"real jump still airborne before S+F")
                key(KEY_S,true); key(KEY_F,true); await ticks(2)
                check(dog.doge_attack_clip=="AirDownKarate","real S+F route")
                key(KEY_S,false); key(KEY_F,false)
                var angles := []; var hit_elapsed := -1.0; var previous := 0.0
                for i in 40:
                    await ticks(1)
                    if dog.doge_attack_clip=="AirDownKarate" and dog.doge_attack_elapsed>=.25 and dog.doge_attack_elapsed<=.33001:
                        var v: Vector3=point(view,"RightFoot")-point(view,"RightUpLeg")
                        var angle: float=rad_to_deg(atan2(-v.y,Vector2(v.x,v.z).length()))
                        angles.append(angle); check(angle>=25 and angle<=35,"actual world hip/foot contact angle 25..35 both facings")
                        check(v.x*facing>0,"leg strikes facing-forward")
                    if enemy.damage_percent>previous:
                        hit_elapsed=dog.doge_attack_elapsed
                        check(hit_elapsed>=.25-.00001 and hit_elapsed<=.33001,"damage only in foot active window")
                    previous=enemy.damage_percent
                    if dog.is_grounded(): check(dog.doge_attack_clip!="AirDownKarate","terrain landing cancels kick")
                check(enemy.damage_percent<=10,"once per victim")
                if distance==2.5: check(enemy.damage_percent==0,"no invisible long reach")
                records.append({"facing":facing,"delay_ticks":delay,"distance":distance,"damage":enemy.damage_percent,"hit_elapsed":hit_elapsed,"angles":angles})
    for facing in [1.0,-1.0]:
        var hits:=0
        for r in records:
            if r.facing==facing and r.damage>0: hits+=1
        check(hits>=2,"real jump kick connects at multiple delays/spacings facing "+str(facing))
    for scenario in ["hit","freeze","grab","reset","setup","stock"]:
        dog.reset_fighter(Vector3(0,1,0),true);enemy.reset_fighter(Vector3(1.0,0,0),true)
        dog.set_physics_process(false);enemy.set_physics_process(false)
        dog.basic_attack(Vector2(1,1),true)
        match scenario:
            "hit":dog.receive_hit(1,Vector3.LEFT,1)
            "freeze":dog.apply_freeze(enemy)
            "grab":dog.cancel_for_grab()
            "reset":dog.reset_fighter(Vector3(0,1,0),true)
            "setup":dog.controls_enabled=false
            "stock":dog.lose_stock()
        dog._tick_character_move(.26);dog._query_doge_air_karate()
        check(enemy.damage_percent==0,"no ghost damage after "+scenario)
    var file:=FileAccess.open("res://.verification/evidence/doge_air_karate/physics_results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"failures":failures,"cases":records},"  "))
    stage.queue_free();await process_frame
    if failures==0:print("PASS real Space then S+F contact matrix, angle, range, once-only, landing and lifecycle")
    quit(1 if failures else 0)

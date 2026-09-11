extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var f=load("res://scripts/fighter.gd").new()
    f.character_id="ice_mage"
    root.add_child(f)
    f.set_physics_process(false)
    var v=f.get_node("VisualRoot/IceMageVisual")
    for clip in ["IceStrike", "IceCast"]:
        check(v.animation_player.has_animation(clip), "local authored " + clip + " imported")
    if failures:
        f.queue_free()
        await process_frame
        quit(1)
        return
    var rig: Skeleton3D=v.model.find_children("*","Skeleton3D",true,false)[0]
    for clip in ["IceStrike", "IceCast"]:
        v.animation_player.play(clip)
        v.animation_player.seek(0,true)
        var arm=rig.find_bone("RightArm")
        var before=rig.get_bone_pose_rotation(arm)
        v.animation_player.seek(0.2,true)
        check(before.angle_to(rig.get_bone_pose_rotation(arm))>0.2,clip+" actually articulates arm")
    var enemy=load("res://scripts/fighter.gd").new()
    enemy.character_id="ggb"
    root.add_child(enemy)
    enemy.set_physics_process(false)
    enemy.position=Vector3(1.3,0,0)
    f.basic_attack(Vector2.ZERO,false)
    check(enemy.damage_percent==0,"strike waits for visible windup")
    check(f.ice_attack_clip=="IceStrike","basic starts authored strike")
    f._tick_character_move(0.2)
    f._update_move_visuals()
    check(enemy.damage_percent==8 and v.current_clip=="IceStrike","strike impact synced to 0.2s pose")
    check(not f._attack_flash.visible,"no giant placeholder flash")
    f._tick_character_move(0.4)
    f.attack_cooldown=0
    f.start_special(Vector2.ZERO)
    check(f.ice_attack_clip=="IceCast","neutral special uses cast animation")
    f.receive_hit(1,Vector3.RIGHT,1)
    check(f.ice_attack_clip.is_empty(),"hit cancels authored attack")
    f.queue_free()
    enemy.queue_free()
    await process_frame
    if failures==0: print("PASS: authored IceStrike/IceCast bone motion, windup/impact, pose mapping, no flash, hit interruption")
    quit(1 if failures else 0)

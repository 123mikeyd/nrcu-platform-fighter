extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok:bool,message:String):
    if not ok:
        failures+=1
        printerr("FAIL: "+message)
func frames(n:int):
    for i in n:await physics_frame
    await process_frame
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.setup.rows[0].character.select(4)
    arena.setup._start()
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    var mage=arena.fighters[0]
    var victim=arena.fighters[1]
    for f in arena.fighters.slice(2):
        f.controls_enabled=false
        f.position=Vector3(14,8,0)
    victim.control_type="human"
    mage.position=Vector3(-3,0,0)
    victim.position=Vector3(1,0,0)
    await frames(25)
    var rig:Skeleton3D=victim.find_children("*","Skeleton3D",true,false)[0]
    var ap:AnimationPlayer=victim.find_children("*","AnimationPlayer",true,false)[0]
    victim.apply_freeze(mage)
    var before=[]
    for i in rig.get_bone_count(): before.append(rig.get_bone_pose_rotation(i))
    await frames(20)
    var changed=false
    for i in rig.get_bone_count():
        if before[i].angle_to(rig.get_bone_pose_rotation(i))>0.005:changed=true
    check(not changed and not ap.is_playing(),"frozen skeleton holds actual hit pose instead of continuing Idle")
    await frames(50)
    check(ap.is_playing(),"thaw resumes victim animation")
    victim.reset_fighter(Vector3(1,0,0))
    victim.apply_freeze(mage)
    victim.set_physics_process(false)
    arena.show_setup()
    check(victim._move_status.text!="FROZEN","setup immediately clears frozen text for stopped bodies")
    arena.start_match(arena.active_slots,false)
    arena._physics_process(arena.ready_remaining)
    mage=arena.fighters[0]
    victim=arena.fighters[1]
    for f in arena.fighters:f.set_physics_process(false)
    victim.apply_freeze(mage)
    for f in arena.fighters.slice(1):f.stocks=0
    arena._on_fighter_eliminated(victim)
    check(arena.match_over and victim.freeze_remaining==0 and not victim._frozen_shell.visible,"winner cleanup clears status and shell")
    arena._reset_match()
    arena._physics_process(arena.ready_remaining)
    check(victim.freeze_immunity==0 and victim.controls_enabled,"rematch resets immunity and controls")
    victim.apply_freeze(mage)
    victim.position=Vector3(0,-9,0)
    victim.set_physics_process(true)
    await frames(2)
    check(victim.stocks==2 and victim.freeze_remaining==0,"real physics blast zone clears frozen stock")
    arena.queue_free()
    await process_frame
    if failures==0:print("PASS: frozen skeleton pause/thaw, immediate text cleanup, winner/rematch and actual frozen blast-zone stock")
    quit(1 if failures else 0)

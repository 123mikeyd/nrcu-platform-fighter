extends SceneTree
var failures=0
func _initialize(): call_deferred("run")
func check(ok:bool,message:String):
    if not ok:
        failures+=1
        printerr("FAIL: "+message)
func key(code:int,down:bool):
    var e=InputEventKey.new()
    e.keycode=code
    e.pressed=down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.setup.rows[0].character.select(4)
    arena.setup._start()
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    check(arena.fighters.size()==4 and not arena.setup.visible,"actual setup Start creates four-player match")
    var mage=arena.fighters[0]
    check(mage.character_id=="ice_mage","Ice Mage chosen by setup")
    for other in arena.fighters.slice(1): other.set_physics_process(false)
    var visual=mage.get_node("VisualRoot/IceMageVisual")
    for i in 45: await physics_frame
    check(mage.is_on_floor() and visual.current_clip=="Idle","standing Idle on actual platform")
    var start=mage.position
    key(KEY_D,true)
    var walked=false
    for i in 22:
        await physics_frame
        if visual.current_clip=="Walk": walked=true
    check(walked and visual.current_clip=="Run" and mage.position.x>start.x+1,"actual D accelerates Walk then Run")
    key(KEY_D,false)
    for i in 30: await physics_frame
    check(visual.current_clip=="Idle" and mage.velocity.x==0,"release stops in animated Idle")
    key(KEY_A,true)
    for i in 18: await physics_frame
    check(mage.facing==-1 and visual.model.rotation.y<0 and mage._visual_root.scale==Vector3.ONE,"actual A faces left with yaw")
    key(KEY_A,false)
    for i in 30: await physics_frame
    key(KEY_SPACE,true)
    for i in 4: await physics_frame
    key(KEY_SPACE,false)
    check(not mage.is_on_floor() and visual.fallback_label=="Airborne: Idle fallback","real jump honestly uses Idle fallback")
    for i in 120: await physics_frame
    check(mage.is_on_floor() and absf(mage.position.y+0.05)<0.02,"feet origin returns to actual platform top")
    # Authored IceStrike has a real 0.2-second windup.
    var opponent=arena.fighters[1]
    opponent.position=mage.position+Vector3(1,0,0)
    mage.facing=1
    key(KEY_F,true)
    for i in 16: await physics_frame
    key(KEY_F,false)
    check(opponent.damage_percent==8 and visual.current_clip=="IceStrike" and visual.fallback_label.is_empty(),"authored palm strike with delayed impact")
    arena.show_setup()
    check(arena.setup.visible and not mage.controls_enabled,"return to setup safely freezes human")
    arena.queue_free()
    await process_frame
    if failures==0: print("PASS: Ice Mage actual Start, keyboard Walk Run Idle, left yaw, jump/landing collision, authored melee and safe setup")
    quit(1 if failures else 0)

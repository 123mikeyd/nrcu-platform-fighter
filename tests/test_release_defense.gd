extends SceneTree
var fails = 0
var checks = 0
var arena
var f
func _initialize(): call_deferred("run")
func frames(n):
    for i in n:
        await physics_frame
        await process_frame
func check(ok, message):
    checks += 1
    print(("PASS: " if ok else "FAIL: ")+message)
    if not ok: fails += 1
func key(code, down):
    var e = InputEventKey.new()
    e.keycode=code; e.physical_keycode=code; e.pressed=down
    Input.parse_input_event(e); Input.flush_buffered_events()
func run():
    var ids=load("res://scripts/match_config.gd").CHARACTERS
    for id in ids:
        arena=load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
        arena.setup.rows[0].character.select(ids.find(id)); arena.setup.rows[0].kind.select(0)
        arena.setup.rows[1].character.select(ids.find("teknium")); arena.setup.rows[1].kind.select(0)
        arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
        arena.setup._refresh(); arena.setup._start(); await frames(150)
        f=arena.fighters[0]
        key(KEY_E,true); key(KEY_D,true); await frames(3)
        check(not f.shielding and not f._shield_visual.visible and f.velocity.x>0,id+" retired shield no state/visual/movement lock")
        key(KEY_D,false); key(KEY_E,false)
        f.reset_fighter(Vector3(-2,0.2,0),true); await frames(20)
        if id=="mephisto":
            key(KEY_E,true); key(KEY_G,true); await frames(18)
            check(f.mephisto_moves.move=="Barrier" and f.mephisto_moves.magic().protected_window(),"ordinary G barrier survives retired E")
            var before=f.damage_percent; f.receive_hit(10,Vector3.RIGHT,3)
            check(f.damage_percent==before,"Mephisto barrier still prevents damage in active window")
            await frames(65)
            check(f.mephisto_moves.move.is_empty(),"Mephisto barrier expires while G held")
            f.receive_hit(10,Vector3.RIGHT,3)
            check(f.damage_percent==before+10,"expired barrier no universal defense")
        elif id=="doge_man":
            key(KEY_E,true); key(KEY_S,true); key(KEY_G,true); await frames(14)
            check(f.doge_counter.active(),"ordinary Down+G counter active with retired E")
            var before=f.damage_percent; f.receive_hit_from(10,Vector3.RIGHT,3,arena.fighters[1])
            check(f.damage_percent==before and f.doge_counter.phase!="stance","finite counter intercepts incoming hit")
            await frames(70); check(f.doge_counter.phase=="idle","counter expires with Special held")
        elif id=="turbofit":
            await frames(100) # allow native landing clip to finish before passive idle
            check(f._visual_root.get_node("TurboFitVisual").current_clip=="MoshIdleV004","ordinary Start retains installed MoshIdleV004")
            key(KEY_E,true); key(KEY_S,true); key(KEY_G,true); await frames(2)
            check(f.sound_orb_time>0 and not f.shielding,"ordinary Down+G sound orb distinct from retired shield")
        for code in [KEY_E,KEY_S,KEY_G]: key(code,false)
        arena.queue_free(); await frames(3)
    print("DEFENSE_COMPLETE checks=%d fails=%d"%[checks,fails]); quit(1 if fails else 0)

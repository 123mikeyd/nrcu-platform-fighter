extends SceneTree
var failures=0
var checks=0
func check(ok,text):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",text)
func _initialize():call_deferred("run")
func run():
 var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 load("res://tools/play_mephisto.gd").configure(arena);arena.setup.rows[1].character.select(load("res://scripts/match_config.gd").CHARACTERS.find("teknium"));arena.setup._start()
 for i in 210:await physics_frame
 var f=arena.fighters[0];var caster=arena.fighters[1]
 for a in [f,caster]:a.set_physics_process(false)
 var m=f.mephisto_moves
 for episode in ["RightSwipe","SmokeCharge","SmokeRelease","SwitchToGirl"]:
  for interrupt in ["hit","freeze","grab","reset","stock","disable","shield"]:
   f.reset_fighter(Vector3.ZERO,true);f.controls_enabled=true;f.hitstun=0;f.freeze_remaining=0;m.demon_form=true
   m.start_kit("SmokeCharge" if episode=="SmokeRelease" else episode,1)
   if episode=="SmokeRelease":f.charge_time=1;m.release()
   m.tick(.15)
   match interrupt:
    "hit":f.receive_hit(7,Vector3.RIGHT,3)
    "freeze":f.apply_freeze(caster)
    "grab":f.cancel_for_grab()
    "reset":f.reset_fighter(Vector3.ZERO,true)
    "stock":f.lose_stock()
    "disable":f.controls_enabled=false
    "shield":
     var key=InputEventKey.new();key.keycode=KEY_E;key.pressed=true;Input.parse_input_event(key);Input.flush_buffered_events();m.tick(.01)
     var up=InputEventKey.new();up.keycode=KEY_E;up.pressed=false;Input.parse_input_event(up);Input.flush_buffered_events()
   check(m.move.is_empty() and not f.charging,"cancel "+episode+" "+interrupt)
   check(f.attack_cooldown<2,"no permanent cooldown after "+episode+" "+interrupt)
   check(m.demon_form,"interrupted lower keeps committed lead")
   await process_frame
   check(get_nodes_in_group("mephisto_smoke").is_empty(),"no orphan smoke "+episode+" "+interrupt)
 print("PAIRED_LIFECYCLE_COMPLETE checks=",checks," failures=",failures)
 quit(1 if failures else 0)

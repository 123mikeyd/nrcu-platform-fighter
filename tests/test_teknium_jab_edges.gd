extends "res://tests/test_teknium_jab.gd"
func run():
 var a=load("res://scenes/main.tscn").instantiate();root.add_child(a);await process_frame
 var ids=load("res://scripts/match_config.gd").CHARACTERS
 a.setup.rows[0].character.select(ids.find("teknium"));a.setup.rows[0].kind.select(0)
 a.setup.rows[1].character.select(ids.find("doge_man"));a.setup.rows[1].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();await frames(150)
 var f=a.fighters[0];var p=a.fighters[1];var c=f.reaction_recovery
 for mode in ["shield","disabled","freeze","hit","support","reset","jump"]:
  for k in [KEY_F,KEY_E,KEY_SPACE]:key(k,false)
  f.controls_enabled=true;f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(1.2,0,0),true);await frames(20)
  key(KEY_F,true);await frames(3)
  check(c.lab_move=="jab" and p.damage_percent==0,"startup before cancellation "+mode)
  if mode=="shield":key(KEY_E,true)
  elif mode=="disabled":f.controls_enabled=false
  elif mode=="freeze":f.apply_freeze(p)
  elif mode=="hit":f.receive_hit(1,Vector3.RIGHT,1)
  elif mode=="support":f.global_position.y=4;f._floor_contacts_valid=false
  elif mode=="reset":f.reset_fighter(Vector3.ZERO,true)
  elif mode=="jump":key(KEY_F,false);key(KEY_SPACE,true)
  await frames(3)
  check(c.lab_move=="" and c.lab_targets.is_empty(),"cancellation clears pending jab "+mode)
  key(KEY_E,false);key(KEY_SPACE,false);f.controls_enabled=true
  if mode=="freeze":f._clear_freeze()
  await frames(60)
  check(p.damage_percent==0 and c.lab_move=="","no ghost hit or held restart "+mode)
  key(KEY_F,false);await frames(2)
 # Source time/recovery and independent fresh episodes via normal input.
 f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(1.2,0,0),true);await frames(20)
 key(KEY_F,true);await frames(1)
 check(is_equal_approx(c.lab_duration(),1.29166662693024/3.5),"complete native Punch at3.5x without extra recovery")
 await frames(7)
 check(p.damage_percent==0,"no damage before source extension")
 await frames(30);key(KEY_F,false);await frames(2)
 check(p.damage_percent==8,"first episode contact8")
 p.reset_fighter(Vector3(1.2,0,0),true);await frames(20)
 key(KEY_F,true);await frames(30);key(KEY_F,false)
 check(p.damage_percent==8,"fresh jab resets once-only ledger")
 f.reset_fighter(Vector3(0,4,0),true);p.reset_fighter(Vector3(8,0,0),true);await frames(2)
 key(KEY_F,true);await frames(2);key(KEY_F,false)
 check(c.lab_move=="" and f.last_move=="AIR STRIKE","air neutral stays original route")
 a.queue_free();await frames(2);quit(1 if fails else 0)

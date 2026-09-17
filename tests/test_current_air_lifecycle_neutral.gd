extends "res://tests/fixtures/current_air_routes.gd"
func run():
 for id in ["teknium","turbofit"]:
  if id=="ggb":continue
  var a=await setup_match(id);var f=a.fighters[0];var p=a.fighters[1];var c=f.humanoid_air_basic
  for reason in ["reset","freeze","disable","shield","hit","landing","face","held","repeat","grab","stock"]:
   for k in [KEY_SPACE,KEY_D,KEY_A,KEY_F,KEY_E]:key(k,false)
   f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(2.4,0,0),true);await frames(20)
   key(KEY_SPACE,true);await frames(1);key(KEY_SPACE,false);await frames(24 if reason=="landing" else 2)
   key(KEY_F,true);await frames(1);
   check(c.active,id+" started "+reason);var serial=c.serial
   if reason=="reset":f.reset_fighter(Vector3.ZERO,true)
   if reason=="freeze":f.freeze_remaining=1
   if reason=="disable":f.controls_enabled=false
   if reason=="shield":key(KEY_E,true)
   if reason=="hit":f.receive_hit(1,Vector3.LEFT,1)
   if reason=="face":key(KEY_A,true)
   if reason=="grab":f.cancel_for_grab()
   if reason=="stock":f.lose_stock()
   if reason=="repeat":key(KEY_F,false);await frames(1);key(KEY_F,true)
   await frames(3)
   if reason=="face":check(f.facing==1,id+" facing latched")
   elif reason not in ["landing","held","repeat"]:check(not c.active and c.targets.is_empty(),id+" cancel "+reason)
   await frames(70)
   check(not c.active and c.targets.is_empty(),id+" eventual cleanup "+reason)
   check(c.serial==serial,id+" no held/repeat restart "+reason)
   check(p.damage_percent==0,id+" no ghost distant damage "+reason)
   if reason=="reset":check(f.reaction_recovery==null or f.reaction_recovery.lab_move.is_empty(),id+" no phantom ground jab after reset")
   rows.append({"id":id,"reason":reason,"serial_unchanged":c.serial==serial,"clear":not c.active and c.targets.is_empty()})
  for k in [KEY_SPACE,KEY_D,KEY_A,KEY_F,KEY_E]:key(k,false)
  a.queue_free();await frames(2)
 var file=FileAccess.open(OUT+"neutral_lifecycle.json",FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
 print("COMPLETE LIFECYCLE ",rows.size()," failures ",fails);quit(1 if fails else 0)

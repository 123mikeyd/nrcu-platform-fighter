extends SceneTree
const OUT="res://.verification/evidence/latest/"
var fails=0;var checks=0
func _initialize():call_deferred("run")
func ck(ok,msg):
 checks+=1;print(("PASS " if ok else "FAIL ")+msg)
 if not ok:fails+=1
func frames(n):
 for i in n:await physics_frame;await process_frame
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func run():
 root.unfocusable=true
 var a=load("res://scenes/main.tscn").instantiate();root.add_child(a);await process_frame
 var ids=load("res://scripts/match_config.gd").CHARACTERS
 for i in 2:a.setup.rows[i].character.select(ids.find("witcheer" if i==0 else "doge_man"));a.setup.rows[i].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();await frames(150)
 var f=a.fighters[0];var p=a.fighters[1];var v=f.get_node("VisualRoot/WitcheerVisual")
 for face in [-1,1]:
  for gap in [.85,1.15,2.5]:
   f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(-face*gap,0,0),true);await frames(20);f.facing=face
   key(KEY_D if face<0 else KEY_A,true);key(KEY_F,true);await frames(2);key(KEY_D if face<0 else KEY_A,false);key(KEY_F,false)
   var first=-1.0
   for tick in 110:
    await frames(1)
    if first<0 and p.damage_percent>0:first=f.witcheer_elapsed
   print("CONTACT ",face," gap ",gap," damage ",p.damage_percent," first_time ",first)
   ck(p.damage_percent==(0 if gap==2.5 else 8),"foot-only contact/miss face "+str(face)+" gap "+str(gap))
   if first>=0:ck(first>=.375 and first<=.65,"damage confined to source68..74")
 # Airborne contact uses the same actual foot volume while both bodies fall.
 for face in [-1,1]:
  f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(-face*.85,0,0),true);await frames(20);f.facing=face
  f.position.y=9;p.position.y=9;f.velocity=Vector3.ZERO;p.velocity=Vector3.ZERO;await frames(2)
  key(KEY_D if face<0 else KEY_A,true);key(KEY_F,true);await frames(2);key(KEY_D if face<0 else KEY_A,false);key(KEY_F,false)
  ck(f.witcheer_clip=="TurnaroundKick" and not f.is_grounded(),"actual airborne contact setup "+str(face))
  await frames(45)
  ck(p.damage_percent==8,"actual airborne foot contact "+str(face))
  await frames(65)
 # Both chord keys held: no auto-facing override during native spin and no repeat.
 f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(5,0,0),true);await frames(20);f.facing=1
 key(KEY_A,true);key(KEY_F,true);await frames(35)
 ck(f.witcheer_clip=="TurnaroundKick" and f.facing==1,"held direction does not double flip")
 await frames(80)
 ck(f.witcheer_clip.is_empty() and f.facing==-1,"held entire chord finishes once")
 key(KEY_A,false);key(KEY_F,false);await frames(2)
 # interruption sinks and held-edge suppression
 for cause in ["hit","freeze","disable","stock"]:
  f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(5,0,0),true);await frames(20);f.facing=1
  key(KEY_A,true);key(KEY_F,true);await frames(2);key(KEY_A,false)
  ck(f.witcheer_clip=="TurnaroundKick","interrupt setup "+cause)
  if cause=="hit":f.receive_hit(1,Vector3.UP,2)
  elif cause=="freeze":f.apply_freeze(p)
  elif cause=="disable":f.controls_enabled=false
  else:f.lose_stock()
  await frames(2);ck(f.witcheer_clip.is_empty(),"cancel pending kick "+cause)
  await frames(120);ck(f.witcheer_clip.is_empty() and p.damage_percent==0,"no ghost hit or held restart "+cause)
  key(KEY_F,false);await frames(2)
 print("TOTAL ",checks," FAIL ",fails)
 a.queue_free();await frames(3);quit(1 if fails else 0)

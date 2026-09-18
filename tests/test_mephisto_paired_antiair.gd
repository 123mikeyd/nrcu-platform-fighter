extends SceneTree
const OUT="res://.verification/evidence/latest/"
func _initialize():call_deferred("run")
func key(k,p):
 var e=InputEventKey.new();e.keycode=k;e.pressed=p;Input.parse_input_event(e)
func frames(n):
 for i in n:await physics_frame;await process_frame
func run():
 var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 load("res://tools/play_mephisto.gd").configure(arena);arena.setup._start();await frames(210)
 var f=arena.fighters[0];var t=arena.fighters[1];var rows=[]
 for face in [1.0,-1.0]:
  for delay in [0,5,9,12,15]:
   f.reset_fighter(Vector3(-8,.1,0),true);t.reset_fighter(Vector3(8,.1,0),true);await frames(8)
   f.reset_fighter(Vector3(0,.1,0),true);t.reset_fighter(Vector3(face*1.12,.1,0),true);f.mephisto_moves.demon_form=true;f.facing=face;await frames(25)
   key(KEY_W,true);key(KEY_F,true);await frames(2);key(KEY_W,false);key(KEY_F,false);await frames(delay)
   key(KEY_ENTER,true);key(KEY_LEFT if face>0 else KEY_RIGHT,true);await frames(15);key(KEY_ENTER,false);key(KEY_LEFT if face>0 else KEY_RIGHT,false)
   await frames(55)
   var row={"face":face,"jump_delay_frames":delay,"damage":t.damage_percent,"contacts":f.mephisto_moves.contacts.duplicate(true)};rows.append(row);print("ANTI_AIR_ROW ",JSON.stringify(row))
 var file=FileAccess.open(OUT+"anti_air.json",FileAccess.WRITE);file.store_string(JSON.stringify(rows," "));file.close()
 var failures=0
 for r in rows:
  if r.damage!=9.0 or r.contacts.size()!=1:failures+=1
 if rows.size()!=10:failures+=1
 print("PAIRED_ANTI_AIR_COMPLETE rows=",rows.size()," failures=",failures)
 if failures:printerr("FAIL: ordinary jumping opponent anti-air")
 quit(1 if failures else 0)

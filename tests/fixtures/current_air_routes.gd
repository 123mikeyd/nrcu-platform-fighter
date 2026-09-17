extends SceneTree
var fails=0
var rows=[]
const OUT="res://.verification/evidence/current_air/"
func _initialize():call_deferred("run")
func frames(n):
 for i in n:await physics_frame;await process_frame
func check(ok,msg):
 print(("PASS: " if ok else "FAIL: ")+msg)
 if not ok:fails+=1
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func setup_match(id,slot=0):
 var a=load("res://scenes/main.tscn").instantiate();root.add_child(a);await process_frame
 var ids=load("res://scripts/match_config.gd").CHARACTERS
 for i in 2:
  a.setup.rows[i].character.select(ids.find(id if i==slot else "doge_man"));a.setup.rows[i].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();await frames(150)
 return a
func run():
 var ids=load("res://scripts/roster.gd").ids()
 for id in ids:
  if id=="ggb":continue
  for slot in [0,1]:
   var a=await setup_match(id,slot);var f=a.fighters[slot];var p=a.fighters[1-slot]
   for face in [-1,1]:
    var direction=KEY_NONE
    var jump=KEY_SPACE if slot==0 else KEY_ENTER;var basic=KEY_F if slot==0 else KEY_K
    f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(face*2.4,0,0),true);f.facing=face;await frames(20)
    key(jump,true);await frames(1);key(jump,false);await frames(1)
    check(not f.is_grounded(),id+" normal jump")
    key(basic,true);await frames(1)
    var c=f.get_node_or_null("HumanoidAirBasic")
    var started=c!=null and c.active
    check(started,id+" P"+str(slot+1)+" neutral kick "+str(face))
    check(p.damage_percent==0,id+" harmless input edge")
    key(basic,false);await frames(70)
    check(c!=null and not c.active,id+" cleanup")
    rows.append({"id":id,"slot":slot,"face":face,"started":started,"edge_damage":p.damage_percent})
   a.queue_free();await frames(2)
 var file=FileAccess.open(OUT+"routes.json",FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
 print("COMPLETE ROUTES ",rows.size()," failures ",fails);quit(1 if fails else 0)

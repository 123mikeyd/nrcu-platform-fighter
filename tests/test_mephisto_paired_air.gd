extends SceneTree
var failures=0
func check(ok,text):
 if not ok:failures+=1;printerr("FAIL: ",text)
func key(k,p):
 var e=InputEventKey.new();e.keycode=k;e.pressed=p;Input.parse_input_event(e)
func frames(n):
 for i in n:await physics_frame;await process_frame
func _initialize():call_deferred("run")
func run():
 var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 load("res://tools/play_mephisto.gd").configure(arena);arena.setup._start();await frames(210)
 var f=arena.fighters[0];var m=f.mephisto_moves
 for form in [false,true]:
  for dir in [0,KEY_D,KEY_W,KEY_S]:
   f.reset_fighter(Vector3(0,.1,0),true);m.demon_form=form;await frames(20)
   key(KEY_SPACE,true);await frames(4);key(KEY_SPACE,false)
   check(not f.is_grounded(),"ordinary jump in each lead")
   if dir:key(dir,true)
   key(KEY_F,true);await frames(3);key(KEY_F,false)
   if dir:key(dir,false)
   check(not m.move.is_empty() if form else (f.humanoid_air_basic.active or f.humanoid_air_side.active),"native-compatible aerial route")
   await frames(110);check(m.move.is_empty(),"bounded aerial completes")
 f.reset_fighter(Vector3(0,.1,0),true);m.demon_form=true;await frames(20)
 key(KEY_W,true);key(KEY_G,true);await frames(8)
 check(f.recovery_spent,"up-special reserves recovery throughout grounded windup")
 key(KEY_W,false);key(KEY_G,false);await frames(25)
 check(f.recovery_spent and not f.is_grounded(),"native paired recovery leaves ground with spent resource")
 print("PAIRED_AIR_COMPLETE failures=",failures);quit(1 if failures else 0)

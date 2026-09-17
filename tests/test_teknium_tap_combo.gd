extends SceneTree
var fails=0
func _initialize():call_deferred("run")
func frames(n):
 for i in n:await physics_frame;await process_frame
func check(ok,msg):
 print(("PASS: " if ok else "FAIL: ")+msg)
 if not ok:fails+=1
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func run():
 var a=load("res://scenes/main.tscn").instantiate();root.add_child(a);await process_frame
 var ids=load("res://scripts/match_config.gd").CHARACTERS
 a.setup.rows[0].character.select(ids.find("teknium"));a.setup.rows[0].kind.select(0)
 a.setup.rows[1].character.select(ids.find("doge_man"));a.setup.rows[1].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();await frames(150)
 var f=a.fighters[0];var p=a.fighters[1];var c=f.reaction_recovery
 f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(8,0,0),true);await frames(20)
 key(KEY_D,true);key(KEY_F,true);await frames(2);key(KEY_D,false)
 check(c.lab_move=="side_basic","normal Start and side chord enters side basic")
 check(c.lab_duration()<.6,"first button plays only first punch at faster playback")
 await frames(40)
 check(c.lab_move=="","one held press cannot play punches two or three")
 check(f.attack_cooldown<=0,"short first-strike recovery completes")
 key(KEY_F,false);await frames(2)
 f.reset_fighter(Vector3.ZERO,true);await frames(12)
 key(KEY_D,true);key(KEY_F,true);await frames(2);key(KEY_D,false);key(KEY_F,false);await frames(3)
 key(KEY_F,true);await frames(2)
 check(c.side_step==0,"early followup buffers without skipping first strike")
 await frames(16)
 check(c.side_step==1 and c.lab_move=="side_basic","second fresh neutral press advances to second punch")
 await frames(25)
 check(c.side_step!=2,"holding second press never buys third punch")
 key(KEY_F,false);await frames(20)
 f.reset_fighter(Vector3.ZERO,true);await frames(12)
 key(KEY_D,true);key(KEY_F,true);await frames(2);key(KEY_D,false);key(KEY_F,false);await frames(3)
 key(KEY_F,true);await frames(2);key(KEY_F,false);await frames(18)
 key(KEY_F,true);await frames(2);key(KEY_F,false);await frames(18)
 check(c.side_step==2 and c.lab_move=="side_basic","third separate neutral press advances to third punch")
 await frames(40)
 check(c.lab_move=="" and f.attack_cooldown<=0,"three punches end with short recovery")
 # Bounded post-recovery window, timeout, and cancelled buffers.
 for mode in ["late","timeout","shield","disabled","freeze","hit","support","reset"]:
  for k in [KEY_D,KEY_F,KEY_E]:key(k,false)
  f.controls_enabled=true;f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(8,0,0),true);await frames(15)
  key(KEY_D,true);key(KEY_F,true);await frames(2);key(KEY_D,false);key(KEY_F,false)
  if mode=="late" or mode=="timeout":
   await frames(21 if mode=="late" else 40)
   key(KEY_F,true);await frames(2);key(KEY_F,false)
   check(c.side_step==1 and c.lab_move=="side_basic" if mode=="late" else c.lab_move=="jab","neutral late continuation bounded "+mode)
  else:
   await frames(3);key(KEY_F,true);await frames(2)
   if mode=="shield":key(KEY_E,true)
   elif mode=="disabled":f.controls_enabled=false
   elif mode=="freeze":f.apply_freeze(p)
   elif mode=="hit":f.receive_hit(1,Vector3.RIGHT,1)
   elif mode=="support":f.global_position.y=4
   elif mode=="reset":f.reset_fighter(Vector3.ZERO,true)
   f.last_move=""
   await frames(3);key(KEY_E,false);f.controls_enabled=true
   if mode=="freeze":f._clear_freeze()
   await frames(40)
   check(c.lab_move=="" and c.side_chain_remaining==0 and not c.side_buffered,"cancel removes followup "+mode)
   check(f.last_move=="","held cancelled button cannot become automatic neutral jab "+mode)
  key(KEY_F,false);await frames(40)
 # One-slot buffer: two extra presses in strike1 cannot reserve strike3.
 f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(8,0,0),true);await frames(15)
 key(KEY_D,true);key(KEY_F,true);await frames(2);key(KEY_D,false);key(KEY_F,false);await frames(3)
 for i in 2:
  key(KEY_F,true);await frames(2);key(KEY_F,false);await frames(2)
 await frames(12)
 check(c.side_step==1,"multiple early edges reserve only one followup")
 await frames(45)
 check(c.lab_move=="" and c.side_step!=2,"no queued third punch from first-strike spam")
 # Source contact windows and faster per-strike recovery are clock mapped.
 for step in 3:
  c.side_step=step;c.lab_move="side_basic"
  check(is_equal_approx(c.side_source_time(0),(c.SIDE_STARTS[step]-81)/30.0),"exact source start "+str(step))
  check(is_equal_approx(c.side_source_time(c.lab_duration()),((176.0 if step==2 else c.SIDE_ENDS[step])-81.0)/30.0),"exact source endpoint "+str(step))
  check(c.lab_duration()<.57,"faster bounded strike duration "+str(step))
  check(not c.lab_active(c.lab_duration()),"recovery cannot damage "+str(step))
 c.clear()
 # Airborne and vertical branches remain distinct; diagonal up is uppercut.
 f.reset_fighter(Vector3.ZERO,true);await frames(15)
 key(KEY_W,true);key(KEY_D,true);key(KEY_F,true);await frames(2)
 check(c.lab_move=="uppercut" and is_equal_approx(c.lab_duration(),.6733333333),"up wins diagonal, original uppercut retained")
 for k in [KEY_W,KEY_D,KEY_F]:key(k,false)
 await frames(50)
 f.reset_fighter(Vector3(0,4,0),true);await frames(2)
 key(KEY_D,true);key(KEY_F,true);await frames(2)
 check(c.lab_move=="" and f.last_move=="AIR STRIKE","air side route not replaced by ground combo")
 for k in [KEY_D,KEY_F]:key(k,false)
 a.queue_free();await frames(2);quit(1 if fails else 0)

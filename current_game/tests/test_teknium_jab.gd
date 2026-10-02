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
 var f=a.fighters[0];var p=a.fighters[1];var c=f.reaction_recovery;var view=f.get_node("VisualRoot/TekniumVisual");var rows=[]
 for face in [-1,1]:
  for gap in [.96,2.4,2.6]:
   f.reset_fighter(Vector3.ZERO,true);p.reset_fighter(Vector3(face*gap,0,0),true);f.facing=face;p.facing=-face;await frames(20)
   var start_frame=Engine.get_physics_frames()
   key(KEY_F,true);await frames(1)
   var row={"facing":face,"gap":gap,"first_callback_damage":p.damage_percent,"physics_ticks":Engine.get_physics_frames()-start_frame,"clip":view.current_clip,"source_seconds":view.animation_player.current_animation_position,"duration":view.animation_player.get_animation("Punch").length,"speed":view.animation_player.speed_scale,"hand_world":str(view.hand_tip("LeftHand")),"target_origin":str(p.global_position),"lab_move":c.lab_move}
   check(p.damage_percent==0,"no first callback damage "+str(face)+str(gap))
   await frames(25);key(KEY_F,false);await frames(2)
   row["held_damage"]=p.damage_percent;rows.append(row);print("JAB ",row)
   check(p.damage_percent==8 if gap==.96 else p.damage_percent==0,"contact-only held result "+str(face)+str(gap))

 a.queue_free();await frames(2);quit(1 if fails else 0)

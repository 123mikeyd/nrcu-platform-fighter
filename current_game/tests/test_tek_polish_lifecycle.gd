extends SceneTree
var a
var failures=0
var checks=0
func _initialize():call_deferred("run")
func check(ok:bool,msg:String):
 checks+=1;print(("PASS " if ok else "FAIL ")+msg)
 if not ok:failures+=1
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func release():
 for k in [KEY_S,KEY_F,KEY_SPACE,KEY_G,KEY_A,KEY_D]:key(k,false)
func ticks(n:int):
 for i in n:await physics_frame;a._physics_process(1.0/60);await process_frame
func air_reset():
 release();a.reset_fighter(Vector3(0,10,0),true);await ticks(1)
func run():
 var floor_body=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,5);shape.shape=box;floor_body.position.y=-.5;floor_body.add_child(shape);root.add_child(floor_body)
 a=load("res://scripts/fighter.gd").new();a.character_id="teknium";a.player_index=1;root.add_child(a);a.set_physics_process(false)
 var air=a.humanoid_air_basic
 for face in [-1,1]:
  await air_reset();a.facing=face;key(KEY_S,true);key(KEY_F,true);await ticks(1)
  check(air.active and air.move=="down","fresh down basic activates "+str(face))
  key(KEY_A if face>0 else KEY_D,true);await ticks(5)
  check(a.facing==face,"air facing remains captured while steering")
  var s=air.serial;await ticks(100)
  check(not air.active and air.serial==s,"hold cannot restart after landing or expiry")
  release();await ticks(2);a.reset_fighter(Vector3.ZERO,true);await ticks(20);key(KEY_S,true);await ticks(35);key(KEY_F,true);await ticks(1)
  check(a.get_node("VisualRoot/TekniumVisual").current_clip=="polish/CrouchKick","new ground route")
  a.receive_hit(4,Vector3(face,.3,0),3);await ticks(2)
  check(a.get_node("VisualRoot/TekniumVisual").current_clip!="polish/CrouchKick","hit interrupts crouch presentation")
 for interrupt in ["hit","freeze","controls","reset","ko","landing"]:
  await air_reset();key(KEY_S,true);key(KEY_F,true);await ticks(2)
  check(air.active,"air setup "+interrupt)
  match interrupt:
   "hit":a.receive_hit(4,Vector3(1,.2,0),3)
   "freeze":a.freeze_remaining=.3
   "controls":a.controls_enabled=false
   "reset":a.reset_fighter(Vector3.ZERO,true)
   "ko":a.lose_stock()
   "landing":a.position.y=.005;a.velocity=Vector3(0,-10,0)
  await ticks(3)
  check(not air.active,"down-air cancels "+interrupt)
  check(air.targets.is_empty(),"ledger clears "+interrupt)
  if interrupt!="hit":check(a.attack_cooldown<=0,"cooldown clears "+interrupt)
 for gate in ["ground","hit","freeze","controls","special","cooldown"]:
  await air_reset()
  match gate:
   "ground":a.reset_fighter(Vector3.ZERO,true);await ticks(20)
   "hit":a.hitstun=.3
   "freeze":a.freeze_remaining=.3
   "controls":a.controls_enabled=false
   "special":a.teknium_specials.phase="rise_charge"
   "cooldown":a.attack_cooldown=.3
  a.basic_attack(Vector2.DOWN,gate!="ground")
  check(not air.active,"ordinary basic dispatch rejects air route: "+gate)
 # Baked ground foot lock and exact endpoint; fractional sampling catches interpolation drift.
 release();a.reset_fighter(Vector3.ZERO,true);await ticks(20)
 var view=a.get_node("VisualRoot/TekniumVisual");var sk:Skeleton3D=a.crouch_pose.skeleton
 var ankle=sk.find_bone("LeftFoot");var toe=sk.find_bone("LeftToeBase")
 view.present_crouch_kick(0,1)
 var reference=sk.global_transform*sk.get_bone_global_pose(ankle).origin
 var toe_start=sk.global_transform*sk.get_bone_global_pose(toe).origin
 var max_ankle=0.0;var max_toe=0.0
 for i in 193:
  view.present_crouch_kick(.32*i/192,1);sk.force_update_all_bone_transforms()
  max_ankle=maxf(max_ankle,reference.distance_to(sk.global_transform*sk.get_bone_global_pose(ankle).origin))
  max_toe=maxf(max_toe,toe_start.distance_to(sk.global_transform*sk.get_bone_global_pose(toe).origin))
 check(max_ankle<.001,"dense support ankle drift %.8f"%max_ankle)
 print("SUPPORT TOE rotation residual m=",max_toe," (native ankle rotation retained; not a sole-vertex lock)")
 for b in sk.get_bone_count():
  check(sk.get_bone_pose(b).is_equal_approx(a.crouch_pose.endpoint[b]),"ground endpoint "+sk.get_bone_name(b))
 a.queue_free();await process_frame;await process_frame
 print("TEK_POLISH_LIFECYCLE_COMPLETE checks=",checks," failures=",failures);print("TEK_POLISH_LIFECYCLE_COMPLETE");quit(1 if failures else 0)

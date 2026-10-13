extends SceneTree
const OUT="user://"
const DT=1.0/60.0
var dog
var foe
var checks=0
var failures=[]
var rows=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func key(code:int,pressed:bool):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed;Input.parse_input_event(e);Input.flush_buffered_events()
func tick(n:int=1):
 for i in n:
  await physics_frame
  dog._physics_process(DT);foe._physics_process(DT)
func fresh(face:float=1.0,gap:float=1.25,pid:int=1):
 for code in [KEY_G,KEY_L,KEY_F,KEY_K,KEY_W,KEY_S,KEY_A,KEY_D,KEY_SPACE,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_ENTER]:key(code,false)
 dog.player_index=pid
 dog.reset_fighter(Vector3(-8,.1,0),true);foe.reset_fighter(Vector3(8,.1,0),true)
 await tick(10)
 dog.reset_fighter(Vector3(0,.02,0),true);foe.reset_fighter(Vector3(face*gap,.02,0),true)
 dog.facing=face;foe.facing=-face
 await tick(15)
 check(dog.is_grounded() and foe.is_grounded(),"fixture grounded")
 dog.doge_super_punch.contacts.clear()
func press():
 key(KEY_G if dog.player_index==1 else KEY_L,true)
 await tick()
func run():
 Engine.physics_ticks_per_second=60
 var floor_body=StaticBody3D.new();var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,10);col.shape=box;floor_body.position.y=-.5;floor_body.add_child(col);root.add_child(floor_body)
 var F=load("res://scripts/fighter.gd")
 dog=F.new();dog.character_id="doge_man";dog.position=Vector3(-8,.1,0);root.add_child(dog);dog.set_physics_process(false)
 foe=F.new();foe.character_id="teknium";foe.player_index=2;foe.control_type="dummy";foe.position=Vector3(8,.1,0);root.add_child(foe);foe.set_physics_process(false)
 await tick(20)
 for face in [1.0,-1.0]:
  for pid in [1,2]:
   for gap in [1.1,1.3,2.0,5.0,-2.0]:
    await fresh(face,gap,pid)
    var actual=absf(foe.position.x-dog.position.x)
    await press()
    check(dog.doge_super_punch.active and not dog.charging,"fresh neutral input starts")
    key(KEY_G if pid==1 else KEY_L,false)
    await tick(50)
    check(foe.damage_percent==0,"harmless through tick51")
    await tick(90)
    var damage=foe.damage_percent
    var contacts=dog.doge_super_punch.contacts.duplicate(true)
    rows.append({"face":face,"player":pid,"gap":gap,"actual_gap":actual,"damage":damage,"contacts":contacts})
    check(damage in [0.0,25.0],"single hit damage only")
    if gap>=2 or gap<0:check(damage==0,"separated/behind miss")
    check(not dog.doge_super_punch.active,"finite completion")
 var hits=0
 for row in rows:
  if row.damage>0:hits+=1
 check(hits>=4,"ordinary-spacing actual contacts both players/facings")
 # Moving-opponent witnesses use real P2 movement throughout the startup.
 var moving=[]
 for behavior in ["approach","escape"]:
  await fresh(1,3.0 if behavior=="approach" else 1.3)
  foe.control_type="human";foe.player_index=2
  await press();key(KEY_G,false);key(KEY_LEFT if behavior=="approach" else KEY_RIGHT,true)
  await tick(90)
  moving.append({"behavior":behavior,"damage":foe.damage_percent,"contacts":dog.doge_super_punch.contacts.duplicate(true)})
  if behavior=="escape":check(foe.damage_percent==0,"moving opponent escapes startup")
  else:check(foe.damage_percent==25,"moving opponent approaches into contact")
  foe.control_type="dummy"
 # Exact clock and held input, miss avoids hitlag.
 await fresh(1,6)
 await press()
 check(is_equal_approx(dog.doge_super_punch.elapsed,DT),"input callback represents frame1 t0")
 await tick(101)
 check(dog.doge_super_punch.active,"committed through frame102")
 check(not dog.try_jump(),"no jump cancel")
 dog.basic_attack(Vector2.ZERO,false);check(dog.doge_ground_basic.clip.is_empty(),"no basic cancel")
 dog.start_special(Vector2.UP);check(not dog.air_doge.active(),"no recovery-special cancel")
 await tick()
 check(dog.doge_super_punch.active and not dog.doge_super_punch.committed(),"frame103 ends ownership before104")
 key(KEY_G,false);key(KEY_F,true)
 await tick()
 check(not dog.doge_super_punch.active and not dog.doge_ground_basic.clip.is_empty(),"fresh basic accepted on104")
 await fresh(1,6);await press();var serial=dog.doge_super_punch.serial
 await tick(160);check(dog.doge_super_punch.serial==serial and not dog.doge_super_punch.active,"held special never repeats")
 for mode in ["hit","freeze","grab","stock","reset","disable","support"]:
  await fresh(1,6);await press();await tick(20)
  if mode=="hit":dog.receive_hit_from(7,Vector3.LEFT,3,foe)
  elif mode=="freeze":dog.apply_freeze(foe)
  elif mode=="grab":dog.cancel_for_grab()
  elif mode=="stock":dog.lose_stock()
  elif mode=="reset":dog.reset_fighter(Vector3.ZERO,true)
  elif mode=="disable":dog.controls_enabled=false
  else:dog.global_position.y=4;dog._floor_contacts_valid=false
  await tick(2)
  check(not dog.doge_super_punch.active,"cleanup "+mode)
  if mode=="hit":check(dog.damage_percent==7,"startup vulnerable no armor")
  await tick(120)
  check(foe.damage_percent==0,"no stale damage "+mode)
 # Unrelated routes, routed via current methods; full raw keyboard routes above.
 await fresh(1,6);dog.start_special(Vector2.DOWN);check(dog.doge_counter.phase=="stance","counter preserved")
 await fresh(1,6);dog.start_special(Vector2.RIGHT);check(dog.torpedo_phase=="launch","side tackle preserved")
 await fresh(1,6);dog.start_special(Vector2.UP);check(dog.air_doge.active(),"Air Doge preserved")
 await fresh(1,6);dog.basic_attack(Vector2.DOWN,false);check(dog.doge_cape_attack.active,"down cape preserved")
 await fresh(1,6);dog.basic_attack(Vector2.RIGHT,false);check(dog.doge_ground_basic.clip=="Roundhouse25_42","roundhouse preserved")
 await fresh(1,6);dog.global_position.y=4;dog._floor_contacts_valid=false;await tick();dog.start_special(Vector2.ZERO)
 check(not dog.doge_super_punch.active,"air neutral remains unassigned")
 dog.basic_attack(Vector2.ZERO,true);check(dog.humanoid_air_side.active,"neutral-air Superman preserved")
 # Late arrival boundary: frame57 remains active; frame58 is recovery.
 for arrival in [56,57]:
  await fresh(1,6);await press();key(KEY_G,false);await tick(arrival-1)
  foe.global_position=Vector3(1.3,.001,0);foe.velocity=Vector3.ZERO
  await tick()
  check((foe.damage_percent==25)==(arrival==56),"late contact boundary frame"+str(arrival+1))
 # Direction changes are not a hidden reversal or stored charge.
 await fresh(1,6);await press();key(KEY_G,false);key(KEY_A,true);await tick(20)
 check(dog.facing==1 and dog.position.x==0 and not dog.charging,"no reversal, locomotion or charge store")
 await tick(50);dog.receive_hit_from(7,Vector3.LEFT,3,foe)
 check(not dog.doge_super_punch.active and dog.damage_percent==7,"recovery vulnerable")
 # Synthetic gamepad B uses the same ordinary input route.
 await fresh(1,6);dog.input_device=0
 var joy=InputEventJoypadButton.new();joy.device=0;joy.button_index=JOY_BUTTON_B;joy.pressed=true
 Input.parse_input_event(joy);Input.flush_buffered_events();await tick()
 check(dog.doge_super_punch.active,"synthetic gamepad B accepted")
 joy.pressed=false;Input.parse_input_event(joy);Input.flush_buffered_events();dog.input_device=-1
 # Imported body source parity, independently exported source landmarks.
 await fresh(1,6)
 var samples=JSON.parse_string(FileAccess.get_file_as_string("res://tests/super_doge_source_landmarks.json"));var max_error=0.0
 dog.doge_super_punch.start()
 for face in [1.0,-1.0]:
  dog.doge_super_punch.direction=face
  for frame in samples:
   dog.doge_super_punch.elapsed=(float(frame)-1)/60.0;dog.doge_super_punch.present()
   for bone in samples[frame]:
    var v=samples[frame][bone];var expected=dog.doge_super_punch.view.model.to_global(Vector3(v[0],v[2],-v[1]))
    var sk=dog.doge_super_punch.skeleton
    var actual:Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone(bone)).origin
    max_error=maxf(max_error,actual.distance_to(expected))
 check(max_error<.001,"source landmark parity under1mm")
 dog.doge_super_punch.cancel()
 var report={"moving":moving,"checks":checks,"failures":failures,"rows":rows,"hits":hits,"source_landmark_max_error_m":max_error}
 FileAccess.open(OUT+"test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("SUPER_DOGE_COMPLETE checks=",checks," failures=",failures.size()," contacts=",hits," source_error=",max_error)
 print("SUPER_DOGE_COMPLETE");quit(0 if failures.is_empty() else 1)

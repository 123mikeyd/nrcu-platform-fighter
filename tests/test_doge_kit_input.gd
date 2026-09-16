extends SceneTree
const F=preload("res://scripts/fighter.gd")
const OUT="res://.verification/evidence/doge_v02/"
var dog
var keys=[]
var checks=0
var failures=0
var cases=[]
var trace=[]
var time=0.0
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+message)
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func release_all():
 for k in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_F,KEY_SPACE,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_K,KEY_ENTER]:key(k,false)
func advance(seconds:float):
 var left=seconds
 while left>.000001:
  var dt=minf(.01,left);await physics_frame;dog._physics_process(dt);left-=dt;time+=dt
  var move=dog.doge_ground_basic
  var bones={}
  for n in ["Hips","LeftHand","RightHand","LeftFoot","RightFoot"]:
   var p=move.skeleton.global_transform*move.skeleton.get_bone_global_pose(move.skeleton.find_bone(n)).origin
   bones[n]=[p.x,p.y,p.z]
  trace.append({"time":time,"clip":move.clip,"elapsed":move.elapsed,"serial":move.serial,"bones":bones})
func opener(face:float):
 release_all();dog.reset_fighter(Vector3.ZERO,true);dog.facing=face;await advance(.1)
 check(dog.is_grounded(),"fixture grounded")
 time=0;trace=[];key(keys[4],true);await advance(.01)
 check(dog.doge_ground_basic.clip=="LeadJab","neutral raw edge promptly opens LeadJab")
func tap_after(delay:float):
 key(keys[4],false);await advance(delay);key(keys[4],true);await advance(.01)
func _initialize():call_deferred("run")
func run():
 dog=F.new();dog.character_id="doge_man";root.add_child(dog);dog.set_physics_process(false)
 var floor_body=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,5);shape.shape=box;floor_body.position.y=-.5;floor_body.add_child(shape);root.add_child(floor_body)
 for player in [1,2]:
  dog.player_index=player;keys=[KEY_A,KEY_D,KEY_W,KEY_S,KEY_F] if player==1 else [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_K]
  for face in [1.0,-1.0]:
   for mode in ["tap_once","held","early_twice","late_twice","alternating","mash","reset_held","hit","controls"]:
    var before=failures;await opener(face);var initial=dog.doge_ground_basic.serial
    if mode=="tap_once":key(keys[4],false)
    if mode in ["early_twice","alternating","mash","reset_held","hit","controls"]:await tap_after(.19)
    if mode=="late_twice":await tap_after(.47)
    if mode in ["early_twice","alternating","mash"]:
     await advance(.34)
     check(dog.doge_ground_basic.clip=="Punch2","early repeat branches to native RIGHT Punch2 without restarting jab")
     if mode=="alternating":
      await tap_after(.06);await advance(.21)
      check(dog.doge_ground_basic.clip=="Punch3","third edge requests native LEFT Punch3")
      await tap_after(.04);await advance(.21)
      check(dog.doge_ground_basic.clip=="Punch2","fourth edge wraps to RIGHT, never Punch4 finisher")
     if mode=="mash":
      for i in range(4):await tap_after(.01)
    if mode=="reset_held":dog.reset_fighter(Vector3.ZERO,true)
    if mode=="hit":dog.receive_hit(5,Vector3.LEFT,2)
    if mode=="controls":dog.controls_enabled=false
    await advance(1.6)
    var strikes=dog.doge_ground_basic.serial-initial+1
    var expected=2 if mode=="early_twice" else (4 if mode=="alternating" else (3 if mode=="mash" else 1))
    check(strikes==expected,"%s expected %d strikes got %d"%[mode,expected,strikes])
    check(dog.doge_ground_basic.clip.is_empty(),"chain recovers / interruption clears")
    cases.append({"player":player,"facing":face,"case":mode,"strikes":strikes,"expected":expected,"pass":before==failures,"trace":trace.duplicate(true)})
    print("CASE P%d face%s %s %s"%[player,face,mode,"PASS" if before==failures else "FAIL"])
 release_all();dog.queue_free();floor_body.queue_free();await process_frame
 var file=FileAccess.open(OUT+"input_results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  "));file.close()
 print("PASS DOGE_KIT_INPUT_COMPLETE cases=%d checks=%d failures=%d"%[cases.size(),checks,failures]);quit(1 if failures else 0)

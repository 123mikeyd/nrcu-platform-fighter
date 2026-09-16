extends SceneTree
const F=preload("res://scripts/fighter.gd")
var dog
var checks=0
var failures=0
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func check(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+msg)
func step(seconds:float):
 var left=seconds
 while left>.000001:
  await physics_frame;var dt=minf(.01,left);dog._physics_process(dt);left-=dt
func _initialize():call_deferred("run")
func run():
 dog=F.new();dog.character_id="doge_man";root.add_child(dog);dog.set_physics_process(false)
 var floor=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,5);shape.shape=box;floor.position.y=-.5;floor.add_child(shape);root.add_child(floor)
 for player in [1,2]:
  dog.player_index=player;var code=KEY_F if player==1 else KEY_K
  for face in [1.0,-1.0]:
   dog.reset_fighter(Vector3.ZERO,true);dog.facing=face;await step(.1)
   for chain in range(3):
    var m=dog.doge_ground_basic;var serial=m.serial
    key(code,true);await step(.01)
    check(m.clip=="LeadJab","every fresh neutral chain immediately starts approved Lead, without reset")
    for edge in range(10):
     key(code,false);await step(.01);key(code,true);await step(.01)
     check(m.clip=="LeadJab" and m.serial==serial+1,"mash never substitutes/restarts Lead first strike")
    key(code,false);await step(.28)
    check(m.clip=="LeadJab" and m.elapsed>.48,"Lead remains visible through .49 before .50 link")
    await step(.02)
    check(m.clip=="Punch2" and m.serial==serial+2,"queued opposite hand begins only after Lead strike")
    await step(1.4)
    check(m.clip.is_empty() and m.serial==serial+2,"bounded one-slot mash gives exactly two strikes then recovers")
 var out=FileAccess.open("res://.verification/evidence/doge_v02/blocker_lead_first.json",FileAccess.WRITE);out.store_string(JSON.stringify({"chains":12,"checks":checks,"failures":failures},"  "));out.close()
 dog.queue_free();floor.queue_free();await process_frame;print("PASS LEAD_FIRST_COMPLETE chains=12 checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)

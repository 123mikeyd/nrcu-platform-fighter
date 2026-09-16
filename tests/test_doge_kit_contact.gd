extends SceneTree
const F=preload("res://scripts/fighter.gd")
var dog
var victim
var failures=0
var checks=0
var cases=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+message)
func step(seconds:float):
 var left=seconds
 while left>.000001:
  await physics_frame;var dt=minf(.01,left);dog._physics_process(dt);left-=dt
func _initialize():call_deferred("run")
func run():
 dog=F.new();dog.character_id="doge_man";root.add_child(dog);dog.set_physics_process(false)
 victim=F.new();victim.character_id="doge_man";victim.player_index=2;root.add_child(victim);victim.set_physics_process(false)
 var floor_body=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,5);shape.shape=box;floor_body.position.y=-.5;floor_body.add_child(shape);root.add_child(floor_body)
 for facing in [1.0,-1.0]:
  for clip in ["LeadJab","Roundhouse25_42"]:
   for gap in [1.2,2.5,-1.2]:
    var before=failures
    dog.reset_fighter(Vector3(-5,0,0),true);victim.reset_fighter(Vector3(5,0,0),true);await step(.06)
    dog.reset_fighter(Vector3.ZERO,true);victim.reset_fighter(Vector3(facing*gap,0,0),true);dog.facing=facing;victim.facing=-facing;victim._update_move_visuals(0);await step(.1)
    var position_before=dog.global_position
    dog.basic_attack(Vector2(facing,0) if clip=="Roundhouse25_42" else Vector2.ZERO,false)
    await step(.15)
    check(victim.damage_percent==0,"startup never deals invisible range damage")
    await step(1.5)
    if gap==1.2:check(victim.damage_percent>0,"native live contact near "+clip)
    else:check(victim.damage_percent==0,"far / behind never damaged "+clip)
    check(victim.damage_percent<=10,"one hit ledger per strike")
    var contacts=dog.doge_ground_basic.get("contacts")
    check(contacts!=null,"contact evidence exposed")
    if victim.damage_percent>0:check(contacts.size()==1,"positive hit has exactly one persisted native witness")
    for contact in contacts:check(contact.distance<=contact.radius+contact.receiver_radius,"damage backed by actual limb overlap")
    cases.append({"facing":facing,"clip":clip,"gap":gap,"actual_start":str(position_before),"victim":str(victim.global_position),"damage":victim.damage_percent,"contacts":contacts.duplicate(true),"pass":before==failures})
 var out=FileAccess.open("res://.verification/evidence/doge_v02/contact_results.json",FileAccess.WRITE);out.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  "));out.close()
 dog.queue_free();victim.queue_free();floor_body.queue_free();await process_frame
 print("PASS DOGE_KIT_CONTACT_COMPLETE cases=%d checks=%d failures=%d"%[cases.size(),checks,failures]);quit(1 if failures else 0)

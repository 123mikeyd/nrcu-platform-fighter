extends SceneTree
const F=preload("res://scripts/fighter.gd")
var dog
var victim
var checks=0
var failures=0
var rows=[]
var clearance=[]
func sample_clearance():
 var m=dog.doge_ground_basic
 if m.clip!="Punch2":return
 var a=m.point("RightForeArm");var b=m.point("RightHand");var radius=minf(.10,a.distance_to(b)*.30)
 var best=100.0;var region=""
 for shape in victim.get_hurtbox_shapes():
  if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
  var capsule:CapsuleShape3D=shape.shape;var tr:Transform3D=shape.global_transform
  var half=maxf(0,capsule.height*.5-capsule.radius)
  var pair=Geometry3D.get_closest_points_between_segments(a,b,tr*Vector3(0,-half,0),tr*Vector3(0,half,0))
  var c=pair[0].distance_to(pair[1])-radius-capsule.radius*maxf(tr.basis.x.length(),tr.basis.z.length())
  if c<best:best=c;region=str(shape.name)
 clearance.append({"time":m.elapsed,"clearance":best,"region":region,"hand":str(b),"actor":str(dog.global_position),"target":str(victim.global_position),"active":m.elapsed>=.08 and m.elapsed<=.18})
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func release_all():
 for k in [KEY_F,KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]:key(k,false)
func check(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+msg)
func step(seconds:float):
 var left=seconds
 while left>.000001:
  await physics_frame;var dt=minf(.01,left);victim._physics_process(dt);dog._physics_process(dt);sample_clearance();left-=dt
func _initialize():call_deferred("run")
func run():
 dog=F.new();dog.character_id="doge_man";root.add_child(dog);dog.set_physics_process(false)
 var floor_body=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,5);shape.shape=box;floor_body.position.y=-.5;floor_body.add_child(shape);root.add_child(floor_body)
 for id in ["turbofit"]:
  victim=F.new();victim.character_id=id;victim.player_index=2;root.add_child(victim);victim.set_physics_process(false)
  for facing in [1.0,-1.0]:
   for mode in ["toward","away"]:
    for gap in [8.0]:
     var move="flurry"
     var before=failures;release_all();clearance=[]
     dog.reset_fighter(Vector3(-5,0,0),true);victim.reset_fighter(Vector3(5,0,0),true);await step(.1)
     dog.reset_fighter(Vector3.ZERO,true);victim.reset_fighter(Vector3(facing*gap,0,0),true);dog.facing=facing;victim.facing=-facing;await step(.12)
     var initial_serial=dog.doge_ground_basic.serial
     var start={"dog":str(dog.global_position),"target":str(victim.global_position)}
     if mode!="stationary":
      var axis=facing if mode=="away" else -facing;key(KEY_RIGHT if axis>0 else KEY_LEFT,true)
     if move=="roundhouse":key(KEY_D if facing>0 else KEY_A,true)
     key(KEY_F,true);await step(.01);key(KEY_D,false);key(KEY_A,false);key(KEY_F,false)
     await step(.19)
     if move=="flurry":key(KEY_F,true)
     await step(.35);key(KEY_F,false);await step(.05)
     await step(1.1)
     var contacts=dog.doge_ground_basic.contacts.duplicate(true)
     var right_hits=0
     for c in contacts:
      if c.clip=="Punch2":right_hits+=1
     check(right_hits==1 if mode=="toward" else right_hits==0,"approaching right contact / escaping miss retained")
     check(dog.doge_ground_basic.serial-initial_serial==2,"exactly two raw presses give two strikes")
     var seen={}
     for contact in contacts:
      check(contact.distance<=contact.radius+contact.receiver_radius+.00001,"native anatomy witness backs damage")
      check(not seen.has(contact.serial),"no duplicate target per strike");seen[contact.serial]=true
      check(contact.clip!="FlurryRecovery","recovery never attacks")
     check(contacts.size()<=3 if move=="flurry" else contacts.size()<=1,"bounded strike damage ledger")
     rows.append({"receiver":id,"gap":gap,"clearance":clearance.duplicate(true),"facing":facing,"mode":mode,"move":move,"start":start,"end":{"dog":str(dog.global_position),"target":str(victim.global_position)},"damage":victim.damage_percent,"contacts":contacts,"pass":before==failures})
  victim.queue_free();await process_frame
 release_all();dog.queue_free();floor_body.queue_free();await process_frame
 var out=FileAccess.open("res://.verification/evidence/doge_v02/blocker_right_regression.json",FileAccess.WRITE);out.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":rows},"  "));out.close()
 print("PASS DOGE_RIGHT_REGRESSION_COMPLETE cases=%d checks=%d failures=%d"%[rows.size(),checks,failures]);quit(1 if failures else 0)

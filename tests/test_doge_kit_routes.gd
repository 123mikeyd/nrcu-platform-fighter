extends SceneTree
const F=preload("res://scripts/fighter.gd")
var dog
var keys=[]
var checks=0
var failures=0
var cases=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+message)
func key(code:int,down:bool):
 var e=InputEventKey.new();e.keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func release_all():
 for k in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_F,KEY_SPACE,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_K,KEY_ENTER]:key(k,false)
func step(n:int):
 for i in n:await physics_frame;dog._physics_process(.01)
func _initialize():call_deferred("run")
func run():
 dog=F.new();dog.character_id="doge_man";root.add_child(dog);dog.set_physics_process(false)
 var floor_body=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(100,1,5);shape.shape=box;floor_body.position.y=-.5;floor_body.add_child(shape);root.add_child(floor_body)
 for player in [1,2]:
  dog.player_index=player;keys=[KEY_A,KEY_D,KEY_W,KEY_S,KEY_F,KEY_SPACE] if player==1 else [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_K,KEY_ENTER]
  for face in [1.0,-1.0]:
   for mode in ["ground_side","air_neutral","air_side","ground_up","ground_down"]:
    var before=failures;release_all();dog.reset_fighter(Vector3.ZERO,true);dog.facing=face;await step(10)
    if mode.begins_with("air"):
     key(keys[5],true);await step(8);key(keys[5],false);check(not dog.is_grounded(),"ordinary jump airborne")
    if mode.ends_with("side"):key(keys[1] if face>0 else keys[0],true)
    if mode=="ground_up":key(keys[2],true)
    if mode=="ground_down":key(keys[3],true)
    key(keys[4],true);await step(1)
    if mode=="ground_side":
     check(dog.doge_ground_basic.clip=="Roundhouse25_42","ground side uses exact selected Roundhouse")
     check(absf(dog.doge_ground_basic.duration()-17.0/30.0)<.00001,"Roundhouse source-speed 25..42 duration")
    elif mode.begins_with("air"):
     if mode=="air_side":
      check(dog.get("doge_air_drop")!=null and dog.get("doge_air_drop").active,"side air uses edited Drop Kick")
     else:check(dog.humanoid_air_side.active,"neutral air uses anatomically queried Superman")
     check(not dog.humanoid_air_basic.active,"Doge neutral no longer shared neutral kick")
     check(dog.facing==face,"neutral air keeps facing")
    elif mode=="ground_up":check(dog.doge_attack_clip=="Uppercut","ground uppercut preserved")
    else:check(dog.doge_attack_clip=="TysonTwoPiece","ground down Tyson preserved")
    cases.append({"player":player,"facing":face,"mode":mode,"pass":before==failures})
 release_all();dog.queue_free();floor_body.queue_free();await process_frame
 var out=FileAccess.open("res://.verification/evidence/doge_v02/route_results.json",FileAccess.WRITE);out.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  "));out.close()
 print("PASS DOGE_KIT_ROUTES_COMPLETE cases=%d checks=%d failures=%d"%[cases.size(),checks,failures]);quit(1 if failures else 0)

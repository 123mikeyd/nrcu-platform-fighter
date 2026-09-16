extends SceneTree
const OUT="res://.verification/evidence/doge_v02/"
const C=preload("res://scripts/match_config.gd")
const DT=1.0/120.0
var arena
var dog
var victim
var keys=[]
var failures=0
var checks=0
var rows=[]
func check(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+msg)
func key(k:int,down:bool):
 var e=InputEventKey.new();e.keycode=k;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func release_all():
 for k in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_F,KEY_G,KEY_H,KEY_SPACE,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_K,KEY_L,KEY_SEMICOLON,KEY_ENTER]:key(k,false)
func step(n:int):
 for i in n:
  await physics_frame;victim._physics_process(DT);dog._physics_process(DT)
func setup_match(player:int,id:String):
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 for i in 4:
  arena.setup.rows[i].kind.select(0 if i<2 else 2)
  if i<2:arena.setup.rows[i].character.select(C.CHARACTERS.find("doge_man" if i==player-1 else id))
 arena.setup.level.select(0);arena.setup._start()
 for i in 240:await physics_frame
 check(arena.ready_remaining==0 and arena.fighters.size()==2,"normal Start/Ready completed")
 dog=arena.fighters[player-1];victim=arena.fighters[1 if player==1 else 0]
 check(dog.controls_enabled and dog.character_id=="doge_man","Start spawned active Doge on requested slot")
 dog.set_physics_process(false);victim.set_physics_process(false);arena.set_process(false);arena.set_physics_process(false)
 keys=[KEY_A,KEY_D,KEY_F,KEY_SPACE] if player==1 else [KEY_LEFT,KEY_RIGHT,KEY_K,KEY_ENTER]
func reset(face:float,gap=9.0):
 release_all();dog.reset_fighter(Vector3(-5,0,0),true);victim.reset_fighter(Vector3(5,0,0),true);await step(8)
 dog.reset_fighter(Vector3.ZERO,true);victim.reset_fighter(Vector3(face*gap,0,0),true);dog.facing=face;victim.facing=-face;await step(16)
 check(dog.is_grounded() and victim.is_grounded(),"fixture settled on real terrain")
func _initialize():
 Engine.physics_ticks_per_second=120
 call_deferred("run")
func run():
 for player in [1,2]:
  for id in ["teknium","turbofit"]:
   await setup_match(player,id)
   for face in [1.0,-1.0]:
    for delay in [48,60]:
     for gap in [1.5,2.0,2.5,3.0]:
      for movement in ["toward_jump","away_jump"]:
       var before=failures;await reset(face,gap)
       var start={"dog":str(dog.global_position),"target":str(victim.global_position)}
       var target_keys=[KEY_LEFT,KEY_RIGHT] if player==1 else [KEY_A,KEY_D]
       key(keys[3],true);await step(delay);key(keys[3],false)
       if movement!="stationary":
        key(KEY_ENTER if player==1 else KEY_SPACE,true)
        var axis=face if movement=="away_jump" else -face
        key(target_keys[1] if axis>0 else target_keys[0],true)
       key(keys[1] if face>0 else keys[0],true);key(keys[2],true);await step(1)
       key(keys[0],false);key(keys[1],false)
       check(dog.doge_air_drop.active,"real raw jump+side starts Drop")
       var trace=[]
       for i in 70:
        await step(1)
        trace.append({"time":dog.doge_air_drop.elapsed,"active":dog.doge_air_drop.active,"actor":str(dog.global_position),"target":str(victim.global_position),"damage":victim.damage_percent})
       var contacts=dog.doge_air_drop.contacts.duplicate(true)
       check(contacts.size()<=1,"one native foot contact per target per episode")
       check(victim.damage_percent==8*contacts.size(),"damage backed by actual contact only")
       for c in contacts:check(c.source_frame>=34-.00001 and c.source_frame<=39+.00001,"no startup/retraction damage")
       rows.append({"player":player,"receiver":id,"face":face,"delay":delay*DT,"gap":gap,"movement":movement,"start":start,"end":{"dog":str(dog.global_position),"target":str(victim.global_position)},"contacts":contacts,"trace":trace,"pass":before==failures})
   release_all();arena.queue_free();await process_frame
 var file=FileAccess.open(OUT+"drop_moving_jump_matrix.json",FileAccess.WRITE);file.store_string(JSON.stringify({"cases":rows,"checks":checks,"failures":failures},"  "));file.close()
 print("PASS DROP_MOVING_JUMP_COMPLETE cases=%d checks=%d failures=%d"%[rows.size(),checks,failures]);quit(1 if failures else 0)

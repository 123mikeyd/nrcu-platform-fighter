extends SceneTree
const OUT="res://.verification/evidence/doge_v02/"
const C=preload("res://scripts/match_config.gd")
const DT=1.0/60.0
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
 for k in [KEY_A,KEY_D,KEY_W,KEY_S,KEY_F,KEY_G,KEY_H,KEY_E,KEY_O,KEY_SPACE,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_K,KEY_L,KEY_SEMICOLON,KEY_ENTER]:key(k,false)
func step(n:int):
 for i in n:
  await physics_frame;victim._physics_process(DT);dog._physics_process(DT)
func setup_match(player:int,id:String):
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 for i in 4:
  arena.setup.rows[i].kind.select(0 if i<2 else 2)
  if i<2:arena.setup.rows[i].character.select(C.CHARACTERS.find("doge_man" if i==player-1 else id))
 arena.setup.level.select(0);arena.setup._start()
 for i in 120:await physics_frame
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
 Engine.physics_ticks_per_second=60
 call_deferred("run")
func run():
 for player in [1,2]:
  await setup_match(player,"teknium")
  for face in [1.0,-1.0]:
   var plain=[]
   for mode in ["plain","neutral","side"]:
    var before=failures;await reset(face)
    var start_y=dog.position.y;var trace=[];var serial=dog.doge_air_drop.serial
    key(keys[3],true)
    for i in 55:
     if i==8:
      key(keys[3],false)
      if mode=="side":key(keys[1] if face>0 else keys[0],true)
      if mode!="plain":key(keys[2],true)
     await step(1)
     if i==8 and mode!="plain":
      check(dog.doge_air_drop.active if mode=="side" else dog.humanoid_air_side.active,"raw air directional route")
      check(not dog.humanoid_air_basic.active,"neutral kick override absent for Doge")
      check(dog.facing==face,"committed facing")
     if i==9:key(keys[0],false);key(keys[1],false)
     trace.append({"t":(i+1)*DT,"y":dog.position.y,"relative_y":dog.position.y-start_y,"vy":dog.velocity.y,"active":dog.doge_air_drop.active,"source":27+dog.doge_air_drop.elapsed*30})
    if mode=="plain":plain=trace.duplicate(true)
    else:
     var y_error=0.0;var velocity_error=0.0
     for i in trace.size():
      y_error=maxf(y_error,absf(trace[i].relative_y-plain[i].relative_y));velocity_error=maxf(velocity_error,absf(trace[i].vy-plain[i].vy))
     check(y_error<.001 and velocity_error<.00001,"ordinary jump vertical travel/velocity parity")
     check(not dog.doge_air_drop.active and not dog.humanoid_air_side.active,"episode ended before/at landing")
     check(dog.doge_air_drop.serial-serial==(1 if mode=="side" else 0),"held air attack never repeats")
     check(dog.doge_ground_basic.clip.is_empty(),"held air input never starts phantom ground jab")
     check(victim.damage_percent==0,"distant target has no phantom damage")
    rows.append({"kind":"trajectory","player":player,"face":face,"mode":mode,"trace":trace,"pass":before==failures})
   for interrupt in ["landing","hit","reset","controls","freeze","grab","shield"]:
    var before=failures;await reset(face);key(keys[3],true);await step(8);key(keys[3],false);key(keys[1] if face>0 else keys[0],true);key(keys[2],true);await step(1);key(keys[0],false);key(keys[1],false)
    check(dog.doge_air_drop.active,"interruption fixture active")
    if interrupt=="hit":dog.receive_hit(4,Vector3(-face,0,0),1)
    elif interrupt=="reset":dog.reset_fighter(Vector3.ZERO,true)
    elif interrupt=="controls":dog.controls_enabled=false
    elif interrupt=="freeze":dog.freeze_remaining=.2
    elif interrupt=="grab":dog.cancel_for_grab()
    elif interrupt=="shield":key(KEY_E if player==1 else KEY_O,true)
    else:
     # Start late in a normal jump, then authoritative floor contact truncates it.
     release_all();dog.reset_fighter(Vector3.ZERO,true);await step(16);key(keys[3],true);await step(30);key(keys[3],false);key(keys[1] if face>0 else keys[0],true);key(keys[2],true);await step(1);key(keys[0],false);key(keys[1],false);await step(22)
    await step(2)
    check(not dog.doge_air_drop.active,"cancel on "+interrupt)
    var count=dog.doge_air_drop.contacts.size();await step(8)
    check(dog.doge_air_drop.contacts.size()==count and victim.damage_percent==0,"no post-cancel damage")
    rows.append({"kind":"lifecycle","player":player,"face":face,"interrupt":interrupt,"source_at_cancel":27+dog.doge_air_drop.elapsed*30,"pass":before==failures})
  release_all();arena.queue_free();await process_frame
 var file=FileAccess.open(OUT+"drop_default60_start.json",FileAccess.WRITE);file.store_string(JSON.stringify({"cases":rows,"checks":checks,"failures":failures},"  "));file.close()
 print("PASS DROP_DEFAULT60_START_COMPLETE cases=%d checks=%d failures=%d"%[rows.size(),checks,failures]);quit(1 if failures else 0)

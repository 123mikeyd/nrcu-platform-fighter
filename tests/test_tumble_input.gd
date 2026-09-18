extends SceneTree
const OUT="res://.verification/evidence/latest/"
var failures=[]
var rows=[]
func _initialize():call_deferred("run")
func frames(n):
 for i in n:await physics_frame;await process_frame
func check(ok,msg):
 if not ok:failures.append(msg);print("FAIL: ",msg)
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func run():
 var a=load("res://scenes/main.tscn").instantiate();root.add_child(a);await process_frame
 var ids=load("res://scripts/match_config.gd").CHARACTERS
 for i in 3:
  a.setup.rows[i].character.select(ids.find(["teknium","doge_man","turbofit"][i]));a.setup.rows[i].kind.select(1 if i==2 else 0)
 a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();await frames(150)
 var tek=a.fighters[0];var doge=a.fighters[1];var turbo=a.fighters[2]
 turbo.control_type="human";turbo.player_index=3
 # Leave physics live for all three; only Teknium receives the engine-local F edge.
 for side in [1.0,-1.0]:
  # Flush old broadphase locations before mirrored placement (avoid old-spawn pileup).
  tek.reset_fighter(Vector3(-10,0,0),true);doge.reset_fighter(Vector3(0,0,0),true);turbo.reset_fighter(Vector3(10,0,0),true)
  await frames(3)
  tek.reset_fighter(Vector3(-2*side,0,0),true);doge.reset_fighter(Vector3(-1.04*side,0,0),true);turbo.reset_fighter(Vector3(1.5*side,0,0),true)
  tek.facing=side;doge.facing=-side;await frames(20);doge.damage_percent=130
  key(KEY_F,true);await frames(2);key(KEY_F,false)
  var active=false;var credited=false;var peak=0.0;var after=0.0;var through=false
  for i in 65:
   await frames(1)
   if doge.tumble.active:
    active=true;credited=credited or doge.tumble.source==tek;peak=maxf(peak,absf(doge.velocity.x));after=absf(doge.velocity.x)
   through=through or doge.global_position.x*side>turbo.global_position.x*side+.8
   rows.append({"side":side,"frame":i,"x":doge.position.x,"speed_x":absf(doge.velocity.x),"active":doge.tumble.active,"turbo_damage":turbo.damage_percent,"tek_x":tek.position.x,"tek_face":tek.facing,"move":tek.reaction_recovery.lab_move,"doge_damage":doge.damage_percent})
  check(active and credited,"ordinary Teknium F launches high-percent Doge with source, facing "+str(side))
  check(through,"live TurboFit cannot wall flight, facing "+str(side))
  check(turbo.damage_percent==3 and turbo.last_damage_source==tek,"one credited collateral via real attack, facing "+str(side))
  check(after<peak,"real-input launch decays, facing "+str(side))
 key(KEY_F,false)
 FileAccess.open(OUT+"test_tumble_input.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 a.queue_free();await frames(2)
 if failures.is_empty():print("PASS: TUMBLE INPUT COMPLETE 2 FACINGS")
 quit(0 if failures.is_empty() else 1)

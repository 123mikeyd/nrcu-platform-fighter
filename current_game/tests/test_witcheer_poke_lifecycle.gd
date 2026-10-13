extends SceneTree
class HoldProbe extends Node:
 var phase="test_grab"
 func follow_caught(_delta):pass
 func cancel():pass
var failures=0
func _initialize():call_deferred('run')
func frames(n):
 for i in n:await physics_frame;await process_frame
func check(ok,msg):
 print(('PASS: ' if ok else 'FAIL: ')+msg)
 if not ok:failures+=1
func run():
 var a=load('res://scenes/main.tscn').instantiate();root.add_child(a);await process_frame
 var ids=load('res://scripts/match_config.gd').CHARACTERS
 for i in 2:a.setup.rows[i].character.select(ids.find('witcheer'));a.setup.rows[i].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();a.setup.choose_stage(0);a.setup.launch_match();await frames(100)
 var f=a.fighters[0];var p=a.fighters[1];var v=f._visual_root.get_node('WitcheerVisual')
 for clip in ['CaneDownPokeV002']:
  for reason in ['cancel','freeze','grab','hit','disabled','KO','reset','airborne','setup']:
   f.reset_fighter(Vector3(-3,0,0),true);p.reset_fighter(Vector3(3,0,0),true);await frames(20)
   f.basic_attack(Vector2.DOWN,false);await frames(12)
   check(f.witcheer_clip==clip,'start '+clip+' '+reason)
   match reason:
    'cancel':f._cancel_witcheer()
    'freeze':f.freeze_remaining=1
    'grab':
     var holder=HoldProbe.new();a.add_child(holder);f.caught_by=holder
    'hit':f.receive_hit_from(8,Vector3(1,.35,0),3.8,p)
    'disabled':f.controls_enabled=false
    'KO':f.stocks=0
    'reset':f.reset_fighter(Vector3(-3,0,0),true)
    'airborne':f.position.y=3;f.velocity.y=2;f._floor_contacts_valid=false
    'setup':f.controls_enabled=false
   if reason=='cancel':check(not v.cane.visible and v.cane.transform.is_equal_approx(v.cane_idle_transform),'immediate cancel restores prop')
   await frames(3)
   check(f.witcheer_clip.is_empty(),'lifecycle cancels '+clip+' '+reason)
   check(f.witcheer_basic_targets.is_empty(),'clears hit ledger '+reason)
   f.caught_by=null;f.freeze_remaining=0;f.stocks=3;f.controls_enabled=true
   await frames(100)
   check(p.damage_percent==0,'no ghost hits '+reason)
 print('LIFECYCLE failures=',failures);a.queue_free();await frames(2);print("WITCHEER_POKE_LIFECYCLE_COMPLETE");quit(1 if failures else 0)

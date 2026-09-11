extends SceneTree
const F=preload('res://scripts/fighter.gd')
var failures:=0
var records:=[]
func _initialize():call_deferred('run')
func check(ok,msg):
 if not ok:failures+=1;printerr('FAIL: '+msg)
func key(c,d):
 var e=InputEventKey.new();e.keycode=c;e.pressed=d;Input.parse_input_event(e);Input.flush_buffered_events()
func ticks(n):
 for i in n:await physics_frame;await process_frame
func run():
 var stage=Node3D.new();root.add_child(stage)
 var floor=StaticBody3D.new();floor.collision_layer=2
 var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(28,1,4);shape.shape=box;floor.position.y=-0.5;floor.add_child(shape);stage.add_child(floor)
 var dog=F.new();dog.character_id='doge_man';stage.add_child(dog)
 var enemy=F.new();enemy.character_id='ice_mage';enemy.player_index=2;stage.add_child(enemy)
 var v=dog._visual_root.get_node('DogeVisual')
 check(v.animation_player.has_animation('GoalkeeperKick'),'actual imported clip')
 for facing in [1.0,-1.0]:
  for hold in [1,6,45,120,300]:
   dog.reset_fighter(Vector3(0,.02,0),true);enemy.reset_fighter(Vector3(facing*1.05,.02,0),true);dog.facing=facing
   await ticks(10);key(KEY_G,true);await ticks(hold)
   check(dog.charging,'real held G charges');check(enemy.damage_percent==0,'no charge damage')
   var pose_before=v.animation_player.current_animation_position
   key(KEY_G,false);await ticks(1)
   check(dog.doge_attack_clip=='GoalkeeperKick','real G release kick')
   check(absf(dog.doge_attack_elapsed*2-pose_before)<.034,'release continues visible held source pose at2x')
   var power=dog.doge_goalkeeper_power
   var first=-1.0
   for i in 70:
    await ticks(1)
    if enemy.damage_percent>0 and first<0:first=dog.doge_attack_elapsed
   check(enemy.damage_percent>0,'actual foot reaches standing IceMage')
   check(absf(enemy.damage_percent-lerpf(10,26,power))<.001,'charge scaled once-only damage')
   check(first>=.4 and first<=.501,'damage during visible foot activity')
   records.append({'facing':facing,'hold':hold,'power':power,'damage':enemy.damage_percent,'first':first,'hold_pose':pose_before})
 for scenario in ['hit','freeze','grab','reset','setup','stock']:
  dog.reset_fighter(Vector3(0,.02,0),true);enemy.reset_fighter(Vector3(1.05,.02,0),true);await ticks(10)
  key(KEY_G,true);await ticks(8)
  match scenario:
   'hit':dog.receive_hit(1,Vector3.LEFT,1)
   'freeze':dog.apply_freeze(enemy)
   'grab':dog.cancel_for_grab()
   'reset':dog.reset_fighter(Vector3(0,.02,0),true)
   'setup':dog.controls_enabled=false
   'stock':dog.lose_stock()
  key(KEY_G,false);await ticks(60)
  check(not dog.charging and dog.doge_attack_clip!='GoalkeeperKick','cancel '+scenario)
  check(enemy.damage_percent==0,'no ghost '+scenario)
 dog.reset_fighter(Vector3(0,4,0),true);await ticks(2);key(KEY_G,true);await ticks(2);key(KEY_G,false)
 check(not dog.charging and dog.doge_attack_clip!='GoalkeeperKick','ground only')
 FileAccess.open('res://.verification/evidence/doge_goalkeeper/physics.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'records':records},'  '))
 stage.queue_free();await process_frame
 if failures==0:print('PASS Goalkeeper real G ten charge/facing contacts, six lifecycle interruptions, ground only')
 quit(1 if failures else 0)

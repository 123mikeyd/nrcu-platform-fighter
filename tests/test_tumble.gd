extends SceneTree
const F = preload("res://scripts/fighter.gd")
const OUT = "res://.verification/evidence/latest/"
var failures = []
var checks = []
var rows = []
func _initialize():call_deferred("run")
func check(ok, label):
 checks.append({"label":label,"passed":ok})
 if not ok:failures.append(label);print("FAIL: ",label)
func step():
 await physics_frame
 await process_frame
func run():
 var world=Node3D.new();root.add_child(world)
 var doge=F.new();doge.character_id="doge_man";doge.player_index=3;world.add_child(doge)
 doge.position=Vector3(-4,4,0);doge.damage_percent=130
 doge.receive_hit(10,Vector3(1,.2,0),6)
 check(doge.get("tumble")!=null,"strong hit creates separate tumble controller")
 if doge.get("tumble")!=null:
  check(doge.tumble.active,"strong hit enters tumble")
  var initial=doge.velocity.x
  for i in 14:await step()
  check(doge.velocity.x>0 and doge.velocity.x<initial,"launch decays without reversing")
 var tek=F.new();tek.character_id="teknium";tek.player_index=4;world.add_child(tek)
 var turbo=F.new();turbo.character_id="turbofit";turbo.player_index=5;world.add_child(turbo)
 tek.set_physics_process(false);turbo.set_physics_process(false)
 for side in [1.0,-1.0]:
  doge.reset_fighter(Vector3(-4*side,4,0));doge.damage_percent=130
  tek.position=Vector3(-7*side,4,0);turbo.reset_fighter(Vector3(-1*side,4,0))
  if doge.has_method("receive_hit_from"):doge.receive_hit_from(10,Vector3(side,.2,0),6,tek)
  else:doge.receive_hit(10,Vector3(side,.2,0),6)
  for i in 30:
   await step()
   rows.append({"side":side,"frame":i,"x":doge.position.x,"vx":doge.velocity.x,"turbo_damage":turbo.damage_percent})
  check(doge.position.x*side>0,"uninterrupted passage both facings")
  check(turbo.damage_percent>0 and turbo.damage_percent<=4,"one minor collateral hit")
  check(turbo.get("last_damage_source")==tek,"collateral credits original attacker")
  check(not turbo.tumble.active,"collateral cannot launch another damaging tumble")
 doge.reset_fighter(Vector3(0,4,0));doge.damage_percent=130
 tek.position=Vector3(-1,4,0);tek.facing=1
 tek._directional_hit(10,6,3,Vector3(1,.2,0),.1)
 check(doge.last_damage_source==tek,"production attack supplies attribution")
 check(doge.tumble.get("effects")!=null,"danger flight has local effects")
 # Lifecycle, overlap ledger, low-speed negatives and native terrain.
 doge.set_physics_process(false)
 doge.reset_fighter(Vector3(0,4,0));doge.damage_percent=130;turbo.reset_fighter(Vector3(.5,4,0))
 doge.receive_hit_from(10,Vector3.RIGHT,6,tek)
 for i in 8:doge.tumble.contact_sweep(doge.position,doge.position)
 check(turbo.damage_percent==3,"repeated overlap consumes recipient only once")
 doge.velocity=Vector3(2,0,0);turbo.reset_fighter(Vector3(.5,4,0));doge.tumble.recipients.clear()
 doge.tumble.contact_sweep(doge.position,doge.position)
 check(turbo.damage_percent==0,"low-speed contact does no damage")
 doge.hitstun=0
 check(doge.tumble.active,"tumble persists independently of hitstun")
 check(not doge.try_jump(),"tumble disallows jump after hitstun ends")
 doge.reset_fighter(Vector3.ZERO)
 check(not doge.tumble.active and doge.get_collision_exceptions().is_empty(),"reset clears flight and collision exceptions")
 doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek);doge.lose_stock()
 check(not doge.tumble.active and doge.get_collision_exceptions().is_empty(),"stock clears flight")
 doge.reset_fighter(Vector3(0,4,0));doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek)
 doge.damage_percent=0;doge.receive_hit_from(1,Vector3.LEFT,1,turbo)
 check(not doge.tumble.active and doge.last_damage_source==turbo,"weak interruption replaces launch and credit")
 check(doge.hitstun>0,"weak reaction still has native hitstun")
 doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek);doge.controls_enabled=false
 check(not doge.tumble.active,"disable clears tumble immediately")
 doge.reset_fighter(Vector3.ZERO)
 var floor_body=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(28,1,6);shape.shape=box;floor_body.add_child(shape);floor_body.position.y=-.5;world.add_child(floor_body)
 tek.position=Vector3(-7,0,0);turbo.position=Vector3(10,0,0)
 doge.set_physics_process(true)
 for i in 10:await step()
 doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek)
 for i in 10:await step()
 check(doge.tumble.active and doge.position.x>1,"strong ground launch lifts instead of immediately cancelling on floor")
 for i in 100:await step()
 check(not doge.tumble.active and doge.is_grounded(),"real stage landing ends flight")
 check(doge.get_collision_exceptions().is_empty(),"landing restores normal solid interactions")
 doge.set_physics_process(false)
 doge.reset_fighter(Vector3(0,4,0));turbo.reset_fighter(Vector3(.5,4,0));turbo.damage_percent=999
 doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek)
 doge.tumble.contact_sweep(doge.position,doge.position)
 check(turbo.damage_percent==1002 and turbo.velocity.length()<=4.001 and not turbo.tumble.active,"high-percent collateral is capped without chains")
 var before=doge.position
 var player=doge._visual_root.find_children("*","AnimationPlayer",true,false)[0]

 doge.tumble.tick(.016)
 check(doge.position==before,"hitstop holds launch position")
 check(player.process_mode==Node.PROCESS_MODE_DISABLED,"hitstop freezes reaction playback")
 check(doge.fitted_reaction.process_mode==Node.PROCESS_MODE_DISABLED,"hitstop also freezes fitted procedural reaction clock")
 doge.tumble.pause_remaining=0;doge.tumble.tick(.016)
 check(player.process_mode!=Node.PROCESS_MODE_DISABLED,"hitstop restores playback")
 doge.tumble.effects.update(0,true,.01,17);check(doge.tumble.effects.flashing,"local danger pulse on")
 doge.tumble.effects.update(0,true,.2,17);check(not doge.tumble.effects.flashing,"local danger pulse off")
 doge.tumble.effects.update(0,true,.51,17);check(doge.tumble.effects.flashing,"local danger pulse recurs")
 doge.tumble.effects.update(0,false,.6,2);check(doge.tumble.effects.strength==0,"effects fade at low launch speed")
 doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek)
 turbo.damage_percent=130;turbo.receive_hit_from(10,Vector3.LEFT,6,tek)
 doge.tumble.clear()
 check(doge in turbo.get_collision_exceptions(),"ending one launch preserves other active launch passthrough")
 turbo.tumble.clear()
 check(doge.get_collision_exceptions().is_empty(),"last launch releases pair exceptions")
 doge.damage_percent=130;doge.receive_hit_from(10,Vector3.RIGHT,6,tek)
 check(doge.apply_freeze(tek),"freeze interrupts launch")
 doge.tumble.tick(.016)
 check(not doge.tumble.active,"freeze clears tumble")
 doge.reset_fighter(Vector3(0,3,0));doge.damage_percent=130
 var wall=StaticBody3D.new();var wall_shape=CollisionShape3D.new();var wall_box=BoxShape3D.new();wall_box.size=Vector3(.3,8,6);wall_shape.shape=wall_box;wall.add_child(wall_shape);wall.position=Vector3(2,4,0);world.add_child(wall)
 turbo.reset_fighter(Vector3(-5,0,0));tek.position=Vector3(-8,0,0)
 await step();doge.receive_hit_from(10,Vector3.RIGHT,6,tek);doge.set_physics_process(true)
 for i in 20:await step()
 check(doge.position.x<1.5,"strong flight retains stage wall collision")
 doge.set_physics_process(false);doge.player_index=1;doge.hitstun=0
 var event=InputEventKey.new();event.keycode=KEY_F;event.physical_keycode=KEY_F;event.pressed=true;Input.parse_input_event(event);Input.flush_buffered_events()
 doge.tumble.tick(.016)
 check(doge._attack_was_down,"held attack during flight is latched, not queued on recovery")
 event=InputEventKey.new();event.keycode=KEY_F;event.physical_keycode=KEY_F;event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events()
 world.queue_free();await process_frame
 FileAccess.open(OUT+"test_tumble.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":checks,"rows":rows},"  "))
 if failures.is_empty():print("PASS: TUMBLE COMPLETE")
 quit(0 if failures.is_empty() else 1)

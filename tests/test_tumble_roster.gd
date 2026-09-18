extends SceneTree
const F=preload("res://scripts/fighter.gd")
const B=preload("res://scripts/bobo_fighter.gd")
const H=preload("res://scripts/body_hurtboxes.gd")
const OUT="res://.verification/evidence/latest/"
var actors=[]
var checks=[]
var pairs=[]
var failures=[]
var world
var source
func _initialize():call_deferred("run")
func check(ok,label,id):
 checks.append({"actor":id,"label":label,"passed":bool(ok)})
 if not ok:failures.append(id+": "+label);print("FAIL: ",id,": ",label)
func step(n=1):
 for i in n:
  await physics_frame
  await process_frame
func reset_all():
 for i in actors.size():
  var a=actors[i];a.set_physics_process(false);a.reset_fighter(Vector3(40+i*4,4,0),true);a.team_id=-1;a.shielding=false
 source.reset_fighter(Vector3(-12,4,0),true);source.team_id=-1
func run():
 world=Node3D.new();root.add_child(world)
 var ids=preload("res://scripts/roster.gd").ids();ids.append("bobo")
 for id in ids:
  var a=B.new() if id=="bobo" else F.new();a.character_id=id;a.player_index=8;a.name=id;world.add_child(a);a.set_physics_process(false);actors.append(a)
 source=F.new();source.player_index=9;world.add_child(source);source.set_physics_process(false)
 reset_all()
 for a in actors:
  var id=a.character_id
  reset_all();a.position=Vector3(0,4,0);a.damage_percent=130
  a.receive_hit_from(10,Vector3.RIGHT,6,source)
  if id=="bobo":
   check(not a.tumble.active and a.velocity==Vector3.ZERO,"stationary encounter never enters flight",id)
   check(a.health==390 and a.last_damage_source==source,"health damage and source retained",id)
   continue
  check(a.tumble.active,"strong launch",id)
  check(a.last_damage_source==source,"direct source credit",id)
  var pos=a.position;var speed=a.velocity.length();a.tumble.tick(.016)
  check(a.position==pos and a.tumble.pause_remaining>0,"hitstop holds position",id)
  a.tumble.pause_remaining=0;a.tumble.tick(.016)
  check(a.velocity.length()<speed,"flight slowdown",id)
  check(a.tumble.effects!=null,"local effects created",id)
  a.tumble.effects.update(0,true,.01,17);check(a.tumble.effects.flashing,"local pulse",id)
  a.reset_fighter(Vector3(0,4,0),true)
  check(not a.tumble.active and a.get_collision_exceptions().is_empty() and not a.tumble.effects.flashing,"reset clears hazard exceptions effects",id)
  a.receive_hit_from(1,Vector3.LEFT,1,source);check(not a.tumble.active and a.hitstun>0,"weak stays native",id)
  a.damage_percent=130;a.receive_hit_from(10,Vector3.RIGHT,6,source);a.lose_stock();check(not a.tumble.active,"stock clears flight",id)
  a.reset_fighter(Vector3(0,4,0),true);a.damage_percent=130;a.receive_hit_from(10,Vector3.RIGHT,6,source);a.controls_enabled=false;check(not a.tumble.active,"disable clears flight",id)
  reset_all();a.position=Vector3(0,4,0);a.damage_percent=130
  H.deliver(a,10,Vector3.RIGHT,6,{"position":a.position+Vector3.UP},source)
  check(a.last_damage_source==source and a.tumble.source==source,"real contact delivery source",id)
 # Exhaustive ordered launch-victim / recipient pairs, both directions.
 for a in actors:
  if a.character_id=="bobo":continue
  for b in actors:
   if a==b:continue
   for side in [1.0,-1.0]:
    reset_all();a.position=Vector3(-3*side,4,0);b.position=Vector3(0,4,0);a.damage_percent=130
    a.receive_hit_from(10,Vector3(side,.1,0),6,source)
    var hp=b.health if b.character_id=="bobo" else b.damage_percent
    for i in 3:a.tumble.contact_sweep(Vector3(-3*side,4,0),Vector3(3*side,4,0))
    var damage=hp-b.health if b.character_id=="bobo" else b.damage_percent-hp
    var ok=is_equal_approx(damage,3) and b.last_damage_source==source and not b.tumble.active and b.velocity.length()<=4.001
    pairs.append({"victim":a.character_id,"recipient":b.character_id,"side":side,"damage":damage,"passed":ok})
    check(ok,"ordered pair %s side %s"%[b.character_id,side],a.character_id)
    check(b in a.get_collision_exceptions(),"pair pass-through exception "+b.character_id,a.character_id)
 # Policy and simultaneous ownership per selectable actor.
 for a in actors:
  if a.character_id=="bobo":continue
  var b=actors[1] if a==actors[0] else actors[0]
  for policy in ["shield","team","disabled","slow","simultaneous"]:
   reset_all();a.position=Vector3(0,4,0);b.position=Vector3(.5,4,0);a.damage_percent=130
   if policy=="shield":b.shielding=true
   if policy=="team":source.team_id=2;b.team_id=2
   if policy=="disabled":b.controls_enabled=false
   a.receive_hit_from(10,Vector3.RIGHT,6,source)
   if policy=="slow":a.velocity=Vector3.RIGHT
   if policy=="simultaneous":
    b.damage_percent=130;b.receive_hit_from(10,Vector3.LEFT,6,source);a.tumble.clear()
    check(a in b.get_collision_exceptions(),"simultaneous keeps exception",a.character_id)
    b.tumble.clear();check(a.get_collision_exceptions().is_empty(),"simultaneous releases final exception",a.character_id)
   else:
    a.tumble.contact_sweep(a.position,a.position)
    check(is_equal_approx(b.damage_percent,1.05 if policy=="shield" else 0.0),policy+" policy",a.character_id)
 # Real physics passage and landing, each selectable, both directions.
 var floor_body=StaticBody3D.new();var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(28,1,6);col.shape=box;floor_body.add_child(col);floor_body.position.y=-.5;world.add_child(floor_body)
 for a in actors:
  if a.character_id=="bobo":continue
  var b=actors[1] if a==actors[0] else actors[0]
  for side in [1.0,-1.0]:
   reset_all();a.position=Vector3(-3*side,0,0);a.spawn_position=a.position;b.position=Vector3(0,0,0);a.set_physics_process(true)
   await step(8);a.damage_percent=130;a.receive_hit_from(10,Vector3(side,.35,0),6,source)
   await step(30)
   check(a.position.x*side>0,"real physics passage side %s"%side,a.character_id)
   await step(90)
   check(not a.tumble.active and a.is_grounded(),"terrain landing recovery side %s"%side,a.character_id)
   check(a.get_collision_exceptions().is_empty(),"landing restores solid bodies",a.character_id)
 # Receiver policy parity includes every selectable actor and health-based Bobo.
 for receiver in actors:
  var launched_actor=actors[1] if receiver==actors[0] else actors[0]
  for policy in ["shield","team","disabled"]:
   reset_all();launched_actor.position=Vector3(0,4,0);receiver.position=Vector3(.5,4,0)
   launched_actor.damage_percent=130
   if policy=="shield":receiver.shielding=true
   if policy=="team":source.team_id=2;receiver.team_id=2
   if policy=="disabled":receiver.controls_enabled=false
   var before=receiver.health if receiver.character_id=="bobo" else receiver.damage_percent
   launched_actor.receive_hit_from(10,Vector3.RIGHT,6,source)
   launched_actor.tumble.contact_sweep(launched_actor.position,launched_actor.position)
   var received=before-receiver.health if receiver.character_id=="bobo" else receiver.damage_percent-before
   check(is_equal_approx(received,1.05 if policy=="shield" else 0.0),"recipient "+policy+" policy",receiver.character_id)
 # Per-actor terrain wall, protection, freeze, distant miss and effect cleanup.
 var wall=StaticBody3D.new();var wc=CollisionShape3D.new();var wb=BoxShape3D.new();wb.size=Vector3(.3,8,6);wc.shape=wb;wall.add_child(wc);wall.position=Vector3(2,4,0);world.add_child(wall)
 for a in actors:
  if a.character_id=="bobo":continue
  reset_all();a.position=Vector3(0,3,0);a.damage_percent=130
  await step(2);a.receive_hit_from(10,Vector3.RIGHT,6,source);a.set_physics_process(true);await step(20)
  check(a.position.x<1.5,"terrain wall blocks flight",a.character_id)
  a.set_physics_process(false);a.apply_freeze(source);a.tumble.tick(.016)
  check(not a.tumble.active,"freeze clears hazard",a.character_id)
  a.reset_fighter(Vector3.ZERO,true)
  var hidden=true
  for particle in a.tumble.effects.particles:hidden=hidden and not particle.mesh.visible
  check(hidden and a.tumble.effects.strength==0,"reset cleans complete particle pool",a.character_id)
  # Protected receiver is Teknium's real grounded recovery, not a fake shield.
  reset_all();source.position=Vector3(-5,0,0);source.set_physics_process(true);await step(8);source.set_physics_process(false)
  source.reaction_recovery.knockdown_phase="rest";source.velocity=Vector3.ZERO
  var launcher=actors[1] if a==actors[0] else actors[0]
  launcher.position=Vector3(-5,0,0);launcher.damage_percent=130
  a.position=Vector3(-9,0,0);launcher.receive_hit_from(10,Vector3.RIGHT,6,a)
  check(source.is_knockdown_protected(),"protection fixture grounded",a.character_id)
  launcher.tumble.contact_sweep(launcher.position,launcher.position)
  check(source.damage_percent==0,"protected recovery rejects collateral",a.character_id)
  reset_all();a.position=Vector3(-3,4,0);a.damage_percent=130;a.receive_hit_from(10,Vector3.RIGHT,6,source)
  a.tumble.contact_sweep(a.position,a.position+Vector3.RIGHT)
  check(a.tumble.recipients.is_empty(),"distant recipients miss",a.character_id)
  a.tumble.pause_remaining=0;a.tumble.clock=1.59;a.tumble.tick(.02)
  check(not a.tumble.active,"bounded timeout clears flight",a.character_id)
 reset_all();world.queue_free();await process_frame
 FileAccess.open(OUT+"roster_tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"pairs":pairs,"failures":failures},"  "))
 print("ROSTER_TUMBLE_COMPLETE checks=",checks.size()," pairs=",pairs.size()," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)

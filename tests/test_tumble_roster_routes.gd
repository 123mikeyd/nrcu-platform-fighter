extends SceneTree
const F=preload("res://scripts/fighter.gd")
const OUT="res://.verification/evidence/latest/"
var rows=[]
var failures=[]
func _initialize():call_deferred("run")
func step(n):
 for i in n:await physics_frame;await process_frame
func run():
 var world=Node3D.new();root.add_child(world)
 var floor_body=StaticBody3D.new();var c=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(28,1,6);c.shape=box;floor_body.add_child(c);floor_body.position.y=-.5;world.add_child(floor_body)
 var ids=preload("res://scripts/roster.gd").ids();ids.append("bobo")
 for id in ids:
  var a=load("res://scripts/bobo_fighter.gd").new() if id=="bobo" else F.new();a.character_id=id;a.player_index=8
  if id=="bobo":a.diagnostic_control=true
  var b=F.new();b.character_id="ggb";b.player_index=9;world.add_child(a);world.add_child(b)
  for side in [1.0,-1.0]:
   var found=false
   for gap in [1.0,1.4,2.0]:
    a.reset_fighter(Vector3(0,0,0),true);b.reset_fighter(Vector3(side*gap,0,0),true);a.facing=side;b.facing=-side;a.set_physics_process(true);b.set_physics_process(false)
    # Isolated attribution witness: no body-pushing of the held receiver.
    a.add_collision_exception_with(b);b.add_collision_exception_with(a)
    await step(12);b.damage_percent=999 if id=="bobo" else 130
    if id=="bobo":a.thrust_rest=0
    a.basic_attack(Vector2(side,0) if id=="bobo" else Vector2.ZERO,false)
    var move=a.last_move
    await step(250 if id=="bobo" else 120)
    var damage=b.damage_percent-(999 if id=="bobo" else 130)
    var credit=b.last_damage_source==a
    rows.append({"actor":id,"route":"native_ground_basic","side":side,"gap":gap,"move":move,"damage":damage,"credited":credit,"witness":damage>0})
    if damage>0:
     found=credit
     break
   if not found:failures.append(id+" native basic attribution side "+str(side))
  if id in ["teknium","ggb","turbofit","ice_mage","witcheer"]:
   for side in [1.0,-1.0]:
    for shot in get_nodes_in_group("projectiles"):shot.queue_free()
    a.reset_fighter(Vector3(0,0,0),true);b.reset_fighter(Vector3(side*2,0,0),true);a.facing=side;b.set_physics_process(false)
    a.add_collision_exception_with(b);b.add_collision_exception_with(a)
    await step(12);b.damage_percent=999 if id=="bobo" else 130
    a.start_special(Vector2(side,0));var move=a.last_move
    await step(150)
    var ok=b.damage_percent>130 and b.last_damage_source==a
    rows.append({"actor":id,"route":"native_projectile_special","side":side,"move":move,"damage":b.damage_percent-130,"credited":b.last_damage_source==a,"witness":b.damage_percent>130})
    if not ok:failures.append(id+" native projectile attribution side "+str(side))
  a.queue_free();b.queue_free();await step(2)
 world.queue_free();await process_frame
 FileAccess.open(OUT+"native_routes.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures},"  "))
 for f in failures:print("FAIL: ",f)
 print("ROSTER_NATIVE_ROUTES_COMPLETE rows=",rows.size()," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)

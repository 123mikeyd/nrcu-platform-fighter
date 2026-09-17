extends Node
# A single actor owns both leads: no damage/stocks are copied or reset on switching.
const Kit=preload("res://scripts/mephisto_kit.gd")
var actor
var demon_form=false
var move=""
var elapsed=0.0
var facing=1.0
var targets=[]
var contacts=[]
var impulse_done=false
var serial=0
var power=0.0
var effect:Node3D
var smoke_origin=Vector3.ZERO
const BASIC={
 "RightSwipe":{"start":109.0,"end":204.0,"hit":148.0,"duration":.82,"bone":"DEF-hand.R","damage":8.0,"kb":3.6},
 "FrontKick":{"start":1.0,"end":108.0,"hit":47.0,"duration":.94,"bone":"DEF-foot.R","damage":10.0,"kb":4.1},
 "RisingForearm":{"start":205.0,"end":300.0,"hit":244.0,"duration":.86,"bone":"DEF-forearm.R","damage":9.0,"kb":4.2},
 "Stomp":{"start":301.0,"end":396.0,"hit":347.0,"duration":.90,"bone":"DEF-foot.R","damage":10.0,"kb":3.8}}
func _ready():actor=get_parent()
func view():return actor.get_node_or_null("VisualRoot/MephistoVisual")
func route(aim:Vector2,air:bool,special:bool)->String:
 if special and aim.y>.1:return "SwitchToGirl" if demon_form else "SwitchToDemon"
 if demon_form:
  if special:return "CinderToss" if aim.y<-.1 else ("SmokeCharge" if absf(aim.x)>.1 else "RightSwipe")
  if aim.y<-.1:return "RisingForearm"
  if aim.y>.1:return "Stomp"
  return "FrontKick" if absf(aim.x)>.1 else "RightSwipe"
 return Kit.route(aim,air,special)
func start_kit(id:String,direction:float):
 if id=="CinderToss" and actor.recovery_spent:return
 if id.begins_with("Switch") and not actor.is_grounded():return
 cancel();move=id;facing=direction;actor.facing=direction;serial+=1
 actor.last_move=id;elapsed=0;contacts.clear();impulse_done=false
 if id=="SmokeCharge":actor.charging=true;actor.charge_time=0
 if id=="CinderToss":actor.recovery_spent=true;actor.jumps_used=2
 actor.attack_cooldown=duration();present()
func duration()->float:
 if move=="SmokeCharge":return 100000.0
 if move=="SmokeRelease":return 1.2
 if move=="SwitchToDemon":return 1.4
 if move=="SwitchToGirl":return 1.7
 if BASIC.has(move):return BASIC[move].duration
 return Kit.duration(move) if Kit.MOVES.has(move) else .8
func present():
 if not view():return
 view().shadow_move=move
 if move=="SwitchToDemon":view().pose_frame(lerpf(733,816,clampf(elapsed/duration(),0,1)),facing)
 elif move=="SwitchToGirl":view().pose_frame(lerpf(577,704,clampf(elapsed/duration(),0,1)),facing)
 elif BASIC.has(move):
  var d=BASIC[move];view().pose_frame(lerpf(d.start,d.end,clampf(elapsed/d.duration,0,1)),facing)
 elif move=="SmokeCharge":view().pose_frame(lerpf(397,444,clampf(elapsed/.45,0,1)),facing)
 elif move=="SmokeRelease":view().pose_frame(lerpf(444,576,clampf(elapsed/1.2,0,1)),facing)
 elif move=="CinderToss" and demon_form:view().pose_frame(1,facing)
 elif not move.is_empty():view().girl_pose(elapsed,facing)
func release():
 if move!="SmokeCharge":return
 power=clampf(actor.charge_time/1.5,0,1)
 actor.charging=false;actor.charge_time=0
 move="SmokeRelease";elapsed=0;actor.attack_cooldown=duration();actor.last_move="ORANGE SMOKE"
 present()
func cancel():
 if actor:
  actor.charging=false;actor.charge_time=0
  if not move.is_empty():actor.attack_cooldown=0
 if is_instance_valid(effect):effect.queue_free()
 effect=null
 move="";elapsed=0;targets.clear();impulse_done=false
 if actor and view():view().end_shadow_move()
func tick(delta:float):
 if move.is_empty():return
 if not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor._read_raw_controls(0).shield:
  cancel();actor.attack_cooldown=0;return
 var previous=elapsed
 elapsed+=delta;present()
 if BASIC.has(move):
  var d=BASIC[move]
  var impact=(d.hit-d.start)/(d.end-d.start)*d.duration
  if elapsed>=impact-.07 and previous<=impact+.09:
   var launch=Vector3(facing,.25,0)
   if move=="RisingForearm":launch=Vector3(facing*.2,1,0)
   query_hand(view().demon_point(d.bone),.19,d.damage,launch,d.kb)
   if move=="RightSwipe" or move=="RisingForearm":query_hand(view().demon_point("DEF-hand.R"),.19,d.damage,launch,d.kb)
  if move=="Stomp" and elapsed>=impact and previous<=impact+.055 and actor.is_grounded():
   # A short visible ground-dust footprint makes the planted stomp usable.
   # No body-range sink: only actual lower receiving anatomy inside this disk.
   if not impulse_done:
    impulse_done=true;smoke_origin=view().demon_point("DEF-foot.R");smoke_origin.y=actor.global_position.y+.035
    effect=preload("res://scripts/mephisto_orange_smoke.gd").new();effect.ground_dust=true;effect.reach=1.15
    actor.get_parent().add_child(effect);effect.global_position=smoke_origin
   query_stomp()
 elif move=="SmokeRelease":
  if elapsed>=.12 and not impulse_done:
   impulse_done=true;smoke_origin=view().demon_point("DEF-hand.R")
   effect=preload("res://scripts/mephisto_orange_smoke.gd").new()
   effect.direction=facing;effect.reach=lerpf(1.2,2.0,power)
   actor.get_parent().add_child(effect);effect.global_position=smoke_origin
  if elapsed>=.12 and elapsed<=.38:
   for i in 9:
    var u=float(i)/8
    query_hand(smoke_origin+Vector3(facing*lerpf(1.2,2.0,power)*u,0,0),lerpf(.12,.34,u),lerpf(6,13,power),Vector3(facing,.2,0),lerpf(3,4.8,power),true)
 elif move=="CinderToss":
  if elapsed>=.36 and not impulse_done:impulse_done=true;actor.velocity.y=13.0
 elif Kit.MOVES.has(move):
  var d=Kit.MOVES[move]
  if elapsed>=d.startup and elapsed<=d.startup+d.active:
   query_hand(view().girl_point("RightHand"),.16,d.damage,Vector3(facing,.3,0),d.kb)
 if elapsed>=duration():
  if move=="SwitchToDemon":demon_form=true
  elif move=="SwitchToGirl":demon_form=false
  cancel();actor.attack_cooldown=0
  actor._update_move_visuals()
func query_hand(point:Vector3,radius:float,damage:float,direction:Vector3,kb:float,forward_only=false):
 for target in get_tree().get_nodes_in_group("fighters"):
  if target in targets or not actor.can_hit(target):continue
  if forward_only and (target.global_position.x-actor.global_position.x)*facing<=0:continue
  for shape in target.get_hurtbox_shapes():
   if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
   var half=maxf(0,shape.shape.height*.5-shape.shape.radius)
   var xf:Transform3D=shape.global_transform
   var nearest=Geometry3D.get_closest_point_to_segment(point,xf*Vector3(0,-half,0),xf*Vector3(0,half,0))
   var body_radius=shape.shape.radius*maxf(xf.basis.x.length(),xf.basis.z.length())
   if point.distance_to(nearest)<=body_radius+radius:
    targets.append(target)
    contacts.append({"move":move,"elapsed":elapsed,"source_frame":view().source_frame,"point":str(point),"target":target.character_id,"damage":damage})
    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,damage,direction,kb,shape,nearest,point,actor)
    break
func query_stomp():
 for target in get_tree().get_nodes_in_group("fighters"):
  if target in targets or not actor.can_hit(target) or not target.is_grounded():continue
  for shape in target.get_hurtbox_shapes():
   if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
   var half=maxf(0,shape.shape.height*.5-shape.shape.radius)
   var xf:Transform3D=shape.global_transform
   var low=xf*Vector3(0,-half,0)
   var other_end=xf*Vector3(0,half,0)
   if other_end.y<low.y:low=other_end
   var r=shape.shape.radius*maxf(xf.basis.x.length(),xf.basis.z.length())
   if low.y-r>smoke_origin.y+.3:continue
   if Vector2(low.x-smoke_origin.x,low.z-smoke_origin.z).length()<=1.15+r:
    targets.append(target);contacts.append({"move":"Stomp","elapsed":elapsed,"source_frame":view().source_frame,"radius":1.15,"target":target.character_id,"damage":10.0,"kind":"visible ground dust"})
    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,10.0,Vector3(facing,.25,0),3.8,shape,low,smoke_origin,actor)
    break

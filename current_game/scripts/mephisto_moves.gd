extends Node
# A single actor owns both leads: no damage/stocks are copied or reset on switching.
const Kit=preload("res://scripts/mephisto_kit.gd")
const ArmTiming=preload("res://scripts/mephisto_arm_timing.gd")
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
var girl_magic
var girl_kick
var shadow_chain
var chain_pose
func chain_animation():
 if not chain_pose:
  chain_pose=preload("res://scripts/mephisto_chain_pose.gd").new();chain_pose.moves=self
 return chain_pose
func kick():
 if not girl_kick:
  girl_kick=preload("res://scripts/mephisto_girl_kick.gd").new();girl_kick.moves=self
 return girl_kick
func magic():
 if not girl_magic:
  girl_magic=preload("res://scripts/mephisto_girl_magic.gd").new();girl_magic.moves=self;add_child(girl_magic)
 return girl_magic
const BASIC={
 "RightSwipe":{"start":109.0,"end":204.0,"hit":148.0,"duration":.82,"bone":"DEF-hand.R","damage":8.0,"kb":3.6},
 "ForwardBackhand":{"start":1.0,"end":64.0,"hit":28.0,"active_start":27.0,"active_end":33.0,"duration":1.19,"bone":"DEF-hand.R","damage":10.0,"kb":4.1},
 "RisingForearm":{"start":205.0,"end":300.0,"hit":244.0,"duration":.86,"bone":"DEF-forearm.R","damage":9.0,"kb":4.2},
 "GroundPalmSlam":{"start":1.0,"end":76.0,"hit":34.0,"active_start":33.0,"active_end":38.0,"duration":1.29,"bone":"DEF-hand.R","damage":10.0,"kb":3.8}}
func _ready():actor=get_parent()
func view():return actor.get_node_or_null("VisualRoot/MephistoVisual")
func route(aim:Vector2,air:bool,special:bool)->String:
 if special and aim.y>.1:return "CompanionPalm"
 if demon_form:
  if special:return "PairVanish" if aim.y<-.1 else ("ShadowChain" if absf(aim.x)>.1 else "SmokeCharge")
  if aim.y<-.1:return "RisingForearm"
  if aim.y>.1:return "GroundPalmSlam"
  return "ForwardBackhand" if absf(aim.x)>.1 else "RightSwipe"
 if special:return "PairTeleport" if aim.y<-.1 else ("EmberHold" if absf(aim.x)>.1 else "Barrier")
 return Kit.route(aim,air,special)
func start_kit(id:String,direction:float):
 if id.begins_with("Switch"):return
 demon_form=false
 if id in ["CinderToss","PairTeleport","PairVanish"] and actor.recovery_spent:return
 if id.begins_with("Switch") and not actor.is_grounded():return
 cancel();move=id;facing=direction;actor.facing=direction;serial+=1
 actor.last_move=id;elapsed=0;contacts.clear();impulse_done=false
 if id=="AnkleRake":kick().begin()
 if id in ["Barrier","EmberHold","PairTeleport","PairVanish"]:magic().begin(id)
 if id=="SmokeCharge":actor.charging=true;actor.charge_time=0
 if id=="CinderToss":actor.recovery_spent=true;actor.jumps_used=2
 actor.attack_cooldown=duration();present()
 if id=="ShadowChain":
  shadow_chain=preload("res://scripts/mephisto_shadow_chain.gd").new();shadow_chain.moves=self;actor.get_parent().add_child(shadow_chain)
func duration()->float:
 if move=="CompanionPalm":return view().companion.attack_duration()
 if move in ["ForwardBackhand","GroundPalmSlam"]:return ArmTiming.duration(move)
 if move=="ShadowChain":return 100000.0
 if move=="ShadowRecover":return preload("res://scripts/mephisto_chain_pose.gd").RETRACT
 if move=="AnkleRake":return preload("res://scripts/mephisto_girl_kick.gd").DURATION
 if move=="Barrier":return 1.25
 if move=="EmberHold":return 3.5
 if move=="EmberRelease":return 22.0/24.0
 if move in ["PairTeleport","PairVanish"]:return 16.0/24.0+.16+20.0/24.0
 if move=="SmokeCharge":return 100000.0
 if move=="SmokeRelease":return 1.2
 if move=="SwitchToDemon":return 1.4
 if move=="SwitchToGirl":return 1.7
 if BASIC.has(move):return BASIC[move].duration
 return Kit.duration(move) if Kit.MOVES.has(move) else .8
func present():
 if not view():return
 view().shadow_move=move
 if move=="CompanionPalm":
  view().pose_frame(704,facing);view().show_native_girl(facing);view().native_pose("Idle",elapsed,true)
  view().companion.sync_pose();return
 if move in ["ShadowChain","ShadowRecover"]:chain_animation().present();return
 if move=="AnkleRake":kick().present(elapsed);return
 if move in ["Barrier","EmberHold","EmberRelease","PairTeleport","PairVanish"]:magic().present();return
 if move=="SwitchToDemon":view().pose_frame(lerpf(733,816,clampf(elapsed/duration(),0,1)),facing)
 elif move=="SwitchToGirl":view().pose_frame(lerpf(577,704,clampf(elapsed/duration(),0,1)),facing)
 elif BASIC.has(move):
  if move in ["ForwardBackhand","GroundPalmSlam"]:view().footless_pose(move,elapsed,facing);return
  var d=BASIC[move];view().pose_frame(lerpf(d.start,d.end,clampf(elapsed/d.duration,0,1)),facing)
 elif move=="SmokeCharge":view().pose_frame(lerpf(397,444,clampf(elapsed/.45,0,1)),facing)
 elif move=="SmokeRelease":view().pose_frame(lerpf(444,576,clampf(elapsed/1.2,0,1)),facing)
 elif move=="CinderToss" and demon_form:view().pose_frame(1,facing)
 elif not move.is_empty():view().girl_pose(elapsed,facing)
func release():
 if move=="EmberHold":magic().release();return
 if move!="SmokeCharge":return
 power=clampf(actor.charge_time/1.5,0,1)
 actor.charging=false;actor.charge_time=0
 move="SmokeRelease";elapsed=0;actor.attack_cooldown=duration();actor.last_move="ORANGE SMOKE"
 present()
func cancel():
 if chain_pose:chain_pose.cancel()
 if is_instance_valid(shadow_chain):shadow_chain.hide();shadow_chain.queue_free()
 shadow_chain=null
 if girl_magic:girl_magic.cancel()
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
 if move in ["ShadowChain","ShadowRecover"] and is_instance_valid(shadow_chain):shadow_chain.tick(delta)
 if move in ["Barrier","EmberHold","EmberRelease","PairTeleport","PairVanish"]:magic().tick(delta)
 if move=="CompanionPalm":
  view().companion.tick_contact(self,previous,elapsed)
 elif move in ["ForwardBackhand","GroundPalmSlam"]:
  tick_footless(previous)
 elif BASIC.has(move):
  var d=BASIC[move]
  var impact=(d.hit-d.start)/(d.end-d.start)*d.duration
  if elapsed>=impact-.07 and previous<=impact+.09:
   var launch=Vector3(facing,.25,0)
   if move=="RisingForearm":launch=Vector3(facing*.2,1,0)
   query_hand(view().demon_point(d.bone),.19,d.damage,launch,d.kb)
   if move=="RightSwipe" or move=="RisingForearm":query_hand(view().demon_point("DEF-hand.R"),.19,d.damage,launch,d.kb)

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
 elif move=="AnkleRake":kick().tick(previous,elapsed)
 elif Kit.MOVES.has(move):
  var d=Kit.MOVES[move]
  if elapsed>=d.startup and elapsed<=d.startup+d.active:
   query_hand(view().girl_point(d.get("hand","RightHand")),.16,d.damage,Vector3(facing,.3,0),d.kb)
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
func tick_footless(previous:float):
 var d=BASIC[move]
 var first=ArmTiming.time_at(move,d.active_start);var last=ArmTiming.time_at(move,d.active_end)
 if elapsed<first or previous>last:return
 var time=clampf(elapsed,first,last)
 view().footless_pose(move,time,facing)
 var hand=view().demon_point("DEF-hand.R")
 var palm=view().demon_palm_points()
 var forearm=view().demon_point("DEF-forearm.R")
 # Bounded visible distal forearm/hand, never a foot or whole-body cone.
 for i in 4:query_hand(hand.lerp(forearm,float(i)/6.0),.19,d.damage,Vector3(facing,.25,0),d.kb,true)
 for point in palm:query_hand(point,.09,d.damage,Vector3(facing,.25,0),d.kb,true)
 if move=="GroundPalmSlam" and time>=ArmTiming.time_at(move,d.hit) and actor.is_grounded():
  var space=actor.get_world_3d().direct_space_state
  var low=hand
  for point in palm:
   if point.y<low.y:low=point
  var ray=PhysicsRayQueryParameters3D.create(low+Vector3.UP*.06,low-Vector3.UP*.12,1,[actor.get_rid()])
  var floor_hit=space.intersect_ray(ray)
  if not floor_hit.is_empty() and floor_hit.normal.y>.7 and absf(floor_hit.position.y-actor.global_position.y)<.14:
   if not impulse_done:
    impulse_done=true;smoke_origin=floor_hit.position+Vector3.UP*.035
    effect=preload("res://scripts/mephisto_palm_dust.gd").new();actor.get_parent().add_child(effect);effect.global_position=smoke_origin
   if impulse_done:query_palm_dust()
 view().footless_pose(move,elapsed,facing)
func query_palm_dust():
 for target in get_tree().get_nodes_in_group("fighters"):
  if target in targets or not actor.can_hit(target) or not target.is_grounded():continue
  if (target.global_position.x-actor.global_position.x)*facing<=0:continue
  if absf(target.global_position.y-actor.global_position.y)>.18:continue
  for shape in target.get_hurtbox_shapes():
   if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
   var half=maxf(0,shape.shape.height*.5-shape.shape.radius)
   var xf:Transform3D=shape.global_transform
   var low=xf*Vector3(0,-half,0)
   var other_end=xf*Vector3(0,half,0)
   if other_end.y<low.y:low=other_end
   var r=shape.shape.radius*maxf(xf.basis.x.length(),xf.basis.z.length())
   if low.y-r>smoke_origin.y+.3 or low.y+r<smoke_origin.y-.1:continue
   if Vector2(low.x-smoke_origin.x,low.z-smoke_origin.z).length()<=.72+r:
    targets.append(target);contacts.append({"move":"GroundPalmSlam","elapsed":elapsed,"source_frame":view().source_frame,"radius":.72,"target":target.character_id,"damage":10.0,"kind":"visible palm ground dust","point":str(smoke_origin)})
    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,10.0,Vector3(facing,.25,0),3.8,shape,low,smoke_origin,actor)
    break

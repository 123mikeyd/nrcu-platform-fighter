extends Node
# Approved v003 uppercut/recovery, isolated from unrelated production routes.
var actor
var lab_skeleton: Skeleton3D
var knockdown_phase := ""
var knockdown_clock := 0.0
const ARISE_DURATION := 1.83333329856396
const DOWN_REST := 0.80
var getup_requested := false
var getup_held := {"attack":false,"jump":false}
var release_latch: Dictionary = {}
var star_materials: Array = []
var star_clock := 0.0
var reduced_star_effect := false
var landing_pose: Array = []
var reaction_time := -1.0
var reaction_facing := 1.0
var reaction_yaw_offset := PI
var reaction_contact_frame := -1
var lab_move := ""
var lab_time := 0.0
var lab_facing := 1.0
var lab_targets: Array = []
var lab_contacts: Array = []
var lab_sample_radius := .14
var side_motion: Dictionary = {}
# Source hand extrema: R89/92, L104/107, R119/122. Recovery joins
# 96 and111 precede the next hand's anticipation;129 ends third recoil.
const SIDE_STARTS = [81.0,96.0,111.0]
const SIDE_ENDS = [96.0,111.0,129.0]
const SIDE_SPEED := 1.5
const SIDE_FINAL_RECOVERY := .16
var side_step := 0
const SIDE_BUFFER_OPEN := .06
const SIDE_CHAIN_WINDOW := .18
var side_buffered := false
var side_attack_held := false
var side_chain_remaining := 0.0
func side_reset() -> void:
 side_step=0;side_buffered=false;side_chain_remaining=0
 side_attack_held=actor._read_raw_controls(0).attack
func side_continue(aim: Vector2) -> bool:
 if side_chain_remaining<=0:return false
 if absf(aim.y)>.1 or (absf(aim.x)>.1 and signf(aim.x)!=lab_facing):
  side_reset();return false
 if not actor.controls_enabled or not actor.is_grounded() or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.shielding:
  side_reset();return false
 side_begin_next();return true
func side_begin_next() -> void:
 side_step+=1;side_buffered=false;side_chain_remaining=0
 lab_move="side_basic";lab_time=0;lab_targets.clear()
 actor.facing=lab_facing;actor.attack_cooldown=lab_duration();actor.last_move="SIDE STRIKE"
 side_attack_held=actor._read_raw_controls(0).attack

func side_source_time(t: float) -> float:
 var punch_duration=(SIDE_ENDS[side_step]-SIDE_STARTS[side_step])/30.0/SIDE_SPEED
 if side_step==2 and t>punch_duration:
  return (lerpf(129,176,clampf((t-punch_duration)/SIDE_FINAL_RECOVERY,0,1))-81)/30.0
 return (SIDE_STARTS[side_step]-81)/30.0+minf(t,punch_duration)*SIDE_SPEED

# Provisional user-requested rate; source extension accelerates at .5s,
# reaches its measured left-hand forward maximum at17/24s, then retracts.
const JAB_SPEED := 3.5
const JAB_ACTIVE_START := .5
const JAB_ACTIVE_END := 17.0/24.0
const HURT = preload("res://scripts/body_hurtboxes.gd")
func _ready():
 actor=get_parent()
 lab_skeleton=actor._visual_root.find_children("*","Skeleton3D",true,false)[0]
 var view=actor._visual_root.get_node("TekniumVisual")
 view.animation_player.add_animation_library("v004",load("res://assets/reactions/teknium_v004.tres").duplicate(true))
 view.animation_player.add_animation_library("recovery",load("res://assets/reactions/teknium_recovery.tres").duplicate(true))
 view.animation_player.add_animation_library("side_basic",load("res://assets/reactions/teknium_side_basic.tres").duplicate(true))
 view.animation_player.add_animation_library("air_up",load("res://assets/reactions/teknium_air_up.tres").duplicate(true))
 side_motion=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reactions/teknium_side_basic_motion.json"))
 build_star_materials()
func restore_lab_pose():pass
func filter_controls(input):
 for k in release_latch.keys():
  if not input[k]:release_latch.erase(k)
  else:input[k]=false
 if not knockdown_phase.is_empty():
  for k in input:input[k]=false
 if lab_move=="side_basic":
  for k in input:
   if k!="shield":input[k]=false
 return input
func before_tick(delta):
 star_clock+=delta
 tick_knockdown(delta)
 if side_chain_remaining>0:
  side_chain_remaining=maxf(0,side_chain_remaining-delta)
  var raw=actor._read_raw_controls(0)
  if side_chain_remaining<=0 or not actor.is_grounded() or not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or raw.shield or raw.jump or raw.special or raw.up or raw.down or (raw.left and lab_facing>0) or (raw.right and lab_facing<0):side_reset()
 if lab_move=="side_basic":
  var raw=actor._read_raw_controls(0)
  if raw.attack and not side_attack_held and side_step<2 and lab_time>=SIDE_BUFFER_OPEN and not raw.up and not raw.down and not raw.shield and not raw.special and not raw.jump and not (raw.left and lab_facing>0) and not (raw.right and lab_facing<0):side_buffered=true
  side_attack_held=raw.attack
 if lab_move=="side_basic" and (not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or not actor.is_grounded()):
  lab_move="";lab_targets.clear();actor.attack_cooldown=0;side_reset()
 if not lab_move.is_empty() and actor.read_controls(0).shield:
  lab_move="";lab_targets.clear();actor.attack_cooldown=0;side_reset()
func after_tick(delta):
 after_knockdown(delta)
 lab_tick(delta)
 if reaction_time>=0:present_reaction()
func clear():
 if lab_move in ["side_basic","jab","air_up"] or side_chain_remaining>0:latch_recovery_controls()
 clear_knockdown();lab_move="";lab_targets.clear();side_reset()
func after_hit(episode,old_facing):
 if episode:
  knockdown_phase="reaction";knockdown_clock=0;reaction_time=0;reaction_facing=old_facing
  reaction_contact_frame=Engine.get_physics_frames();getup_requested=false
  present_reaction()
func _input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F6:
  reduced_star_effect=not reduced_star_effect;update_protection_cue()
func build_star_materials()->void:
 if not star_materials.is_empty():return
 for mesh in actor._visual_root.find_children("*","MeshInstance3D",true,false):
  if not mesh.mesh:continue
  for surface in mesh.mesh.get_surface_count():
   var original=mesh.get_active_material(surface)
   if not original is BaseMaterial3D:continue
   var isolated=original.duplicate()
   isolated.next_pass=null
   mesh.set_surface_override_material(surface,isolated)
   star_materials.append({"material":isolated,"base":isolated.albedo_color,"texture":isolated.albedo_texture})

func is_knockdown_protected() -> bool:
 # Terrain contact is authoritative even during the inherited post-move calls,
 # before after_knockdown promotes the animation state. Never fighter tops.
 return not knockdown_phase.is_empty() and actor.controls_enabled and actor.stocks>0 and actor.is_grounded() and actor.velocity.y<=0

func clear_knockdown() -> void:
 knockdown_phase="";knockdown_clock=0;reaction_time=-1;getup_requested=false
 landing_pose.clear()
 star_clock=0
 for entry in star_materials:entry.material.albedo_color=entry.base

func latch_recovery_controls()->void:
 var raw=actor._read_raw_controls(0)
 for k in ["attack","special","jump","up","down","shield"]:
  if raw[k]:release_latch[k]=true
 actor._attack_was_down=raw.attack;actor._special_was_down=raw.special
 actor._jump_was_down=raw.jump or raw.up;actor._down_was_down=raw.down
func capture_landing_pose()->void:
 # Preserve the incoming source-clock pose in the recovery actor.facing basis.
 present_reaction()
 var hi=lab_skeleton.find_bone("Hips")
 var hip=lab_skeleton.global_transform*lab_skeleton.get_bone_global_pose(hi)
 var bones=[]
 for i in lab_skeleton.get_bone_count():bones.append(lab_skeleton.get_bone_pose(i))
 actor._visual_root.get_node("TekniumVisual").magic_pose("recovery/Arise",0,reaction_facing)
 for i in bones.size():lab_skeleton.set_bone_pose(i,bones[i])
 lab_skeleton.set_bone_pose(hi,lab_skeleton.global_transform.affine_inverse()*hip)
 lab_skeleton.force_update_all_bone_transforms()
 landing_pose.clear()
 for i in lab_skeleton.get_bone_count():landing_pose.append(lab_skeleton.get_bone_pose(i))

func present_recovery()->void:
 var clip={"join":"Join","rest":"Arise","arise":"Arise","settle":"Settle"}.get(knockdown_phase,"")
 if clip.is_empty():return
 restore_lab_pose()
 var dynamic_join=knockdown_phase=="join" and not landing_pose.is_empty()
 actor._visual_root.get_node("TekniumVisual").magic_pose("recovery/Arise" if dynamic_join else "recovery/"+clip,0.0 if dynamic_join or knockdown_phase=="rest" else knockdown_clock,reaction_facing)
 if dynamic_join:
  var weight=smoothstep(0,.35,knockdown_clock)
  for i in landing_pose.size():lab_skeleton.set_bone_pose(i,landing_pose[i].interpolate_with(lab_skeleton.get_bone_pose(i),weight))
 lab_skeleton.force_update_all_bone_transforms()

func tick_knockdown(delta:float)->void:
 if knockdown_phase.is_empty():return
 if not actor.controls_enabled or actor.freeze_remaining>0 or actor.magic_locked() or actor.stocks<=0:
  clear_knockdown();return
 var raw=actor._read_raw_controls(0)
 var fresh:bool=(raw.attack and not getup_held.attack) or (raw.jump and not getup_held.jump)
 if is_knockdown_protected() and knockdown_phase in ["join","rest"] and fresh:getup_requested=true
 getup_held={"attack":raw.attack,"jump":raw.jump}
 latch_recovery_controls()
 if knockdown_phase=="reaction" or knockdown_phase=="waiting_land":
  if Engine.get_physics_frames()!=reaction_contact_frame:reaction_time=minf(2.4,reaction_time+delta)
  if reaction_time>=2.4:knockdown_phase="waiting_land"

func after_knockdown(delta:float)->void:
 if knockdown_phase.is_empty():return
 # This runs directly after the actual inherited movement. No teleport, resource
 # grant or original-platform anchor. A support loss is a vulnerable air episode.
 if knockdown_phase in ["reaction","waiting_land"] and actor.is_grounded() and actor.velocity.y<=0:
  capture_landing_pose()
  knockdown_phase="join";knockdown_clock=0;reaction_time=2.4;star_clock=0
  actor.velocity.x=0;actor.hitstun=0
 elif knockdown_phase in ["join","rest","arise","settle"]:
  if not actor.is_grounded():
   landing_pose.clear()
   knockdown_phase="waiting_land";knockdown_clock=0;reaction_time=2.4;getup_requested=false
   update_protection_cue();return
  knockdown_clock+=delta
  var duration={"join":.35,"rest":DOWN_REST,"arise":ARISE_DURATION,"settle":.30}[knockdown_phase]
  if knockdown_clock>=duration or (knockdown_phase=="rest" and getup_requested):
   knockdown_clock=0
   if knockdown_phase=="join":knockdown_phase="arise" if getup_requested else "rest"
   elif knockdown_phase=="rest":knockdown_phase="arise"
   elif knockdown_phase=="arise":knockdown_phase="settle"
   else:
    latch_recovery_controls();clear_knockdown();actor._update_move_visuals(0,true);return
 if knockdown_phase in ["join","rest","arise","settle"]:present_recovery()
 update_protection_cue()

func update_protection_cue()->void:
 build_star_materials()
 var active=is_knockdown_protected()
 # Smooth rainbow rotation, never opacity blinking or a global flash.
 var tint=Color.from_hsv(.12 if reduced_star_effect else fposmod(star_clock/1.6,1.0),.24 if reduced_star_effect else .60,1.0)
 for entry in star_materials:
  entry.material.albedo_color=entry.base*tint if active else entry.base

func begin_uppercut_reaction()->void:
 if actor.character_id!="teknium" or not actor.controls_enabled or actor.shielding:return
 knockdown_phase="reaction";knockdown_clock=0
 reaction_time=0;reaction_facing=actor.facing;reaction_contact_frame=Engine.get_physics_frames()
 present_reaction()

func present_reaction()->void:
 if knockdown_phase in ["join","rest","arise","settle"]:
  present_recovery();return
 if reaction_time<0:return
 restore_lab_pose()
 var view=actor._visual_root.get_node("TekniumVisual")
 view.magic_pose("v004/UppercutReaction",reaction_time,reaction_facing)
 view.model.rotation.y+=reaction_yaw_offset
 lab_skeleton.force_update_all_bone_transforms()
 var hurt=actor.get_node_or_null("BodyHurtboxes")
 if hurt:hurt.sync()

func side_forward(t: float) -> float:
 var samples: Array=side_motion.forward
 var f=clampf(t*120.0,0,samples.size()-1)
 var i=int(f)
 return lerpf(samples[i][1],samples[mini(i+1,samples.size()-1)][1],f-i)

func before_move(delta: float) -> void:
 if lab_move in ["air_up"]:actor.facing=lab_facing
 if lab_move!="side_basic":return
 # Source root travel goes through the real movement capsule exactly once.
 # Normal steering is filtered; the animation has no forward root translation.
 actor.facing=lab_facing
 actor.velocity.x=(side_forward(side_source_time(minf(lab_time+delta,lab_duration())))-side_forward(side_source_time(lab_time)))*lab_facing/maxf(delta,.000001)

func side_hand(t: float) -> String:
 var frame=81+side_source_time(t)*30.0
 return "LeftHand" if frame>=101 and frame<=108 else "RightHand"

func lab_start(move: String) -> bool:
 if not knockdown_phase.is_empty():return false
 if actor.character_id!="teknium" or move not in ["uppercut","side_basic","jab","air_up"] or not actor.controls_enabled or (actor.is_grounded() if move in ["air_up"] else not actor.is_grounded()) or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.shielding or actor.attack_cooldown>0: return false
 restore_lab_pose()
 reaction_time=-1
 side_reset()
 lab_move=move;lab_time=0;lab_facing=actor.facing;lab_targets.clear();lab_contacts.clear()
 actor.attack_cooldown=lab_duration()
 if move in ["side_basic","jab"]:actor.last_move="SIDE STRIKE"
 if move=="air_up":actor.last_move="AIR BACKFLIP 33-73"
 if move=="crouch_kick":actor.last_move="CROUCH KICK"
 return true

# Halve the installed1.2s clock uniformly: source33-73 in0.6s.
# Evaluate the preserved smooth early profile at2*t (rate3x tapering to2x).
# Source poses, continuous midpoint rate/slope and contact geometry unchanged.
const AIR_UP_SPEED := 2.0
const AIR_UP_HALF_TIME := 8.0/15.0
const AIR_UP_HALF_SOURCE := 20.0/30.0
func air_up_source_time(t: float) -> float:
 t=clampf(t*AIR_UP_SPEED,0,AIR_UP_HALF_TIME+AIR_UP_HALF_SOURCE)
 if t>=AIR_UP_HALF_TIME:return AIR_UP_HALF_SOURCE+t-AIR_UP_HALF_TIME
 var u=t/AIR_UP_HALF_TIME
 return AIR_UP_HALF_TIME*(1.5*u-.5*u*u*u+.25*u*u*u*u)

func air_up_elapsed_time(source: float) -> float:
 source=clampf(source,0,2*AIR_UP_HALF_SOURCE)
 if source>=AIR_UP_HALF_SOURCE:return (AIR_UP_HALF_TIME+source-AIR_UP_HALF_SOURCE)/AIR_UP_SPEED
 var lo=0.0;var hi=AIR_UP_HALF_TIME/AIR_UP_SPEED
 for i in 32:
  var mid=(lo+hi)*.5
  if air_up_source_time(mid)<source:lo=mid
  else:hi=mid
 return (lo+hi)*.5 if source>0 else 0.0

func air_up_sample_next(t: float,end: float) -> float:
 # Source-domain240Hz also guarantees >=240Hz real-time at rates2..3.
 # Keep the exact callback endpoint; do not discard its fractional interval.
 var source_end=air_up_source_time(end)
 var next_source=air_up_source_time(t)+1.0/240.0
 return end if next_source>=source_end else air_up_elapsed_time(next_source)

func lab_present(t: float) -> Vector3:
 restore_lab_pose()
 var view=actor._visual_root.get_node("TekniumVisual")
 if lab_move=="air_up":
  view.magic_pose("air_up/Backflip33_73",air_up_source_time(t),lab_facing)
  return lab_bone_point("LeftFoot")
 if lab_move=="side_basic":
  view.magic_pose("side_basic/TripleUppercutTail",side_source_time(t),lab_facing)
  return view.hand_tip(side_hand(t))
 if lab_move=="crouch_kick":
  view.magic_pose("v004/CrouchKick",t,lab_facing)
  return lab_bone_point("LeftToeBase")
 if lab_move=="uppercut":
  view.magic_pose("v004/Uppercut",t,lab_facing)
  return view.hand_tip("RightHand")
 var source=t*JAB_SPEED
 view.magic_pose("Punch",source,lab_facing)
 view.position.y=-.106

 return view.hand_tip("LeftHand")

func lab_bone_point(name:String)->Vector3:
 return lab_skeleton.global_transform*lab_skeleton.get_bone_global_pose(lab_skeleton.find_bone(name)).origin

func lab_duration()->float:
 if lab_move=="air_up":return (AIR_UP_HALF_TIME+AIR_UP_HALF_SOURCE)/AIR_UP_SPEED
 if lab_move=="jab":return actor._visual_root.get_node("TekniumVisual").animation_player.get_animation("Punch").length/JAB_SPEED
 if lab_move=="side_basic":return (SIDE_ENDS[side_step]-SIDE_STARTS[side_step])/30.0/SIDE_SPEED+(SIDE_FINAL_RECOVERY if side_step==2 else 0.0)
 return .68 if lab_move=="crouch_kick" else (.6733333333 if lab_move=="uppercut" else .58)

func lab_active(t:float)->bool:
 if lab_move=="air_up":return air_up_source_time(t)>=(51.5-33.0)/30.0 and air_up_source_time(t)<=(60.75-33.0)/30.0
 if lab_move=="jab":return t*JAB_SPEED>=JAB_ACTIVE_START and t*JAB_SPEED<=JAB_ACTIVE_END
 if lab_move=="side_basic":
  var frame=81+side_source_time(t)*30.0
  return (frame>=86 and frame<=93) or (frame>=101 and frame<=108) or (frame>=116 and frame<=123)
 if lab_move=="uppercut":return t>=.08+1.0/30.0 and t<=.08+4.0/30.0
 return t>=.16 and t<=.30 if lab_move=="crouch_kick" else t>=.18 and t<=.27
func lab_query(point: Vector3, sample_time: float) -> void:
 var shape=SphereShape3D.new();shape.radius=.10 if lab_move=="crouch_kick" else lab_sample_radius
 var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,point);query.collision_mask=7
 HURT.prepare(actor,query)
 for hit in actor.get_world_3d().direct_space_state.intersect_shape(query,64):
  var target=HURT.resolve(hit.collider)
  if actor.can_hit(target) and target not in lab_targets:
   lab_targets.append(target)
   lab_contacts.append({"time":sample_time,"point":str(point),"target":target.character_id,"strike":side_step+1 if lab_move=="side_basic" else 0})
   if lab_move in ["jab","air_up"]:
    lab_contacts[-1].merge({"source_time":sample_time*JAB_SPEED if lab_move=="jab" else air_up_source_time(sample_time),"radius":shape.radius,"target_origin":str(target.global_position),"collider":str(hit.collider.name),"shape":hit.shape,"receiver":"fitted anatomy" if hit.collider.has_meta("hurtbox_actor") else "existing movement capsule"})
   var reaction_allowed=lab_move=="uppercut" and target.character_id=="teknium" and not target.shielding
   hit.position=point # Actual sampled hand/forearm query, not target-origin aim.
   if lab_move=="side_basic":
    # Eight total across three fresh presses, once per target per strike.
    HURT.deliver(target,[2.5,2.5,3.0][side_step],Vector3(lab_facing,0,0),3.8,hit, actor)
   elif lab_move in ["air_up"]:
    HURT.deliver(target,8.0,Vector3(lab_facing,0,0),3.8,hit, actor)
   else:
    HURT.deliver(target,10.0 if lab_move=="uppercut" else 8.0,Vector3(lab_facing*.2,1,0) if lab_move=="uppercut" else Vector3(lab_facing,0 if lab_move=="jab" else .12,0),6.0 if lab_move=="uppercut" else (3.8 if lab_move in ["crouch_kick","jab"] else 2.0),hit, actor)
   if reaction_allowed and target.has_method("begin_uppercut_reaction"):target.begin_uppercut_reaction()

func lab_tick(delta: float) -> void:
 if lab_move.is_empty(): return
 if not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or (actor.is_grounded() if lab_move in ["air_up"] else not actor.is_grounded()):
  if lab_move in ["air_up"]:actor.attack_cooldown=0;latch_recovery_controls()
  lab_move="";lab_targets.clear();side_reset();restore_lab_pose();return
 var duration=lab_duration()
 var end=minf(lab_time+delta,duration)
 var t=lab_time
 while t<end-.000001:
  t=air_up_sample_next(t,end) if lab_move=="air_up" else minf(t+1.0/240.0,end)
  var point=lab_present(t)
  if lab_active(t) and lab_move=="air_up":
   # Native feet and shin segments, overhead only; controller owns travel.
   var hips=lab_bone_point("Hips")
   for side in ["Left","Right"]:
    var knee=lab_bone_point(side+"Leg");var ankle=lab_bone_point(side+"Foot");var toe=lab_bone_point(side+"ToeBase")
    lab_sample_radius=.10
    for fraction in [0.0,.25,.5,.75,1.0]:
     var shin=knee.lerp(ankle,fraction)
     if shin.y>hips.y:lab_query(shin,t)
     var foot=ankle.lerp(toe,fraction)
     if foot.y>hips.y:lab_query(foot,t)
  elif lab_active(t):
   lab_sample_radius=.14;lab_query(point,t)
   if lab_move in ["uppercut","side_basic","jab"]:
    # Actual native forearm core and palm, not extra forward reach.
    var hand=side_hand(t) if lab_move=="side_basic" else ("LeftHand" if lab_move=="jab" else "RightHand")
    var elbow=lab_bone_point("LeftForeArm" if hand=="LeftHand" else "RightForeArm");var wrist=lab_bone_point(hand)
    lab_sample_radius=elbow.distance_to(wrist)*.32
    for fraction in [0.0,.33,.66,1.0]:lab_query(elbow.lerp(wrist,fraction),t)
    lab_sample_radius=.10;lab_query(wrist.lerp(point,.5),t)
    lab_sample_radius=.14
   if lab_move=="crouch_kick":lab_query(point.lerp(lab_bone_point("LeftFoot"),.5),t)
 lab_time=end
 lab_present(end)
 if lab_time>=duration:
  if lab_move in ["jab","air_up"]:
   actor.attack_cooldown=0;lab_targets.clear();latch_recovery_controls()
  if lab_move=="side_basic":
   actor.velocity.x=0;actor.attack_cooldown=0;lab_targets.clear()
   if side_buffered and side_step<2:
    side_begin_next();lab_present(0);return
   side_chain_remaining=SIDE_CHAIN_WINDOW if side_step<2 else 0.0
   latch_recovery_controls()
  lab_move="";restore_lab_pose();actor._update_move_visuals(0,true)
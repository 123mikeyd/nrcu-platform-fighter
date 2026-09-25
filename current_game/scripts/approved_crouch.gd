extends Node
# Approved Tek v004, Turbo corrected v005 motion, and Doge static endpoint.
# Tek/Turbo 2s authored entry maps to .30s responsive gameplay (timing not art approval).
# Doge .18s reversible FK blend is gameplay transition, not authored animation.
var actor
var view
var skeleton: Skeleton3D
var phase := "idle"
var amount := 0.0
var hold_time := 0.0
var standing: Array[Transform3D] = []
var endpoint: Array[Transform3D] = []
var duration := 0.3
func _ready():
 actor=get_parent()
 view=actor._visual_root.get_node({"teknium":"TekniumVisual","doge_man":"DogeVisual","turbofit":"TurboFitVisual"}[actor.character_id])
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 var stamp="20260920" if actor.character_id=="turbofit" else "20260919"
 var library=load("res://assets/"+actor.character_id+"/approved_crouch_"+stamp+".tres")
 view.animation_player.add_animation_library("crouch",library)
 if actor.character_id=="doge_man":
  duration=.18
  var ap=view.animation_player
  ap.play("Idle",0);ap.seek(0,true);ap.pause()
  for b in skeleton.get_bone_count():standing.append(skeleton.get_bone_pose(b))
  ap.play("crouch/Hold",0);ap.seek(0,true);ap.pause()
  for b in skeleton.get_bone_count():endpoint.append(skeleton.get_bone_pose(b))
  view.current_clip="";view.sync_pose("idle",actor.facing,.4,.42,.18,.6)
func allowed() -> bool:
 if not actor.controls_enabled or actor.stocks<=0 or not actor.is_grounded() or actor.velocity.y>0.01:return false
 if actor.hitstun>0 or actor.freeze_remaining>0 or actor.counter_hitstop>0 or actor.magic_locked() or actor.charging or actor.attack_cooldown>0 or actor.landing_lag>0:return false
 if actor.tumble and actor.tumble.active:return false
 if actor.revival and actor.revival.phase!="idle":return false
 if actor.reaction_recovery and (not actor.reaction_recovery.knockdown_phase.is_empty() or not actor.reaction_recovery.lab_move.is_empty()):return false
 if actor.teknium_specials and actor.teknium_specials.phase!="idle":return false
 if actor.doge_counter and actor.doge_counter.phase!="idle":return false
 if actor.doge_ground_rush and actor.doge_ground_rush.phase!="idle":return false
 if not actor.doge_attack_clip.is_empty() or actor.torpedo_phase!="idle":return false
 if actor.doge_ground_basic and not actor.doge_ground_basic.clip.is_empty():return false
 return true
func cancel():
 if phase=="idle":return
 phase="idle";amount=0;hold_time=0
 view.current_clip=""
 view.animation_player.speed_scale=1
 # Native presenter owns the next pose; never restore collision or movement tuning.
func guard():
 if not allowed():cancel()
func present(delta:float,interrupted:bool) -> bool:
 if interrupted or not allowed():cancel();return false
 var input=actor._read_raw_controls(0)
 if input.left or input.right or input.up or input.jump or absf(actor.velocity.x)>.2:
  cancel();return false
 var down:bool=input.down and (not input.attack or actor.character_id=="doge_man") and not input.special
 if phase=="idle" and not down:return false
 var old=amount
 amount=move_toward(amount,1.0 if down else 0.0,maxf(delta,0)/duration)
 if amount<=0:
  cancel();return false
 phase="hold" if amount>=1 else ("enter" if amount>=old else "exit")
 actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 view.model.rotation.y=actor.facing*PI/2
 if actor.character_id in ["teknium","turbofit"]:
  if phase=="hold":hold_time+=maxf(delta,0)
  else:hold_time=0
  # Authored exit reverses entry; scalar reversal also handles short taps.
  var source=2.0+fmod(hold_time,2.0) if phase=="hold" else amount*2.0
  if actor.character_id=="teknium":
   view.magic_pose("crouch/Full",source,actor.facing)
  else:
   view.falling=false;view.landing_remaining=0
   view.cancel_power_chord()
   view.current_clip="crouch/Full"
   view.animation_player.play("crouch/Full",0)
   view.animation_player.speed_scale=0
   view.animation_player.seek(source,true)
   skeleton.force_update_all_bone_transforms()
 else:
  view.flight_root.rotation=Vector3.ZERO
  view.current_clip="crouch/Hold"
  view.animation_player.pause()
  var weight=smoothstep(0,1,amount)
  for b in skeleton.get_bone_count():
   skeleton.set_bone_pose(b,standing[b].interpolate_with(endpoint[b],weight))
  skeleton.force_update_all_bone_transforms()
 sync_receivers()
 return true
func sync_receivers():
 # Fitted Tek receivers must not remain at the last crouch sample on release.
 # Doge deliberately retains the pre-existing movement-capsule fallback.
 var hurt=actor.get_node_or_null("BodyHurtboxes")
 if hurt:hurt.sync()

extends Node
# Mike's approved crouch holds (2026-09-28): Doge, Tek and TurboFit each use their own static hold
# pose from the approved crouch library (approved_crouch_20260928.tres "Hold").
# Entry/exit are a responsive reversible FK blend (gameplay transition, not authored animation):
# Doge .18s, Tek/Turbo .30s. The previous authored Tek v004 / Turbo v005 libraries stay on disk.
# A grounded down-basic started from the crouch begins on the crouch pose and blends into the attack.
const STAMP := "20260928"
const ATTACK_BLEND := 0.12
var actor
var view
var skeleton: Skeleton3D
var phase := "idle"
var amount := 0.0
var hold_time := 0.0
var standing: Array[Transform3D] = []
var endpoint: Array[Transform3D] = []
var entry_from: Array[Transform3D] = []
var base_y := 0.0
var duration := 0.3
var attack_modifier: SkeletonModifier3D
func _ready():
 actor=get_parent()
 view=actor._visual_root.get_node({"teknium":"TekniumVisual","doge_man":"DogeVisual","turbofit":"TurboFitVisual"}[actor.character_id])
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 var library=load("res://assets/"+actor.character_id+"/approved_crouch_"+STAMP+".tres")
 view.animation_player.add_animation_library("crouch",library)
 duration=.18 if actor.character_id=="doge_man" else .3
 var ap=view.animation_player
 ap.play("Idle",0);ap.seek(0,true);ap.pause()
 for b in skeleton.get_bone_count():standing.append(skeleton.get_bone_pose(b))
 ap.play("crouch/Hold",0);ap.seek(0,true);ap.pause()
 for b in skeleton.get_bone_count():endpoint.append(skeleton.get_bone_pose(b))
 view.current_clip=""
 if actor.character_id=="doge_man":view.sync_pose("idle",actor.facing,.4,.42,.18,.6)
 attack_modifier=preload("res://scripts/crouch_attack_blend.gd").new()
 attack_modifier.name="CrouchAttackBlend";attack_modifier.pose=endpoint;attack_modifier.active=false
 skeleton.add_child(attack_modifier)
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
 if actor.character_id=="turbofit" and not actor.turbofit_attack_clip.is_empty():return false
 return true
func attack_started() -> bool:
 return actor.is_grounded() and actor.hitstun<=0 and (actor.attack_cooldown>0 or (actor.character_id=="turbofit" and not actor.turbofit_attack_clip.is_empty()))
func cancel():
 if phase=="idle":return
 # A down-basic launched from the crouch starts on the crouch pose (Doge's cape attack does this itself).
 if actor.character_id!="doge_man" and amount>=.5 and attack_started():attack_modifier.start(ATTACK_BLEND*amount)
 phase="idle";amount=0;hold_time=0
 view.current_clip=""
 view.animation_player.speed_scale=1
 if actor.character_id!="teknium":view.position.y=base_y
 # Native presenter owns the next pose; never restore collision or movement tuning.
func guard():
 if not allowed():cancel()
func present(delta:float,interrupted:bool) -> bool:
 if interrupted or not allowed():cancel();return false
 var input=actor._read_raw_controls(0)
 if input.left or input.right or input.up or input.jump or absf(actor.velocity.x)>.2:
  cancel();return false
 var down:bool=input.down and not input.special
 if phase=="idle" and not down:return false
 var old=amount
 if phase=="idle":
  # Start from whatever the presenter shows now (idle, mosh idle, end of an attack): no pop.
  entry_from.clear()
  for b in skeleton.get_bone_count():entry_from.append(skeleton.get_bone_pose(b))
  base_y=view.position.y
  attack_modifier.stop()
 amount=move_toward(amount,1.0 if down else 0.0,maxf(delta,0)/duration)
 if amount<=0:
  cancel();return false
 phase="hold" if amount>=1 else ("enter" if amount>=old else "exit")
 hold_time=hold_time+maxf(delta,0) if phase=="hold" else 0.0
 actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 view.model.rotation.y=actor.facing*PI/2
 if actor.character_id=="turbofit":
  view.falling=false;view.landing_remaining=0
  view.cancel_power_chord()
 if actor.character_id=="doge_man":view.flight_root.rotation=Vector3.ZERO
 view.current_clip="crouch/Hold"
 view.animation_player.pause()
 var weight=smoothstep(0,1,amount)
 var from:Array[Transform3D]=entry_from if phase!="exit" and entry_from.size()==skeleton.get_bone_count() else standing
 for b in skeleton.get_bone_count():
  skeleton.set_bone_pose(b,from[b].interpolate_with(endpoint[b],weight))
 # Tek's presenter lifts Idle by a floor offset; the crouch hold is authored on the floor (y=0).
 view.position.y=lerpf(base_y,0.0,weight)
 if actor.character_id=="teknium":
  view.placement_from=view.position.y;view.placement_target=view.position.y;view.placement_elapsed=.06
 skeleton.force_update_all_bone_transforms()
 sync_receivers()
 return true
func sync_receivers():
 # Fitted Tek receivers must not remain at the last crouch sample on release.
 # Doge deliberately retains the pre-existing movement-capsule fallback.
 var hurt=actor.get_node_or_null("BodyHurtboxes")
 if hurt:hurt.sync()

extends Node
# Approved source breathing; entry/release are presentation-only 0.18s blends.
# No movement capsule or damage-receiver redesign.
var actor
var view
var skeleton: Skeleton3D
var phase := "idle"
var elapsed := 0.0
var hold_time := 0.0
var from_pose: Array[Transform3D] = []
var from_prop: Transform3D
var from_y := 0.0
const TRANSITION := 0.18
func _ready():
 actor=get_parent()
 view=actor._visual_root.get_node("WitcheerVisual")
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
func allowed() -> bool:
 if not actor.controls_enabled or actor.stocks<=0 or not actor.is_grounded() or actor.velocity.y>0.01:return false
 if actor.hitstun>0 or actor.freeze_remaining>0 or actor.counter_hitstop>0 or actor.magic_locked() or is_instance_valid(actor.caught_by) or actor.charging or actor.attack_cooldown>0 or actor.landing_lag>0:return false
 if not actor.witcheer_clip.is_empty() or actor.shielding:return false
 if actor.tumble and actor.tumble.active:return false
 if actor.revival and actor.revival.phase!="idle":return false
 if actor.reaction_recovery and (not actor.reaction_recovery.knockdown_phase.is_empty() or not actor.reaction_recovery.lab_move.is_empty()):return false
 return true
func capture():
 from_pose.clear()
 for b in skeleton.get_bone_count():from_pose.append(skeleton.get_bone_pose(b))
 from_prop=view.cane.transform;from_y=view.position.y;elapsed=0.0
func cancel():
 if phase=="idle":return
 phase="idle";elapsed=0;hold_time=0
 view.cane.visible=false;view.cane.transform=view.cane_idle_transform
 view.position.y=view.FLOOR_OFFSET
func guard():
 if not allowed():cancel()
func finish_poke():
 # Completion owns the exact approved base, never an intervening Run/idle pose.
 view.show_move("CrouchBreathingV001",0,actor.facing)
 phase="hold";hold_time=0;elapsed=TRANSITION
func present(delta:float,interrupted:bool) -> bool:
 if interrupted or not allowed():cancel();return false
 var input=actor._read_raw_controls(0)
 if input.left or input.right or input.up or input.jump or absf(actor.velocity.x)>.2:
  cancel();return false
 var down:bool=input.down and not input.special
 if phase=="idle":
  if not down:return false
  capture();phase="enter";hold_time=0
 elif (not down and phase!="exit") or (down and phase=="exit"):
  capture();phase="enter" if down else "exit"
 elapsed+=maxf(delta,0)
 actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 view.model.rotation.y=actor.facing*PI/2
 if phase=="exit":
  view.sync_pose(true,Vector3.ZERO,false,false,actor.facing)
  view.animation_player.seek(0,true);view.animation_player.pause()
 else:
  if phase=="hold":hold_time+=maxf(delta,0)
  view.show_move("CrouchBreathingV001",fmod(hold_time,2.0),actor.facing)
 if phase!="hold":
  var weight:float=smoothstep(0,1,minf(elapsed/TRANSITION,1))
  for b in skeleton.get_bone_count():skeleton.set_bone_pose(b,from_pose[b].interpolate_with(skeleton.get_bone_pose(b),weight))
  view.cane.transform=from_prop.interpolate_with(view.cane.transform,weight)
  view.position.y=lerpf(from_y,view.position.y,weight)
  if elapsed>=TRANSITION:
   if phase=="exit":phase="idle";return false
   phase="hold"
 skeleton.force_update_all_bone_transforms();sync_receivers()
 return true
func sync_receivers():
 var hurt=actor.get_node_or_null("BodyHurtboxes")
 if hurt:hurt.sync()

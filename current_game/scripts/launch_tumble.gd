extends Node
# Strong-launch flight owns movement only through hitstun. No new authored pose.
const THRESHOLD := 12.0
const DANGER_SPEED := 7.0
const DRAG := 1.55
const MAX_TIME := 1.6
var actor
var active := false
var clock := 0.0
var pause_remaining := 0.0
var source: Node
var recipients: Array = []
var ignored: Array = []
var collateral_allowed := true
var effects
var launch_speed := 0.0
var paused_players: Array = []
func _ready():actor=get_parent()
func begin(attacker: Node, collateral := false):
 clear()
 if collateral or actor.shielding or actor.velocity.length()<THRESHOLD:return
 active=true;source=attacker;collateral_allowed=not collateral
 # Horizontal strong ground blows need lift to enter flight; downward spikes stay downward.
 if actor.is_grounded() and actor.velocity.y>=0:actor.velocity.y=maxf(actor.velocity.y,3.8)
 launch_speed=actor.velocity.length()
 if effects==null:
  effects=preload("res://scripts/tumble_effects.gd").new()
  actor.add_child(effects);effects.setup(actor)
 effects.impact(actor.global_position+Vector3.UP,1.0)
 pause_remaining=.055
 if is_instance_valid(source) and source.get("tumble")!=null:
  source.tumble.pause_remaining=maxf(source.tumble.pause_remaining,.055)
 ignore_fighters()
func ignore_fighters():
 for other in get_tree().get_nodes_in_group("fighters"):
  if other==actor or other in ignored:continue
  actor.add_collision_exception_with(other)
  other.add_collision_exception_with(actor)
  ignored.append(other)
func clear():
 if actor and actor.has_node("ReviewAir"):actor.get_node("ReviewAir").finish()
 restore_players()
 active=false;clock=0;pause_remaining=0;source=null;recipients.clear()
 if effects:effects.clear()
 for other in ignored:
  if is_instance_valid(other):
   if other.get("tumble")!=null and other.tumble.active:continue
   actor.remove_collision_exception_with(other)
   other.remove_collision_exception_with(actor)
 ignored.clear()
func tick(delta: float) -> bool:
 if effects:effects.update(delta,active and dangerous(),clock,minf(launch_speed,actor.velocity.length()))
 if not actor.controls_enabled or actor.stocks<=0 or actor.freeze_remaining>0 or is_instance_valid(actor.caught_by):
  clear();return false
 if active or pause_remaining>0:
  var held=actor._read_raw_controls(delta)
  actor._attack_was_down=held.attack
  actor._special_was_down=held.special
  actor._jump_was_down=held.jump or held.up
  actor._down_was_down=held.down
 if pause_remaining>0:
  if paused_players.is_empty():
   for player in actor._visual_root.find_children("*","AnimationPlayer",true,false):
    paused_players.append({"player":player,"mode":player.process_mode})
    player.process_mode=Node.PROCESS_MODE_DISABLED
   if actor.fitted_reaction:
    paused_players.append({"player":actor.fitted_reaction,"mode":actor.fitted_reaction.process_mode})
    actor.fitted_reaction.process_mode=Node.PROCESS_MODE_DISABLED
  pause_remaining=maxf(0,pause_remaining-delta)
  return true
 restore_players()
 if not active:return false
 clock+=delta
 launch_speed*=exp(-DRAG*delta)
 ignore_fighters()
 actor.hitstun=maxf(0,actor.hitstun-delta)
 actor.velocity*=exp(-DRAG*delta)
 actor.velocity.y=maxf(actor.velocity.y-actor.GRAVITY*delta,-actor.MAX_FALL_SPEED)
 actor._update_platform_collisions(delta)
 var start: Vector3 = actor.global_position
 actor.move_and_slide()
 contact_sweep(start, actor.global_position)
 actor._floor_contacts_valid=true
 actor.global_position.z=0
 # Existing reaction presentation is provisional until Mike authors tumble.
 var saved=actor.hitstun
 actor.hitstun=maxf(saved,.001)
 actor._update_move_visuals(delta)
 actor.hitstun=saved
 if actor.fitted_reaction:
  if actor.character_id=="doge_man":actor.fitted_reaction.trial_present(clock,true)
  else:
   actor.fitted_reaction.begin("body",signf(actor.velocity.x))
   actor.fitted_reaction.present_sample(minf(clock,.18))
 if actor.has_node("ReviewAir"):actor.get_node("ReviewAir").present(clock,true)
 if actor.hitstun<=0 or actor.is_grounded() or clock>=MAX_TIME:
  # This tick already moved and latched blocked inputs. Keep its true return:
  # ordinary control resumes next tick, never a second gravity/movement pass.
  # End collateral/passthrough ownership with flight; retain velocity/resources.
  clear()
  if actor.fitted_reaction:actor.fitted_reaction.clear()
  actor._update_move_visuals(0)
  if actor.is_grounded():actor.reset_air_resources()
 if actor.global_position.y < -8 or absf(actor.global_position.x)>16 or actor.global_position.y>15:
  actor._handle_blast_zone()
 return true

func contact_sweep(start: Vector3, finish: Vector3):
 if not collateral_allowed or not dangerous() or not is_instance_valid(source):return
 for target in get_tree().get_nodes_in_group("fighters"):
  if target==actor or target==source or target in recipients or not source.can_hit(target):continue
  # Sum of unchanged upright capsules, swept over stage-clipped travel.
  var a = actor.find_children("*","CollisionShape3D",false,false)[0]
  var b = target.find_children("*","CollisionShape3D",false,false)[0]
  var radius: float = a.shape.radius+b.shape.radius
  var half_axis: float = (a.shape.height+b.shape.height)*.5-radius
  var center: Vector3 = target.global_position+b.position
  var pair=Geometry3D.get_closest_points_between_segments(start+a.position,finish+a.position,center+Vector3.UP*half_axis,center-Vector3.UP*half_axis)
  if pair[0].distance_squared_to(pair[1])>radius*radius:continue
  recipients.append(target)
  if effects:effects.impact(pair[0],clampf(launch_speed/17,0,1))
  target.receive_hit_from(3.0,Vector3(signf(actor.velocity.x),.25,0),2.0,source,true)

func dangerous() -> bool:
 return active and launch_speed>=DANGER_SPEED and actor.velocity.length()>=DANGER_SPEED

func restore_players():
 for entry in paused_players:
  if is_instance_valid(entry.player):entry.player.process_mode=entry.mode
 paused_players.clear()

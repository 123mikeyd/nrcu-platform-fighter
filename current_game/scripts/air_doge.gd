extends Node
# Isolated Air Doge: native imported skeleton, gameplay seconds, grab-only GGB hull.
const Receivers=preload("res://scripts/body_hurtboxes.gd")
const START_TIME=0.16
const ACTIVE_TIME=0.40
const PHOTO_TIME=0.26
const THROW_TIME=0.12
const LANDING_RECOVERY_TIME=0.20
const RADIUS=0.36
const FORWARD=0.16
const BONUS=2.5
const GLOVE=Vector3(3.42368269,9.83053112,0.96084452)
var actor
var view
var skeleton:Skeleton3D
var bone:int
var phase="idle"
var elapsed=0.0
var facing=1.0
var kind="GROUND"
var branch="MISS"
var victim
var grip_offset=Vector3.ZERO
var previous=Vector3.ZERO
var previous_valid=false
var actor_stock=0
var victim_stock=0
var accepted_starts=0
var active_ticks=0
var boost_count=0
var damage_count=0
var cue_count=0
var contact_log=[]
var added_actor_exception=false
var added_victim_exception=false
var debug_visible=false
var debug_mesh:MeshInstance3D
var debug_sweep:MeshInstance3D
var ggb_receivers={}
var audio:AudioStreamPlayer
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual")
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0];bone=skeleton.find_bone("RightHand")
 debug_mesh=MeshInstance3D.new();debug_mesh.mesh=SphereMesh.new();debug_mesh.mesh.radius=RADIUS;debug_mesh.mesh.height=RADIUS*2
 var mat=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.albedo_color=Color(0,1,1,.22);debug_mesh.material_override=mat
 actor.add_child(debug_mesh);debug_mesh.visible=false
 debug_sweep=MeshInstance3D.new();debug_sweep.mesh=CapsuleMesh.new();debug_sweep.mesh.radius=RADIUS;debug_sweep.material_override=mat;actor.add_child(debug_sweep);debug_sweep.visible=false
 audio=AudioStreamPlayer.new();audio.stream=load("res://assets/airdoge_shutter.wav");audio.volume_db=-15;add_child(audio)
func active():return phase!="idle"
func _input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F8:
  debug_visible=not debug_visible
  if not debug_visible:debug_mesh.visible=false;debug_sweep.visible=false
func valid_actor():
 return is_instance_valid(actor) and actor.controls_enabled and actor.stocks>0 and actor.hitstun<=0 and actor.freeze_remaining<=0 and not is_instance_valid(actor.caught_by)
func start():
 if active() or actor.recovery_spent or not valid_actor():return false
 kind="GROUND" if actor.is_grounded() else "AIR"
 actor.cancel_for_grab()
 actor.recovery_spent=true;actor.jumps_used=2;actor_stock=actor.stocks;facing=actor.facing
 actor.velocity=Vector3(4*facing,13.5,0);actor.recovery_active=0;actor.attack_flash_time=0;actor.attack_cooldown=.56
 actor.last_move="JORDAN AIR DOGE"
 phase="start";elapsed=0;branch="MISS";previous_valid=false;accepted_starts+=1;active_ticks=0;boost_count=0;damage_count=0;cue_count=0;contact_log.clear()
 present();return true
func hand_world()->Vector3:
 skeleton.force_update_all_bone_transforms()
 return skeleton.global_transform*skeleton.get_bone_global_pose(bone)*GLOVE
func center()->Vector3:return hand_world()+Vector3(facing*FORWARD,0,0)
func source_frame()->float:
 match phase:
  "start":return lerpf(1,14,clampf(elapsed/START_TIME,0,1))
  "catch":return lerpf(14,28,clampf(elapsed/ACTIVE_TIME,0,1))
  "photo":return lerpf(28,36,clampf(elapsed/PHOTO_TIME,0,1))
  "throw":return lerpf(36,43,clampf(elapsed/THROW_TIME,0,1))
  "fall":
   # Finish the approved tuck-to-extension once, then keep its late extended
   # motion alive on long drops. Reuse source poses, never a hurt spin or a
   # held landing/crouch endpoint; terrain alone enters frames 88..114.
   if elapsed<=.65:return lerpf(45,88,elapsed/.65)
   return 74.0+14.0*cos((elapsed-.65)*TAU/1.2) # smooth 60..88 extension cycle
  "landing":return lerpf(88,114,clampf(elapsed/LANDING_RECOVERY_TIME,0,1))
 return 1
func present():
 if not active():return
 actor.facing=facing;actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 view.flight_root.rotation=Vector3.ZERO;view.model.rotation.y=facing*PI/2
 var clip="AirDoge_"+kind+"_"+branch
 if view.current_clip!=clip:view.animation_player.play(clip,0)
 view.current_clip=clip;view.animation_player.speed_scale=0;view.animation_player.seek((source_frame()-1)/30.0,true)
 debug_mesh.visible=debug_visible and phase=="catch";debug_mesh.global_position=center()
 if phase!="catch":debug_sweep.visible=false
func watchdog():
 if not active():return
 if not valid_actor() or actor.stocks!=actor_stock:cancel();return
 if is_instance_valid(victim) and (not victim.controls_enabled or victim.stocks!=victim_stock or victim.freeze_remaining>0 or victim.hitstun>0 or victim.caught_by!=self):cancel()
func before_input(delta):
 # Release before input eligibility/arbitration, not one frame after dispatch.
 # Keep the authored endpoint while sharing one clock with the landing lock.
 if phase=="landing" and elapsed+delta+0.000001>=LANDING_RECOVERY_TIME:
  elapsed=LANDING_RECOVERY_TIME;present();actor.landing_lag=0;cancel()
func before_move(delta,input):
 watchdog()
 if not active():return
 if phase in ["photo","throw"]:actor.velocity=Vector3.ZERO
 elif phase=="landing":actor.velocity.x=0
 elif phase=="fall":
  var axis=float(int(input.right)-int(input.left))
  if axis!=0:actor.velocity.x=move_toward(actor.velocity.x,axis*4,actor.AIR_ACCELERATION*delta)
 elapsed+=delta
 if phase=="start" and elapsed+0.000001>=START_TIME:
  phase="catch";elapsed=0;previous_valid=false
 elif phase=="photo" and elapsed+0.000001>=PHOTO_TIME:phase="throw";elapsed=0
 elif phase=="throw" and elapsed+0.000001>=THROW_TIME:release_success()

 if phase=="photo" and cue_count<3 and elapsed>=float(cue_count)*.08:audio.play();cue_count+=1
 present()
func after_move(delta):
 if not active():return
 if phase not in ["start","landing"] and actor.is_grounded() and actor.velocity.y<=0:
  detach();phase="landing";elapsed=0;actor.landing_lag=LANDING_RECOVERY_TIME
 present()
 if phase=="catch" and delta>0:
  # Half-open [0,.40): exactly 24 samples at nominal 60 Hz including entry.
  if elapsed<ACTIVE_TIME-0.000001:
   active_ticks+=1;capture()
  else:phase="fall";elapsed=0;previous_valid=false
func eligible(t):
 return is_instance_valid(t) and t.has_method("cancel_for_grab") and actor.can_hit(t) and t.stocks>0 and t.freeze_remaining<=0 and t.hitstun<=0 and t.grab_immunity<=0 and not t.shielding and not t.magic_locked()
func clear_path(a:Vector3,b:Vector3,_target=null)->bool:
 if a.distance_squared_to(b)<.000001:return true
 var q=PhysicsRayQueryParameters3D.create(a,b,3);q.hit_from_inside=true
 var exclude:Array[RID]=[]
 for f in get_tree().get_nodes_in_group("fighters"):exclude.append(f.get_rid())
 q.exclude=exclude
 return actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
func sync_ggb():
 for f in get_tree().get_nodes_in_group("fighters"):
  if f.character_id!="ggb":continue
  var mesh=f._visual_root.get_node("GGBVisual").meshes[0]
  if not ggb_receivers.has(f):
   var b=StaticBody3D.new();b.name="AirDogeOnlyBodyHull";b.collision_layer=0;b.collision_mask=0;b.set_meta("hurtbox_actor",f)
   var s=CollisionShape3D.new();s.shape=mesh.mesh.create_convex_shape(true,true);b.add_child(s);f.add_child(b);ggb_receivers[f]=b
  var body=ggb_receivers[f];body.global_transform=mesh.global_transform;body.collision_layer=0;body.force_update_transform()
func query_hulls(enabled):
 # Default-mask rays in unrelated attacks must NEVER see these grab-only hulls.
 # Enabled only inside this synchronous query, with no awaits/callback dispatch.
 for f in ggb_receivers:
  if is_instance_valid(f) and is_instance_valid(ggb_receivers[f]):
   ggb_receivers[f].collision_layer=8 if enabled and eligible(f) else 0
func capture():
 sync_ggb()
 query_hulls(true)
 var c=center();var old=previous if previous_valid else c;previous=c;previous_valid=true
 var q=PhysicsShapeQueryParameters3D.new();q.collision_mask=12;q.margin=0;q.exclude=[actor.get_rid()]
 var distance=old.distance_to(c)
 if distance<.000001:
  q.shape=SphereShape3D.new();q.shape.radius=RADIUS;q.transform.origin=c
 else:
  q.shape=CapsuleShape3D.new();q.shape.radius=RADIUS;q.shape.height=distance+2*RADIUS
  q.transform=Transform3D(Basis(Quaternion(Vector3.UP,(c-old).normalized())),(c+old)*.5)
 Receivers.prepare(actor,q)
 debug_sweep.visible=debug_visible and distance>.000001
 if debug_sweep.visible:
  debug_sweep.mesh.height=distance+2*RADIUS;debug_sweep.global_transform=q.transform
 var space=actor.get_world_3d().direct_space_state
 var hits=space.intersect_shape(q,64)

 hits.sort_custom(func(a,b):return a.collider.get_instance_id()<b.collider.get_instance_id())
 for hit in hits:
  var t=Receivers.resolve(hit.collider)
  if not eligible(t):continue
  var contact=Receivers.shape_contact(space,q,hit,hits)
  if contact.is_empty():continue
  if not clear_path(actor.global_position+Vector3.UP,c,t) or not clear_path(old,c,t) or not clear_path(c,contact.position,t):continue
  query_hulls(false)
  victim=t;victim_stock=t.stocks
  grip_offset=t.global_position-hand_world()
  t.cancel_for_grab();t.caught_by=self;t.velocity=Vector3.ZERO
  added_actor_exception=not t in actor.get_collision_exceptions();added_victim_exception=not actor in t.get_collision_exceptions()
  if added_actor_exception:actor.add_collision_exception_with(t)
  if added_victim_exception:t.add_collision_exception_with(actor)
  contact_log.append({"target":t.character_id,"collider":str(hit.collider.name),"active_seconds":elapsed,"hand":str(hand_world()),"witness":str(contact.position),"sweep_length":distance})
  branch="SUCCESS";phase="photo";elapsed=0;actor.velocity=Vector3.ZERO;previous_valid=false;present();audio.play();cue_count=1
  return
 query_hulls(false)
func anchor()->Vector3:return hand_world()+grip_offset
func follow_caught(delta):
 if not is_instance_valid(victim):return
 var dest=anchor();dest.z=0
 if not clear_path(victim.global_position+Vector3.UP,dest+Vector3.UP,victim):cancel();return
 victim.velocity=(dest-victim.global_position)/maxf(.001,delta)
func detach():
 if is_instance_valid(victim):
  if victim.caught_by==self:
   victim.caught_by=null;victim.grab_immunity=1;victim._visual_root.position=Vector3.ZERO;victim._resume_frozen_animation()
  if added_actor_exception:actor.remove_collision_exception_with(victim)
  if added_victim_exception:victim.remove_collision_exception_with(actor)
 victim=null;added_actor_exception=false;added_victim_exception=false
func release_success():
 if not is_instance_valid(victim) or damage_count>0:cancel();return
 var t=victim;detach();phase="fall";elapsed=0
 t.receive_hit_from(5,Vector3.DOWN,4,actor);t.velocity=Vector3(0,-12,0)
 damage_count+=1;actor.velocity.y=BONUS;boost_count+=1
func cancel():
 query_hulls(false)
 detach();phase="idle";elapsed=0;previous_valid=false
 if debug_mesh:debug_mesh.visible=false
 if debug_sweep:debug_sweep.visible=false
 if view:view.current_clip=""
 if audio:audio.stop()
func _exit_tree():
 detach()
 for f in ggb_receivers:
  if is_instance_valid(ggb_receivers[f]):ggb_receivers[f].queue_free()

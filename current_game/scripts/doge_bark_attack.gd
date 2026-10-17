extends Node
# All-fours bark animation with a segmented playback clock and ground-down lifecycle hooks.
const Route=preload("res://scripts/body_hurtboxes.gd")
const SOURCE_HOLD=1.0/30.0
const STRIKE=.18
const WAVE_SECONDS=.30
const ACTIVE_END=STRIKE+WAVE_SECONDS
const FINISH=.54
const DURATION=.62
const DAMAGE=7.0
const PUSH=1.2
var actor
var view
var skeleton:Skeleton3D
var mesh:MeshInstance3D
var active=false
var elapsed=0.0
var direction=1.0
var targets=[]
var contacts=[]
var entry=[]
var entry_needed=false
var rings=[]
var sound:AudioStreamPlayer
var wave_origin=Vector3.ZERO
var emitted=false
var activations=0
var emission_source=-1.0
var emission_elapsed=-1.0
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual")
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 mesh=view.model.find_children("*","MeshInstance3D",true,false)[0]
 view.animation_player.add_animation_library("bark",load("res://assets/doge_man/bark/source_motion.res"))
 sound=AudioStreamPlayer.new();sound.stream=load("res://assets/doge_man/bark/Shadow_ONE_BARK.wav");add_child(sound)
 for i in 3:
  var ring=MeshInstance3D.new();ring.mesh=TorusMesh.new();ring.mesh.inner_radius=.93;ring.mesh.outer_radius=1.0
  var mat=StandardMaterial3D.new();mat.albedo_color=Color(.35,.85,1,.8);mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
  ring.material_override=mat;actor.add_child(ring);ring.visible=false;rings.append(ring)
func start():
 if active or not actor.is_grounded():return
 active=true;elapsed=0;direction=actor.facing;targets.clear();contacts.clear();entry.clear();emitted=false;activations+=1;emission_source=-1;emission_elapsed=-1
 entry_needed=actor.crouch_pose.amount<.999
 for b in skeleton.get_bone_count():entry.append(skeleton.get_bone_pose(b))
 actor.doge_tyson_followup=false;actor.doge_punch_buffered=false
 actor.attack_cooldown=DURATION;actor.last_move="BARK";actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.visible=false
 view.cancel_up_special();view.jump_elapsed=-1;view.air_uppercut=false
 present(0)
func reset_morphs(crouching:bool=false):
 if not is_instance_valid(mesh):return
 for i in mesh.mesh.get_blend_shape_count():
  var n=str(mesh.mesh.get_blend_shape_name(i))
  if "Fist_STUDY" in n:mesh.set_blend_shape_value(i,0.0 if crouching else 1.0)
  elif "LowerLipFlex" in n:mesh.set_blend_shape_value(i,0)
func cancel():
 if not active:return
 active=false;elapsed=0;targets.clear();entry.clear();emitted=false
 sound.stop();sound.stream_paused=false
 for r in rings:r.visible=false
 actor.attack_cooldown=0;view.current_clip="";view.animation_player.speed_scale=1;reset_morphs()
func before_tick():
 if not active:return
 if not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.sleep_remaining>0 or (actor.tumble and actor.tumble.active) or (actor.revival and actor.revival.phase!="idle"):
  cancel();return
 sound.stream_paused=actor.counter_hitstop>0
func before_move():
 if active:actor.facing=direction;actor.velocity.x=0
func source_time(t:float)->float:
 if t<=.13:return lerpf(1.0/30,27.0/30,clampf(t/.13,0,1))
 if t<=STRIKE:return lerpf(27.0/30,34.0/30,(t-.13)/.05)
 if t<=.36:return lerpf(34.0/30,51.0/30,(t-STRIKE)/.18)
 return lerpf(51.0/30,79.0/30,clampf((t-.36)/.18,0,1))
func pose_at(t:float):
 view.animation_player.play("bark/Bark",0);view.animation_player.seek(source_time(t),true);view.animation_player.pause()
 # No standing/re-squat when already held. A simultaneous chord bridges only
 # entry, preserving source ordering and arriving before the thrust.
 if entry_needed and t<.08 and entry.size()==skeleton.get_bone_count():
  for b in skeleton.get_bone_count():skeleton.set_bone_pose(b,entry[b].interpolate_with(skeleton.get_bone_pose(b),smoothstep(0,.08,t)))
 if t>FINISH:
  for b in skeleton.get_bone_count():skeleton.set_bone_pose(b,skeleton.get_bone_pose(b).interpolate_with(actor.crouch_pose.endpoint[b],smoothstep(FINISH,DURATION,t)))
 if t>=DURATION:reset_morphs(true)
 skeleton.force_update_all_bone_transforms()
func present(t:float):
 if not active:return
 actor._visual_root.scale=Vector3.ONE;view.model.rotation.y=direction*PI/2
 view.flight_root.rotation=Vector3.ZERO;view.current_clip="bark/Bark";pose_at(t)
 var age=t-STRIKE
 for i in 3:
  var a=age-i*.05;rings[i].visible=emitted and a>=0 and a<WAVE_SECONDS
  if rings[i].visible:
   var radius=lerpf(.12,.72,a/WAVE_SECONDS)
   rings[i].global_position=wave_origin+Vector3(direction*2.0*a/WAVE_SECONDS,0,0)
   rings[i].rotation=Vector3(0,.5,PI/2);rings[i].scale=Vector3.ONE*radius;rings[i].material_override.albedo_color.a=(1-a/WAVE_SECONDS)*.8
func emit_wave():
 pose_at(STRIKE)
 wave_origin=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("headfront")).origin+Vector3(direction*.08,0,0)
 emitted=true;emission_source=source_time(STRIKE);emission_elapsed=STRIKE;sound.play()
func query_contact(t:float):
 if not emitted or t<STRIKE or t>=ACTIVE_END:return
 var age=t-STRIKE;var radius=lerpf(.12,.72,age/WAVE_SECONDS);var center=wave_origin+Vector3(direction*2.0*age/WAVE_SECONDS,0,0)
 var q=PhysicsShapeQueryParameters3D.new();q.shape=SphereShape3D.new();q.shape.radius=radius;q.transform.origin=center;q.collision_mask=1 | 4;q.margin=0
 Route.prepare(actor,q)
 var space=actor.get_world_3d().direct_space_state;var hits=space.intersect_shape(q,64)
 for hit in hits:
  var target=Route.resolve(hit.collider)
  if not actor.can_hit(target) or target in targets:continue
  var contact=Route.shape_contact(space,q,hit,hits)
  if contact.is_empty():continue
  targets.append(target)
  var owner=hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(int(contact.shape)))
  contacts.append({"elapsed":t,"source_time":source_time(t),"center":center,"radius":radius,"point":contact.position,"region":str(owner.name),"facing":direction,"target":target.character_id,"target_position":target.global_position})
  Route.deliver(target,DAMAGE,Vector3(direction,.15,0),PUSH,contact,actor)
func after_tick(delta:float):
 if not active:return
 if not actor.is_grounded():cancel();return
 var end=minf(elapsed+delta,DURATION)
 var t=elapsed
 while t<end-.000001:
  t=minf(t+1.0/240,end)
  if not emitted and t>=STRIKE:emit_wave()
  query_contact(t)
 elapsed=end;present(elapsed);actor.attack_cooldown=maxf(.00001,DURATION-elapsed)
 if elapsed>=DURATION-.000001:
  cancel();actor.crouch_pose.amount=1;actor.crouch_pose.phase="hold"
  # Finish already has the actual hold. Native crouch presenter owns release.
  reset_morphs(true);actor.crouch_pose.sync_receivers()

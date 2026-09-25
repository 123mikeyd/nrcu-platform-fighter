extends Node
# Isolated GGB kit. Native mesh/material/wing source is unchanged.
const HURT=preload("res://scripts/body_hurtboxes.gd")
var actor
var view
var cues
var phase=""
var elapsed=0.0
var facing=1.0
var targets={}
var contacts=[]
var previous_center=Vector3.ZERO
var landing_origin=Vector3.ZERO
var ignored=[]
var landed=false
func committed():return phase in ["up","up_land","steel","steel_land"]
func reserve_air():return phase=="up"
func start_special(aim):
 if phase in ["steel","steel_land"]:
  if aim.y>.1:cancel();actor.last_move="NORMAL FORM"
  return
 if aim.y<-.1 and actor.recovery_spent:return
 cancel();facing=actor.facing;landed=false
 if aim.y>.1:
  phase="steel";actor.drop_committed=true;actor._ggb_impact_pending=false
  actor.velocity=Vector3(0,-24,0);actor.last_move="STEEL FORM"
  for other in actor.get_tree().get_nodes_in_group("fighters"):
   if other!=actor:actor.add_collision_exception_with(other);ignored.append(other)
 else:
  phase="up";actor.recovery_spent=true;actor.velocity=Vector3.ZERO
  actor.last_move="WING RISE / FLIP / DIVE"
  for other in actor.get_tree().get_nodes_in_group("fighters"):
   if other!=actor:actor.add_collision_exception_with(other);ignored.append(other)
 actor.attack_cooldown=.22;actor._update_move_visuals()
 previous_center=view.body_center_world()
func resistance():return .6 if phase in ["steel","steel_land"] and elapsed<3.0 else 1.0
func before_move(delta):
 if not committed():return
 previous_center=view.body_center_world()
 if phase=="steel":actor.velocity=Vector3(0,-24,0)
 elif phase in ["up_land","steel_land"]:actor.velocity=Vector3(0,-1,0)
 elif phase=="up":
  if elapsed<.22:actor.velocity=Vector3.ZERO
  elif elapsed<1.05:
   var u=clampf((elapsed-.22)/.83,0,1)
   actor.velocity=Vector3(facing*.45/.83,3.25*PI/(2*.83)*cos(u*PI/2),0)
  elif elapsed<1.63:actor.velocity=Vector3(facing*.65/.58,0,0)
  else:actor.velocity=Vector3(facing*.75/.41,-minf(24,5+24*(elapsed-1.63)),0)
 # Steel bypasses fighter movement pushing only; terrain stays authoritative.
 if phase=="steel":
  var sphere=SphereShape3D.new();sphere.radius=.39
  var q=PhysicsShapeQueryParameters3D.new();q.shape=sphere;q.transform=Transform3D(Basis.IDENTITY,previous_center);q.motion=actor.velocity*delta;q.collision_mask=2;q.margin=0;q.exclude=[actor.get_rid()]
  var fractions=actor.get_world_3d().direct_space_state.cast_motion(q)
  var safe=fractions[0] if not fractions.is_empty() else 1.0
  swept_body(previous_center,previous_center+q.motion*safe,12.0,"activation")
func swept_body(a,b,damage,strike):
 var shape=CapsuleShape3D.new();shape.radius=.39;shape.height=a.distance_to(b)+.78
 var basis=Basis.IDENTITY if a.distance_squared_to(b)<.000001 else Basis(Quaternion(Vector3.UP,(b-a).normalized()))
 query(shape,(a+b)*.5,damage,4.0,strike,basis)
func special_tick(delta):
 elapsed+=delta;cues.hide_all()
 if elapsed>=3.0 and phase in ["steel","steel_land"]:cancel();return
 if elapsed>=5.0 and phase=="up":cancel();return
 if phase=="up":
  var squash=1.0
  if elapsed<.22:squash=1-.18*sin(elapsed/.22*PI)
  elif elapsed<1.05:squash=1.06
  elif elapsed<1.63:
   var u=(elapsed-1.05)/.58
   view.rotation.z=-facing*TAU*smoothstep(0,1,u);squash=1-.20*sin(u*PI)
  else:
   view.rotation.z=0;squash=1.16
   swept_body(previous_center,view.body_center_world(),10.0,"activation")
  view.scale=Vector3(1/sqrt(squash),squash,1)*view.PRESENTATION_SCALE
  for i in view.wings.size():view.wings[i].rotation.z=(-1 if i==0 else 1)*(.38+.62*sin(elapsed*48))
  if elapsed>1.63 and actor.is_grounded():
   phase="up_land";elapsed=0;landing_origin=actor.global_position;actor.landing_lag=.38
 elif phase=="steel" and actor.is_grounded():
  phase="steel_land";landing_origin=actor.global_position;actor.landing_lag=.38
  var shape=BoxShape3D.new();shape.size=Vector3(2.2,.28,1.0)
  query(shape,landing_origin+Vector3(0,.14,0),12.0,4.0,"activation")
 if phase in ["up_land","steel_land"]:
  cues.ripple.visible=true
  var r=clampf(elapsed/.58,0,1) if phase=="up_land" else 1.0
  cues.ripple.global_position=landing_origin+Vector3(facing*.75*r if phase=="up_land" else 0,.03,0)
  cues.ripple.scale=Vector3(.55+1.20*r,1,.55+.35*r)
  if phase=="up_land":
   var squash=1-.32*sin(clampf(elapsed/.38,0,1)*PI)
   view.rotation.z=0;view.scale=Vector3(1/sqrt(squash),squash,1)*view.PRESENTATION_SCALE
   var shape=BoxShape3D.new();shape.size=Vector3(1.12*cues.ripple.scale.x,.18,1.12*cues.ripple.scale.z)
   query(shape,cues.ripple.global_position+Vector3(0,.09,0),6.0,2.4,"activation")
   if elapsed>=.58:cancel()
  else:cues.ripple.visible=actor.landing_lag>0
func _ready():
 actor=get_parent();view=actor.get_node("VisualRoot/GGBVisual")
 cues=preload("res://scripts/ggb_review_cues.gd").new();actor.add_child(cues)
func start_basic(aim):
 cancel();phase="chomp" if absf(aim.x)<=.1 else "sting"
 if absf(aim.x)>.1:actor.facing=signf(aim.x)
 facing=actor.facing;actor.attack_cooldown=1.24 if phase=="chomp" else .72
 actor.last_move="DOUBLE CHOMP" if phase=="chomp" else "SHORT STING"
 actor.attack_flash_time=0
func cancel():
 for other in ignored:
  if is_instance_valid(other):actor.remove_collision_exception_with(other)
 ignored.clear()
 if is_instance_valid(actor) and phase in ["steel","steel_land"]:
  actor.drop_committed=false;actor._ggb_impact_pending=false
  view.set_lead(false)
 phase="";elapsed=0;targets.clear()
 if is_instance_valid(cues):cues.hide_all()
 if is_instance_valid(view):
  view.scale=Vector3.ONE*view.PRESENTATION_SCALE;view.rotation.z=0;view.position=Vector3(0,view.NORMAL_HOVER,0)
func before_tick():
 if not phase.is_empty() and (not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or (actor.tumble and actor.tumble.active) or (actor.revival and actor.revival.phase!="idle")):cancel()
func tick(delta):
 if phase.is_empty():return
 if committed():special_tick(delta);return
 elapsed+=delta
 if elapsed>=(1.24 if phase=="chomp" else .72):cancel();return
 cues.hide_all()
 # Exact audition HOME-relative floor anchor; jaws do not follow the body bump.
 var center=actor.global_position+Vector3(0,.77,.30)
 if phase=="chomp":
  if elapsed>=.12 and elapsed<.92:
   var local=fmod(elapsed-.12,.40)
   var gap=.50-.31*clampf(local/.13,0,1) if local<.18 else .19+.31*clampf((local-.18)/.18,0,1)
   var pulse=sin(clampf(local/.24,0,1)*PI)
   view.scale=Vector3(1+.10*pulse,1-.12*pulse,1)*view.PRESENTATION_SCALE
   view.position=Vector3(facing*.10*pulse,view.NORMAL_HOVER-.055*pulse,0)
   for j in 2:
    cues.jaws[j].visible=true;cues.jaws[j].global_position=center+Vector3(facing*.90,(1 if j==0 else -1)*gap,0)
   if local>=.12 and local<=.19:
    cues.spark.visible=true;cues.spark.global_position=center+Vector3(facing*.90,0,.15);cues.spark.scale=Vector3.ONE*.32
    var shape=BoxShape3D.new();shape.size=Vector3(.96,.14,.20)
    query(shape,center+Vector3(facing*.90,0,0),4.0,1.4,str(int((elapsed-.12)/.40)))
 elif phase=="sting":
  if elapsed>=.14 and elapsed<.44:
   var extension=smoothstep(.14,.27,elapsed) if elapsed<.27 else 1-smoothstep(.31,.44,elapsed)
   var point=center+Vector3(facing*lerpf(.64,1.12,extension),.06,0)
   cues.needle.visible=true;cues.needle.global_position=point;cues.needle.rotation.z=0 if facing>0 else PI
   var shape=BoxShape3D.new();shape.size=Vector3(.48,.09,.06)
   query(shape,point,7.0,3.2,"sting")
  if elapsed>=.27 and elapsed<.34:
   cues.spark.visible=true;cues.spark.global_position=center+Vector3(facing*1.36,.06,0);cues.spark.scale=Vector3.ONE*.28
func query(shape,point,damage,push,strike,basis=Basis.IDENTITY):
 var ray=PhysicsRayQueryParameters3D.create(view.body_center_world(),point,2);ray.exclude=[actor.get_rid()]
 var space=actor.get_world_3d().direct_space_state
 if not space.intersect_ray(ray).is_empty():return
 var q=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.transform=Transform3D(basis,point);q.collision_mask=7;q.margin=0
 HURT.prepare(actor,q)
 var hits=space.intersect_shape(q,64)
 for hit in hits:
  var target=HURT.resolve(hit.collider)
  if not actor.can_hit(target):continue
  var key=strike+":"+str(target.get_instance_id())
  if targets.has(key):continue
  targets[key]=true
  var witness=HURT.shape_contact(space,q,hit,hits)
  contacts.append({"phase":phase,"strike":strike,"target":target.character_id,"point":str(point),"time":elapsed,"damage":damage})
  HURT.deliver(target,damage,Vector3(facing,.3,0),push,witness,actor)

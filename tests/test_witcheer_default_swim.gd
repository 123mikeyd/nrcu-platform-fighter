extends SceneTree
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1;print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func run():
 root.unfocusable=true
 var fighter=load("res://scripts/fighter.gd").new();fighter.character_id="witcheer";root.add_child(fighter);fighter.set_physics_process(false)
 var v=fighter.get_node("VisualRoot/WitcheerVisual")
 await process_frame;await process_frame
 var p:AnimationPlayer=v.animation_player
 p.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var special:Animation=p.get_animation("AirSwim")
 for face in [-1.,1.]:
  for state in [[true,Vector3.ZERO,false],[true,Vector3.RIGHT*6,false],[false,Vector3.UP*6,false],[false,Vector3.DOWN*6,false],[true,Vector3.ZERO,true],[false,Vector3.DOWN,true]]:
   v.sync_pose(state[0],state[1],false,state[2],face)
   check(v.current_clip=="DefaultSwim" and p.is_playing(),"native swimming all passive states facing="+str(face)+" state="+str(state))
 check(p.has_animation("DefaultSwim"),"independent native full SwimIdle loop exists")
 if p.has_animation("DefaultSwim"):
  var a=p.get_animation("DefaultSwim");var native=load("res://assets/witcheer/native_library.tres").get_animation("SwimIdle_DEFERRED")
  check(a!=native and a!=special and a.loop_mode==Animation.LOOP_LINEAR and is_equal_approx(a.length,3),"three-second full native cycle per-instance")
  check(a.get_track_count()==native.get_track_count(),"all native tracks retained")
  var same=true
  for t in a.get_track_count():
   same=same and a.track_get_key_count(t)==native.track_get_key_count(t)
   for k in a.track_get_key_count(t):same=same and a.track_get_key_time(t,k)==native.track_get_key_time(t,k) and a.track_get_key_value(t,k)==native.track_get_key_value(t,k)
  check(same,"native full forward keys unchanged; no pingpong")
  check(special.loop_mode==Animation.LOOP_NONE and is_equal_approx(special.length,2),"finite AirSwim unchanged")
 check(v.has_method("_process"),"passive pace smoothly follows movement")
 if v.has_method("_process"):
  v.set_process(false)
  var sk:Skeleton3D=v.model.find_children("*","Skeleton3D",true,false)[0]
  for face in [-1.,1.]:
   v.sync_pose(true,Vector3.ZERO,false,false,face)
   for i in 60:v._process(1./60);p.advance(1./60)
   check(is_equal_approx(p.get_playing_speed(),.65),"gentle native pace")
   p.seek(.7,true)
   var arm=sk.find_bone("LeftArm");var initial=sk.get_bone_pose_rotation(arm)
   for state in [[true,Vector3.RIGHT*6,false],[false,Vector3.UP*6,false],[false,Vector3.DOWN*6,false],[false,Vector3.DOWN,true],[true,Vector3.ZERO,true],[true,Vector3.ZERO,false]]:
    var time=p.current_animation_position;var pose=sk.get_bone_pose_rotation(arm)
    v.sync_pose(state[0],state[1],false,state[2],face)
    check(is_equal_approx(p.current_animation_position,time) and pose.angle_to(sk.get_bone_pose_rotation(arm))<.002,"state transition preserves exact phase and pose")
    p.advance(.05)
   check(initial.angle_to(sk.get_bone_pose_rotation(arm))>.01,"native arm really moves")
   v.sync_pose(true,Vector3.RIGHT*6,false,false,face)
   var old=p.get_playing_speed();v._process(1./60)
   check(p.get_playing_speed()>old and p.get_playing_speed()<1.25,"pace change smooth not abrupt")
   for i in 90:
    var time=p.current_animation_position
    v.sync_pose(true,Vector3.RIGHT*6,false,false,face);v._process(1./60);p.advance(1./60)
    check(absf(fposmod(p.current_animation_position-time,3)-p.get_playing_speed()/60)<.002,"no phase restart during speed easing")
   check(is_equal_approx(p.get_playing_speed(),1.25) and p.speed_scale==1,"strong paddling with no global speed_scale leak")
   v.sync_pose(true,Vector3.ZERO,false,true,face)
   for i in 60:v._process(1./60);p.advance(1./60)
   check(is_equal_approx(p.get_playing_speed(),.65),"shield returns gentle pace")
   v.show_move("NeutralHook",.3,face)
   check(p.speed_scale==1 and not p.is_playing() and is_equal_approx(p.current_animation_position,.3),"attack exact clock and priority")
   v.sync_pose(false,Vector3.DOWN,false,false,face)
   check(v.current_clip=="DefaultSwim" and p.is_playing(),"attack recovers swimming")
   v.sync_pose(true,Vector3.ZERO,true,false,face)
   v._process(.2)
   check(not p.is_playing() and v.current_clip!="DefaultSwim","interruption cannot resume passive")
 # Let SceneTree own shutdown; dummy renderer can log null material on early free.
 print("DEFAULT SWIM checks=",checks," failures=",failures);quit(1 if failures else 0)

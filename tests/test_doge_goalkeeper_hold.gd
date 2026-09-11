extends SceneTree
const F=preload('res://scripts/fighter.gd')
var failures:=0
func _initialize():call_deferred('run')
func check(ok,msg):
 if not ok:failures+=1;printerr('FAIL: '+msg)
func run():
 var dog=F.new();dog.character_id='doge_man';root.add_child(dog);dog.set_physics_process(false);await process_frame
 var v=dog._visual_root.get_node('DogeVisual')
 for direction in [1.0,-1.0]:
  dog.facing=direction;dog.charging=true
  var previous=-1.0
  var monotonic=true
  for i in 73:
   dog.doge_goalkeeper_hold=i/60.0;dog._update_move_visuals()
   var source=dog.doge_goalkeeper_source
   if source<previous-0.000001:monotonic=false
   previous=source
   check(absf(v.animation_player.current_animation_position-source)<0.00001,'actual skeleton source clock')
  check(monotonic,'draw back only once, never reverse full anticipation')
  check(absf(previous-.6)<.00001,'holds actual rear-most right-foot source frame58')
  dog.doge_goalkeeper_hold=.3;dog._update_move_visuals();check(dog.doge_goalkeeper_source<.15,'slow draw rather than immediate rear pose')
  var lo=1.0;var hi=0.0
  for i in range(72,1201):
   dog.doge_goalkeeper_hold=i/60.0;dog._update_move_visuals()
   lo=minf(lo,dog.doge_goalkeeper_source);hi=maxf(hi,dog.doge_goalkeeper_source)
  check(lo>=.597-0.00001 and hi<=.60001,'20-second hold bounded at pulled-back pose; no replay')
  check(hi-lo<=.00301,'optional idle movement tiny source bound')
 dog.charging=false;dog.queue_free();await process_frame
 if failures==0:print('PASS slow once-only draw, source frame58 hold, tiny bound over20s, both facings and actual skeleton seek')
 quit(1 if failures else 0)

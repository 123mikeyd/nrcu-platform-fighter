extends SceneTree
var failures=0
var rows=[]
func _initialize():root.unfocusable=true;call_deferred('run')
func frames(n):
 for i in n:await physics_frame;await process_frame
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func check(ok,msg):
 print(('PASS: ' if ok else 'FAIL: ')+msg)
 if not ok:failures+=1
func run():
 var unlocks=load('res://scripts/unlocks.gd');unlocks.path_override=OS.get_environment('WITCHEER_UNLOCK_JSON')
 var a=load('res://scenes/main.tscn').instantiate();root.add_child(a);await process_frame
 for i in 2:
  var options=a.setup.rows[i].character
  for j in options.item_count:
   if options.get_item_metadata(j)==('witcheer' if i==0 else 'doge_man'):options.select(j)
  a.setup.rows[i].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();a.setup.choose_stage(0);a.setup.launch_match();await frames(130)
 var f=a.fighters[0];var p=a.fighters[1];var v=f._visual_root.get_node('WitcheerVisual')
 for face in [-1,1]:
  for move in ['neutral','up','poke','poke_held','side']:
   f.reset_fighter(Vector3(0,0,0),true);p.reset_fighter(Vector3(7,0,0),true);f.facing=face;await frames(20)
   var code=KEY_W if move=='up' else (KEY_S if move.begins_with('poke') else ((KEY_D if face==1 else KEY_A) if move=='side' else 0))
   var clip='CaneUpV002' if move=='up' else ('CaneDownPokeV002' if move.begins_with('poke') else ('HighKick' if move=='side' else 'CaneNeutralV003'))
   if code:key(code,true)
   key(KEY_F,true);await frames(1);key(KEY_F,false)
   if code and move!='poke_held':key(code,false)
   check(f.witcheer_clip==clip,'route '+move+' '+str(face))
   var trace=[]
   for tick in 220:
    var allowed=[clip,'DapperCaneIdleV004','CrouchBreathingV001']
    check(v.current_clip in allowed,'boundary '+move+' '+str(face)+' '+str(tick)+' '+v.current_clip)
    if move!='side':check(v.cane.visible,'cane remains visible '+move+' '+str(tick))
    trace.append({'tick':tick,'clip':f.witcheer_clip,'cooldown':f.attack_cooldown,'elapsed':f.witcheer_elapsed,'visual':v.current_clip,'cane':v.cane.visible,'crouch':f.crouch_pose.phase})
    await frames(1)
   check(f.attack_cooldown==0 and f.witcheer_clip.is_empty(),'finite '+move)
   check(v.current_clip==('CrouchBreathingV001' if move=='poke_held' else 'DapperCaneIdleV004'),'destination '+move)
   if code:key(code,false)
   rows.append({'move':move,'face':face,'trace':trace})
 # An unrelated cooldown must NOT acquire the natural-finish presentation.
 f.reset_fighter(Vector3(0,0,0),true);await frames(20);f.attack_cooldown=.5;f._update_move_visuals()
 check(v.current_clip=='Run' and not v.cane.visible,'unowned cooldown is not idle')
 var out=FileAccess.open(OS.get_environment('WITCHEER_CAPTURE_JSON'),FileAccess.WRITE);out.store_string(JSON.stringify({'rows':rows,'failures':failures},'  '));out.close()
 a.queue_free();await frames(3);print('WITCHEER_RETURNS_COMPLETE failures=',failures);quit(1 if failures else 0)

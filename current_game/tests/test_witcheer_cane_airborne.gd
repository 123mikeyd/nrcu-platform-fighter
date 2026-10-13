extends SceneTree
var failures=0
var rows=[]
func _initialize():call_deferred('run')
func frames(n):
 for i in n:await physics_frame;await process_frame
func key(code,down):
 var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e);Input.flush_buffered_events()
func check(ok,msg):
 print(('PASS: ' if ok else 'FAIL: ')+msg)
 if not ok:failures+=1
func run():
 var a=load('res://scenes/main.tscn').instantiate();root.add_child(a);await process_frame
 var ids=load('res://scripts/match_config.gd').CHARACTERS
 for i in 2:a.setup.rows[i].character.select(ids.find('witcheer' if i==0 else 'doge_man'));a.setup.rows[i].kind.select(0)
 a.setup.rows[2].kind.select(2);a.setup.rows[3].kind.select(2);a.setup._refresh();a.setup._start();a.setup.choose_stage(0);a.setup.launch_match();await frames(100)
 var f=a.fighters[0];var p=a.fighters[1];var v=f._visual_root.get_node('WitcheerVisual')
 for face in [-1,1]:
  # Recreate the match before exchanging sides: reset_fighter calls move_and_slide
  # immediately and can push through the other fighter's old position otherwise.
  a.show_setup();await frames(2);a.setup._start();a.setup.choose_stage(0);a.setup.launch_match();await frames(100)
  f=a.fighters[0];p=a.fighters[1];v=f._visual_root.get_node('WitcheerVisual')
  for clip in ['CaneUpV002']:
   for gap in [1.25,2.2]:
    f.reset_fighter(Vector3(-face*gap/2,0,0),true);p.reset_fighter(Vector3(face*gap/2,0,0),true);f.facing=face;p.facing=-face;await frames(20)
    if clip=='CaneUpV002':key(KEY_W,true)
    key(KEY_F,true);await frames(2);key(KEY_F,false);key(KEY_W,false)
    check(f.witcheer_clip==clip,'route '+clip)
    var first=-1.0;var peak=0.0;var cane_seen=false;var jumped=false;var hit_air=false;var first_height=0.0
    for tick in 100:
     if not jumped and f.witcheer_elapsed>=.1:
      key(KEY_ENTER,true);jumped=true
     elif jumped:key(KEY_ENTER,false)
     if jumped and gap==1.25:
      key(KEY_LEFT if face==1 else KEY_RIGHT,f.witcheer_elapsed>=.4 and f.witcheer_elapsed<.65)
     await frames(1)
     check(v.current_clip in [clip,'DapperCaneIdleV004'] and v.cane.visible,'continuous contact/return '+clip+' cooldown='+str(f.attack_cooldown)+' visual='+v.current_clip)
     if p.damage_percent>0 and first<0:
      first=f.witcheer_elapsed;hit_air=not p.is_grounded();first_height=p.position.y
     peak=maxf(peak,p.damage_percent);cane_seen=cane_seen or v.cane.visible
    key(KEY_LEFT,false);key(KEY_RIGHT,false)
    rows.append({'clip':clip,'face':face,'gap':gap,'damage':peak,'first_time':first,'hit_air':hit_air,'first_height':first_height,'actual_offset':str(p.position-f.position)})
    if gap==1.25:check(peak==8 and hit_air,'airborne staff contact once '+str(rows[-1]))
    if gap==2.2:check(peak==0,'outside reach '+str(rows[-1]))
    check(peak<=8,'once-per-opponent '+str(rows[-1]))
    # Contact sampling above stays unchanged. The authored up-cane clip lasts
    # longer than that 100-tick contact window; observe its finite completion.
    for recovery_tick in 240:
     if f.witcheer_clip.is_empty():break
     await frames(1)
     check(v.current_clip in [clip,'DapperCaneIdleV004'] and v.cane.visible,'continuous attack-to-idle boundary '+clip+' cooldown='+str(f.attack_cooldown)+' visual='+v.current_clip)
    check(f.witcheer_clip.is_empty(),'bounded completion '+clip)
    # The move clock starts later in the input tick than cooldown decrement.
    # Completion can therefore precede cooldown expiry by one physics tick;
    # Presentation is asserted above THROUGH the residual tick, not after it.
    check(f.attack_cooldown <= 1.0 / Engine.physics_ticks_per_second,'return cooldown bounded to one tick '+clip)
    if f.attack_cooldown > 0.0:await frames(1)
    check(f.attack_cooldown == 0.0,'return cooldown expired '+clip)
    check(cane_seen and v.current_clip=='DapperCaneIdleV004' and v.animation_player.assigned_animation=='DapperCaneIdleV004' and v.animation_player.is_playing() and v.cane.visible and v.cane.transform.is_equal_approx(v.cane_idle_transform),'cane finite return '+clip)
    var idle_time: float = v.animation_player.current_animation_position
    await frames(12)
    check(f.witcheer_clip.is_empty() and v.current_clip=='DapperCaneIdleV004' and v.animation_player.current_animation_position > idle_time and v.cane.visible and v.cane.transform.is_equal_approx(v.cane_idle_transform),'sustained animated cane idle '+clip)
 print('CONTACT failures=',failures);a.queue_free();await frames(2);print("WITCHEER_CANE_AIRBORNE_COMPLETE");quit(1 if failures else 0)

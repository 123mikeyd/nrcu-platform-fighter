extends SceneTree
var failures=0
var checks=0
var arena
var f
var target
func check(ok,text):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",text)
func _initialize():call_deferred("run")
func run():
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 load("res://tools/play_mephisto.gd").configure(arena);arena.setup.rows[1].kind.select(0);arena.setup._start()
 for i in 210:await physics_frame
 f=arena.fighters[0];target=arena.fighters[1]
 for a in [f,target]:a.set_physics_process(false);a.controls_enabled=true
 f.mephisto_moves.demon_form=true;f.damage_percent=0;f.attack_cooldown=0
 f.start_special(Vector2.RIGHT)
 check(f.charging and f.mephisto_moves.move=="SmokeCharge","side special is interactive hold-to-charge")
 if failures:print("PAIRED_COMBAT_COMPLETE checks=",checks," failures=",failures);quit(1);return
 for i in 180:f.advance_charge(1.0/60);f.mephisto_moves.tick(1.0/60)
 check(f.charge_time<=1.5 and f.charging,"charge capped; hold never automatically fires")
 f._update_move_visuals()
 check(not f._attack_flash.visible,"smoke charge never uses generic glowing attack sphere")
 f.release_special()
 check(not f.charging and f.mephisto_moves.move=="SmokeRelease","real release enters smoke")
 check(target.damage_percent==0,"release startup harmless")
 for i in 150:f.mephisto_moves.tick(1.0/60)
 check(f.mephisto_moves.move.is_empty(),"release completes without stuck state")
 for move in f.mephisto_moves.BASIC:
  f.attack_cooldown=0;target.damage_percent=0;target.hitstun=0
  f.mephisto_moves.start_kit(move,1)
  check(target.damage_percent==0,"basic startup harmless "+move)
  var d=f.mephisto_moves.BASIC[move]
  f.mephisto_moves.elapsed=(d.hit-d.start)/(d.end-d.start)*d.duration
  f.mephisto_moves.present()
  var point=f.mephisto_moves.view().demon_point(d.bone)
  target.global_position=point-Vector3(0,1,0)
  f.mephisto_moves.tick(.001)
  check(target.damage_percent>0,"actual native limb witness "+move)
  var damage=target.damage_percent
  for i in 150:f.mephisto_moves.tick(1.0/60)
  check(target.damage_percent==damage,"one contact ledger "+move)
 print("PAIRED_COMBAT_COMPLETE checks=",checks," failures=",failures)
 quit(1 if failures else 0)

extends SceneTree
var failures=0
func check(ok,text):
 if not ok:failures+=1;printerr("FAIL: ",text)
func _initialize():call_deferred("run")
func run():
 var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
 load("res://tools/play_mephisto.gd").configure(arena);arena.setup.rows[1].kind.select(0);arena.setup._start();await process_frame
 for i in 210:await physics_frame
 var f=arena.fighters[0];f.set_physics_process(false);f.controls_enabled=true
 f.hitstun=0;f.freeze_remaining=0
 check(f.mephisto_moves.get("demon_form")!=null,"persistent playable paired form state")
 if failures:quit(1);return
 f.damage_percent=37;f.stocks=2;f.attack_cooldown=0
 f.start_special(Vector2.DOWN)
 check(f.mephisto_moves.move=="SwitchToDemon","down special selects authored lift")
 for i in 180:f.mephisto_moves.tick(1.0/60)
 check(f.mephisto_moves.demon_form,"lift commits demon form")
 check(f.damage_percent==37 and f.stocks==2,"form switch preserves owner damage/stocks")
 check(f.mephisto_moves.route(Vector2.ZERO,false,false)=="RightSwipe","demon neutral routes new swipe")
 check(f.mephisto_moves.route(Vector2.RIGHT,false,false)=="FrontKick","demon side routes new kick")
 check(f.mephisto_moves.route(Vector2.UP,false,false)=="RisingForearm","demon up routes new forearm")
 check(f.mephisto_moves.route(Vector2.DOWN,false,false)=="Stomp","demon down routes new stomp")
 print("PAIRED_FORM_COMPLETE failures=",failures)
 quit(1 if failures else 0)

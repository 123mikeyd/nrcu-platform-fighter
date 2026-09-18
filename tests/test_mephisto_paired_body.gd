extends SceneTree
var failures=0
func check(ok,text):
 if not ok:failures+=1;printerr("FAIL: ",text)
func _initialize():call_deferred("run")
func run():
 var f=load("res://scripts/fighter.gd").new();f.character_id="mephisto";root.add_child(f);f.set_physics_process(false);f.controls_enabled=true
 var m=f.mephisto_moves
 m.demon_form=false;var speed=f.ground_speed_multiplier();f.receive_hit(10,Vector3.RIGHT,4);var light=f.velocity.length()
 f.damage_percent=0;f.hitstun=0;m.demon_form=true;f.receive_hit(10,Vector3.RIGHT,4)
 check(f.ground_speed_multiplier()<speed,"demon slower than girl")
 check(f.velocity.length()<light and f.damage_percent==10,"resistance without armor or damage immunity")
 check(f.get_node_or_null("BodyHurtboxes")!=null and f.get_hurtbox_shapes().size()==14,"native fitted paired hurt regions share one owner")
 print("PAIRED_BODY_COMPLETE failures=",failures)
 quit(1 if failures else 0)

extends SceneTree
var failures := 0
func _initialize():call_deferred("run")
func check(ok, label):
 if not ok:failures+=1;printerr("FAIL: "+label)
func run():
 var catalog=load("res://scripts/catalogs/story_encounter_catalog.gd")
 var briefing=load("res://scenes/story_briefing.tscn").instantiate()
 root.add_child(briefing)
 await process_frame
 check("does not attack" not in briefing._rule_behavior.text,"briefing must not claim attacking Bobo is passive")
 check("claw" in briefing._rule_behavior.text.to_lower(),"briefing describes current claw attacks")
 var text=FileAccess.get_file_as_string("res://scripts/catalogs/story_encounter_catalog.gd")
 check("Bobo does not attack." not in text,"catalog rules must not promise passive Bobo")
 briefing.queue_free();await process_frame
 if failures==0:print("PASS: current Bobo briefing truth")
 quit(1 if failures else 0)

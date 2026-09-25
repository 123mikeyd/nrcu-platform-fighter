extends SceneTree
var arena
var failures:Array=[]
var checks=0
func _initialize():call_deferred("run_test")
func check(ok:bool,description:String):
 checks+=1
 if not ok:failures.append(description);print("FAIL ",description)
func run_test():
 arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);current_scene=arena
 await physics_frame
 arena.clearance.save_path="user://story_contact_fixture.cfg"
 DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.clearance.save_path))
 await preload("res://tests/story_contact_cases.gd").new().run_cases(self,arena,check)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.clearance.save_path))
 root.remove_child(arena);arena.queue_free()
 for i in 3:await physics_frame
 print("STORY_CONTACT checks=",checks," failures=",failures.size())
 if failures.is_empty():print("STORY_CONTACT_COMPLETE")
 quit(0 if failures.is_empty() else 1)

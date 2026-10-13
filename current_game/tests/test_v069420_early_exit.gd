extends SceneTree
# Quit while startup owns threaded work; the runner rejects shutdown leaks.
func _initialize():
 root.unfocusable = true
 call_deferred("run")
func run():
 change_scene_to_file("res://scenes/startup.tscn")
 for i in 3: await process_frame
 if not is_instance_valid(current_scene) or not current_scene.has_method("request_skip") or not current_scene.requested:
  print("FAIL early-exit fixture must reach startup's request")
  quit(1)
  return
 print("EARLY_EXIT pending cache requests=", root.get_node("FrontendCache").pending.size())
 print("V069420_EARLY_EXIT_COMPLETE")
 quit(0)

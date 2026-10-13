extends Node
# Warm only data resources in workers. No fighter instances or game simulation.
const Resources = preload("res://scripts/frontend_resources.gd")
var started := false
var is_ready := false
var failed := false
var pending: Array = []
var held: Array = []
var start_ms := 0
var ready_ms := 0
var prepared_scene: PackedScene
func _exit_tree() -> void:
 # Finish owned requests before engine teardown, including early window close.
 # load_threaded_get may block here; ordinary frame polling stays asynchronous.
 for path in pending:
  if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
   ResourceLoader.load_threaded_get(path)
 pending.clear()
 held.clear()
 prepared_scene = null
func prime_scene() -> PackedScene:
 if prepared_scene == null:
  prepared_scene=load("res://scenes/main.tscn") as PackedScene
 return prepared_scene
func start() -> bool:
 if started:return not failed
 started=true;start_ms=Time.get_ticks_msec()
 for path in Resources.PATHS:
  if ResourceLoader.load_threaded_request(path)==OK:pending.append(path)
  else:failed=true
 return not failed
func _process(_delta):
 if not started or is_ready or failed:return
 for i in range(pending.size()-1,-1,-1):
  var path: String=pending[i]
  var state=ResourceLoader.load_threaded_get_status(path)
  if state==ResourceLoader.THREAD_LOAD_FAILED:failed=true;return
  if state==ResourceLoader.THREAD_LOAD_LOADED:
   held.append(ResourceLoader.load_threaded_get(path));pending.remove_at(i)
 if pending.is_empty():is_ready=true;ready_ms=Time.get_ticks_msec()

extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	check(lab.working != null, "standalone auto opens a discovered real profile")
	lab.open_profile("res://data/collision/generated/teknium.tres")
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await process_frame; await process_frame
		var save: Button = lab.find_child("SaveOverride",true,false)
		check(save.get_global_rect().end.y < resolution.y - 50, "save and reset reachable without scrolling at " + str(resolution))
		check(lab.panel.size.x <= 385,"compact panel without horizontal clipping")
	lab.free()
	print("PASS collision authoring layout" if not failures else "FAILED collision authoring layout")
	quit(1 if failures else 0)

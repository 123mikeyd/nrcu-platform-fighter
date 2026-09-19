extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func run() -> void:
	var v = load("res://scripts/core/presentation/ggb_presenter.gd").new()
	root.add_child(v)
	var host = load("res://scripts/core/kits/ggb_host.gd").new()
	host.start_special("old-drop",Vector2.DOWN,-1,true)
	var value: Dictionary = host.snapshot()
	value.facing = 1
	value.hit = true
	value.hit_id = "hit"
	v.present(value,0)
	check(is_equal_approx(v.rotation.y,.48),"winning hit uses committed actor facing, never stale lower-priority drop facing")
	check(not v.is_lead and v.output.identity == "hit:hit","hit suppresses lead material and ability identity")
	value.erase("hit")
	value.electrocution = {"activation_id":"caught","elapsed":.1}
	v.present(value,0)
	check(is_equal_approx(v.rotation.y,.48),"winning reaction uses actor facing")
	host.cancel(true)
	v.present(host.snapshot(),0)
	check(v.output.identity == "idle" and not v.is_lead,"same-tick actual host cancellation clears reaction")
	var fresh = load("res://scripts/core/presentation/ggb_presenter.gd").new()
	root.add_child(fresh)
	fresh.present(host.snapshot(),0)
	for i in v.meshes.size(): check(v.meshes[i].transform.is_equal_approx(fresh.meshes[i].transform),"cancel restores fresh source node transforms")
	v.reset()
	v.present(host.snapshot(),0)
	check(v.model.transform.is_equal_approx(fresh.model.transform),"reset restores fresh placement")
	v.free()
	fresh.free()
	await process_frame
	if failures == 0: print("PASS: GGB priority-facing ownership and same-tick lifecycle replacement")
	quit(1 if failures else 0)

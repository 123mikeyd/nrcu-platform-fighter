extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func pose(v: Node3D) -> Array:
	var result := [v.transform,v.model.transform]
	for node in v.model.find_children("*","Node3D",true,false): result.append(node.transform)
	return result
func run() -> void:
	var v = load("res://scripts/core/presentation/ggb_presenter.gd").new()
	root.add_child(v)
	v.present({"grounded":false},0)
	v.present({"grounded":false},1)
	var before := pose(v)
	v.present({"grounded":false,"hitstop":true},30)
	check(pose(v) == before,"hitstop freezes whole procedural pose, not just source elapsed")
	if not v.has_method("reset"):
		check(false,"missing lifecycle reset")
		v.free()
		quit(1)
		return
	var source = load("res://scripts/ggb_visual.gd").new()
	root.add_child(source)
	var samples_before := FileAccess.get_file_as_bytes("res://assets/ggb/electrocution_samples.json")
	for facing in [-1.0,1.0]:
		v.reset()
		source.clear_electrocution()
		source.phase = 0
		for seconds in [0.0,1.0/192,.137,2.375,8.0]:
			var value := {"facing":facing,"hit":true,"electrocution":{"activation_id":"grab","elapsed":seconds}}
			v.present(value,0)
			source.sync_pose(true,Vector3.ZERO,false,facing,0,true)
			source.present_electrocution(seconds)
			check(v.output.state == "electrocution","reaction relation beats generic hit")
			var actual := pose(v)
			var expected := pose(source)
			for i in actual.size(): check(actual[i].is_equal_approx(expected[i]),"sampled rigid source transform including exact endpoint, both facings")
		before = pose(v)
		v.present({"frozen":true,"hit":true,"electrocution":{"activation_id":"grab","elapsed":1}},0)
		check(v.output.state == "frozen" and pose(v) == before,"freeze has priority and preserves sampled reaction")
		v.present({"hit":true,"hit_id":"new"},0)
		check(v.output.identity == "hit:new" and not pose(v)[2].is_equal_approx(before[2]),"same-tick thaw/cancel retires reaction pose")
		before = pose(v)
		v.present({"hit":true,"hit_id":"new","locomotion":"rising","grounded":false,"jumps_used":3},0)
		check(pose(v) == before and v.output.identity == "hit:new","lower priority air transition cannot replace stopped hit")
		v.present({"hit":true,"hit_id":"next","hitstop":true},0)
		check(v.output.identity == "hit:next","synchronous new hit identity reconciles while stopped")
		v.present({"enabled":false,"electrocution":{"activation_id":"stale","elapsed":1}},0)
		check(v.output.state == "inactive","disable retires reaction despite stale snapshot")
	v.reset()
	v.present({"grounded":false,"paused":true},0)
	before = pose(v)
	for i in 5: v.present({"grounded":false,"paused":true},0)
	check(pose(v) == before,"unchanged committed tick is whole pose pause")
	v.present({"grounded":false,"paused":true},1)
	check(not pose(v)[1].is_equal_approx(before[1]),"committed step updates pose even if host UI remains paused")
	v.present({"grounded":false},0)
	check(is_zero_approx(v.phase),"rewind resets procedural clock")
	v.reset()
	check(v.output.is_empty() and not v.is_lead,"explicit reset clears identities and materials")
	check(FileAccess.get_file_as_bytes("res://assets/ggb/electrocution_samples.json") == samples_before,"immutable sampled reaction data")
	v.free()
	source.free()
	await process_frame
	if failures == 0: print("PASS: GGB committed clocks, source samples, priority, freeze thaw cancel rewind")
	quit(1 if failures else 0)

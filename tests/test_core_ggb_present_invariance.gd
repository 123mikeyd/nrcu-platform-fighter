extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func trace(mode: int) -> Array:
	var host = load("res://scripts/core/kits/ggb_host.gd").new()
	var v = load("res://scripts/core/presentation/ggb_presenter.gd").new()
	root.add_child(v)
	v.visible = mode == 0
	var result := []
	for tick in 220:
		if tick == 0: host.start_special("charge",Vector2.ZERO,1,true)
		if tick == 105:
			host.cancel(true)
			host.start_special("drop",Vector2.DOWN,-1,true)
		if tick == 125: host.landed(true)
		if tick == 160: host.cancel_for_status("frozen")
		if tick == 170: host.cancel(true)
		if tick == 180: host.start_basic("basic",Vector2.UP,true,1)
		if mode == 2 and tick == 10: v.free()
		host.prepare(tick < 70)
		var value: Dictionary = host.snapshot()
		var before := var_to_bytes(value)
		if is_instance_valid(v):
			v.present(value,tick)
			for render in 3: v.present(value,tick)
		check(before == var_to_bytes(value),"consumer never writes snapshot")
		result.append([host.snapshot(),host.collect(1,Vector3.ZERO,[{"id":2,"position":Vector3(1,0,0)}]),host.pre_move_requests(1)])
	if is_instance_valid(v): v.free()
	return result
func run() -> void:
	var visible_trace := trace(0)
	check(visible_trace == trace(1) and visible_trace == trace(2),"real host gameplay invariant visible hidden deleted presenter")
	for iteration in 8:
		var a = load("res://scripts/core/presentation/ggb_presenter.gd").new()
		var b = load("res://scripts/core/presentation/ggb_presenter.gd").new()
		root.add_child(a)
		root.add_child(b)
		a.present({"presentation":{"move":"heavy_drop","activation_id":"drop","lead":true}},1)
		b.present({"electrocution":{"activation_id":"grab","elapsed":.137}},1)
		var b_pose: Transform3D = b.meshes[0].transform
		check(a.lead_material != b.lead_material and a.originals[0] != b.originals[0],"duplicates own independent materials")
		a.reset()
		a.free()
		check(b.meshes[0].transform.is_equal_approx(b_pose) and b.output.identity == "electrocution:grab","other-instance reset/free cannot alter reaction")
		b.free()
		await process_frame
	if failures == 0: print("PASS: GGB actual kit trace invariance and duplicate material/reaction cleanup")
	quit(1 if failures else 0)

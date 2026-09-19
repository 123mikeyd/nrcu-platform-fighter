extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ",label)
func _init() -> void: call_deferred("run")
func poses(v) -> Array:
	var result: Array = []
	for b in v.skeleton.get_bone_count(): result.append(v.skeleton.get_bone_pose(b))
	return result
func run() -> void:
	var v = load("res://scripts/core/presentation/turbofit_presenter.gd").new()
	root.add_child(v)
	v.present({"locomotion":"walk","velocity":Vector3(2.5,0,0)},0)
	check(v.output.get("clip") == "Walk", "committed locomotion selects actual Walk")
	if failures:
		v.free()
		quit(1)
		return
	v.present({"locomotion":"run","velocity":Vector3(7.5,0,0)},1)
	v.present({"locomotion":"run","velocity":Vector3(7.5,0,0)},2)
	var frozen := poses(v)
	var clock: Dictionary = v.output.duplicate(true)
	v.present({"locomotion":"run","velocity":Vector3(7.5,0,0)},2)
	check(poses(v) == frozen and v.output == clock, "unchanged tick freezes whole blend and pose")
	v.present({"locomotion":"run","stopped":true},30)
	check(poses(v) == frozen, "stopped clock does not advance blend")
	v.present({"locomotion":"run","velocity":Vector3(7.5,0,0)},31)
	check(v.output.seconds < 0.1, "unfreeze excludes stopped tick gap")
	var request := {"clip":"MeleeHorizontal","activation_id":"first","elapsed":0.4,"duration":0.8,"facing":-1.0}
	v.present({"presentation":request},32)
	var starts: int = v.play_count
	request.activation_id = "second"
	request.elapsed = 0.0
	v.present({"presentation":request},32)
	check(v.play_count == starts+1 and v.output.seconds == 0,"same clip new identity restarts synchronously")
	request.elapsed = 0.1
	v.present({"presentation":request},33)
	frozen = poses(v)
	v.present({"presentation":request},50)
	check(poses(v) == frozen,"unchanged committed ability elapsed freezes independent of tick")
	v.present({"presentation":request,"status":"hitstun","hit_id":7},50)
	check(v.output.clip == "HitReactRight", "hit priority reconciles while clock unchanged")
	check(v.output.blend == 1.0, "synchronous hit completes blend without advancing simulation clock")
	v.present({"presentation":request,"status":"hitstun","hit_id":7,"locomotion":"rising","air_jumps_left":0},54)
	starts = v.play_count
	v.present({"presentation":request,"status":"hitstun","hit_id":7,"locomotion":"jump_startup"},55)
	check(v.play_count == starts and v.output.seconds > 0,"lower priority episodes cannot restart hit")
	v.present({"presentation":request,"status":"hitstun","hit_id":8},55)
	check(v.play_count == starts+1 and v.output.seconds == 0,"new hit identity restarts same clip")
	v.present({"presentation":{},"stopped":true},55)
	check(v.output.clip == "Idle" and v.output.identity != "second","cancel removes live identity even stopped")
	for pair in [["falling","FallLoop"],["fast_fall","FallLoop"],["landing","Landing"],["rising","Jump"],["idle","Idle"],["turn","Walk"]]:
		v.present({"locomotion":pair[0]},56)
		check(v.output.clip == pair[1],"source locomotion "+pair[0])
		if pair[0] == "turn": check(not v.output.fallback.is_empty(),"missing turn asset labeled")
	v.present({"action":"block"},56)
	check(v.output.clip == "BlockIdle","source shield")
	v.present({"action":"recovery","recovery_id":"rise"},56)
	check(v.output.clip == "Jump" and not v.output.fallback.is_empty(),"recovery legacy Jump fallback explicitly labeled")
	v.reset()
	check(v.output.is_empty(),"reset clears output and identity")
	v.present({"presentation":request},0)
	check(v.output.identity == "second", "reset accepts new generation at tick zero")
	v.free()
	if not failures: print("PASS: core turbo presenter lifecycle clocks priority mappings")
	quit(1 if failures else 0)

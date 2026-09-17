extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func run():
	var path = "res://scripts/core/stage/ledge_policy.gd"
	check(ResourceLoader.exists(path), "ledge policy exists")
	if failures: quit(1); return
	var p = load(path).new()
	var a = load("res://scripts/core/stage/ledge_anchor.gd").new()
	a.anchor_id = "left"
	var s = {1: actor(Vector3(-1, -1, 0), Vector3(1, -1, 0))}
	var r = p.advance({}, s, [a], 0, func(_points): return true)
	check(r.proposals[1].transition == "catch", "falling outside approach catches")
	check(r.proposals[1].restore_recovery, "first catch explicitly restores recovery")
	check(r.state.actors[1].anchor_id == "left", "stable anchor occupancy")
	check(s[1].position == Vector3(-1, -1, 0), "snapshot not mutated")
	finish()
func actor(at: Vector3, velocity: Vector3) -> Dictionary:
	return {"position": at, "velocity": velocity, "grounded": false, "status": "normal", "enabled": true, "intent": ""}
func finish():
	print("%s: ledge policy (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

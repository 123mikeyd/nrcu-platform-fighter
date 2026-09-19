extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var path := "res://data/moves/side_strike.tres"
	if not ResourceLoader.exists(path):
		check(false, "strike definition exposes exact legacy origin-cone and timing")
	else:
		var move = load(path)
		check(move.move_id == "SIDE STRIKE" and load("res://data/moves/air_strike.tres").move_id == "AIR STRIKE", "distinct context definitions")
		check(move.damage == 8 and move.base_knockback == 3.8 and move.cooldown_seconds == 0.32 and move.cooldown_ticks() == 20, "source payload and explicit ceiling preserved")
		check(move.contains(Vector3(2.5, 0, 0), 1), "range endpoint included")
		check(not move.contains(Vector3(2.5001, 0, 0), 1), "beyond range excluded")
		check(not move.contains(Vector3(1, 0, 1.5), 1) and move.contains(Vector3(1, 0, 1.499), 1), "z endpoint strictly excluded")
		check(not move.contains(Vector3(0.4, sqrt(0.84), 0), 1), "dot 0.4 endpoint excluded")
		check(move.contains(Vector3(0.401, sqrt(0.84), 0), 1), "just inside cone included")
		check(not move.contains(Vector3.ZERO, 1), "coincident origins excluded")
		check(not move.contains(Vector3(-1, 0, 0), 1) and move.contains(Vector3(-1, 0, 0), -1), "latched facing mirrors cone")
	if failures == 0: print("PASS: core combat definitions (%d checks)" % checks)
	quit(1 if failures else 0)

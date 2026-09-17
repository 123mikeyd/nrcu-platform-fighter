extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func hit(source: int, activation: String, base := 3.8, direction := Vector3.RIGHT) -> Dictionary:
	return {"tick": 0, "source": source, "victim": 30, "activation_id": activation, "damage": 8.0, "base_knockback": base, "direction": direction}
func run() -> void:
	var path := "res://scripts/core/combat/combat_resolver.gd"
	if not ResourceLoader.exists(path):
		check(false, "batched resolver exists with explicit multi-incoming policy")
	else:
		var r = load(path).new()
		var weak := hit(10, "1:1")
		var strong := hit(20, "1:2", 6.0, Vector3.LEFT)
		var result: Array = r.resolve([weak, strong, weak], {30: 4.0})
		check(result.size() == 1 and result[0].percent == 20.0, "sum unique damage per activation/victim")
		check(result[0].source == 20 and result[0].launch.x < 0, "strongest incoming launch wins independent of order")
		check(is_equal_approx(result[0].strength, 6.0 + 20.0 * 0.065 + 8.0 * 0.12), "all launch candidates use final batched percent")
		check(result[0].hitstun_ticks == ceili((0.08 + result[0].strength * 0.025) * 60), "legacy hitstun uses selected strength and ceil ticks")
		check(r.resolve([strong, weak], {30: 20.0}).is_empty(), "per-activation dedup survives repeated collection")
		r = load(path).new()
		result = r.resolve([hit(20, "1:2", 3.8, Vector3.LEFT), weak], {30: 0.0})
		check(result[0].source == 10 and result[0].launch.x > 0, "equal-strength launch tie uses smallest stable source ID")
	if failures == 0: print("PASS: core combat resolver (%d checks)" % checks)
	quit(1 if failures else 0)

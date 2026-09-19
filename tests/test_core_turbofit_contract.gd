extends SceneTree
const Kit = preload("res://scripts/core/kits/turbofit_kit.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func _init() -> void:
	var kit = Kit.new()
	kit.start("contract:1", Vector2(1, -1), false, -1)
	check(kit.snapshot().facing == -1, "up branch preserves source facing despite horizontal aim")
	check(kit.snapshot().get("phase", "missing") == "windup", "explicit action windup")
	kit.tick(0.28)
	check(kit.snapshot().get("phase", "missing") == "active", "single ground impact active phase")
	check(is_equal_approx(kit.snapshot().presentation.duration, 0.8), "guitar presentation retains .8 retime after impact cooldown replacement")
	kit.tick(0.1)
	check(kit.snapshot().get("phase", "missing") == "recovery", "explicit recovery phase")
	check(is_equal_approx(kit.snapshot().get("remaining", -1), 0.4), "remaining caller action lock")
	kit.cancel()
	check(kit.snapshot().get("phase", "missing") == "idle", "idle after cleanup")
	check(kit.snapshot().motion.is_empty(), "all basics preserve caller movement authority")
	if failures == 0: print("PASS: core Turbofit caller action/presentation contract")
	quit(1 if failures else 0)

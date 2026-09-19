extends SceneTree
const Kit = preload("res://scripts/core/kits/turbofit_kit.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func _init() -> void:
	for airborne in [false, true]:
		for aim in ([Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP] if not airborne else [Vector2.UP, Vector2(1, -1)]):
			var kit = Kit.new()
			check(kit.start("guitar:1", aim, airborne, -1), "guitar route accepted")
			var up: bool = aim.y < -0.1
			check(kit.snapshot().clip == ("MeleeBackhand" if up else "MeleeHorizontal"), "actual source guitar clip")
			check(is_equal_approx(kit.snapshot().duration, 0.8), "initial .8 cooldown")
			var target_position := Vector3(0, 2.7, 0) if up else Vector3(2.7 * (1 if aim.x > 0 else -1), 0, 0)
			var targets := [{"id": 2, "position": target_position}]
			kit.tick(0.279)
			check(kit.contacts(1, Vector3.ZERO, targets).is_empty(), "guitar .28 windup")
			kit.tick(0.001)
			var hits: Array = kit.contacts(1, Vector3.ZERO, targets)
			check(hits.size() == 1, "guitar uses source 2.8 range")
			if not hits.is_empty(): check(hits[0].damage == 14 and hits[0].base_knockback == 5.5, "not generic eight damage")
			kit.tick(0.499)
			check(kit.snapshot().active, "source impact replaces cooldown with .5")
			kit.tick(0.001)
			check(not kit.snapshot().active, "guitar recovery cleanup")
	if failures == 0: print("PASS: core Turbofit ground side/up and aerial up Guitar Swing")
	quit(1 if failures else 0)

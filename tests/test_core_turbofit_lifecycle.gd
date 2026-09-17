extends SceneTree
const Kit = preload("res://scripts/core/kits/turbofit_kit.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func _init() -> void:
	for move in [{"aim": Vector2.DOWN, "air": false}, {"aim": Vector2.RIGHT, "air": false}, {"aim": Vector2.RIGHT, "air": true}, {"aim": Vector2.DOWN, "air": true}]:
		for reason in ["interrupted", "disabled", "stock", "reset"]:
			var kit = Kit.new()
			kit.start("life:1", move.aim, move.air, 1)
			kit.tick(0.1)
			if reason in ["stock", "reset"]: kit.cancel()
			else: kit.tick(0.1, {reason: true})
			check(not kit.snapshot().active, reason + " cancels startup")
			check(kit.contacts(1, Vector3.ZERO, [{"id": 2, "position": Vector3.RIGHT}]).is_empty(), "canceled startup cannot hit")
			check(kit.snapshot().activation_id.is_empty() and kit._victims.is_empty(), "cancel releases activation/victim state")
			check(kit.start("life:2", move.aim, move.air, 1), "fresh episode after interruption")
	var first = Kit.new()
	var second = Kit.new()
	first.start("one:1", Vector2.DOWN, false, -1)
	second.start("two:1", Vector2.DOWN, false, 1)
	first.tick(0.2)
	var before: Dictionary = first.snapshot()
	for reason in ["paused", "frozen", "hitstop"]:
		first.tick(3.0, {reason: true})
		check(first.snapshot() == before, reason + " preserves entire presentation/ability clock")
	first.tick(0.25)
	check(second.snapshot().elapsed == 0 and second.snapshot().facing == 1, "two instances independent")
	var targets := [{"id": 2, "position": Vector3.LEFT}, {"id": 3, "position": Vector3.LEFT}, {"id": 4, "position": Vector3.LEFT, "eligible": false}]
	check(first.contacts(1, Vector3.ZERO, targets).size() == 2, "one hit per eligible victim not one per episode")
	first.tick(0, {"hitstop": true})
	check(first.contacts(1, Vector3.ZERO, [{"id": 5, "position": Vector3.LEFT}]).is_empty(), "hitstop does not emit new contacts")
	first.cancel()
	check(first._victims.is_empty(), "dedup resources cleared")
	check(second.snapshot().active, "other episode survives cleanup")
	# Landing affects authored airborne kicks only; guitar up is legacy fallback.
	first.start("one:2", Vector2.UP, true, 1)
	first.tick(0.1, {"grounded": true})
	check(first.snapshot().active, "landing does not cancel guitar up fallback")
	if failures == 0: print("PASS: core Turbofit interruption, pause/hitstop, resources and independent instances")
	quit(1 if failures else 0)

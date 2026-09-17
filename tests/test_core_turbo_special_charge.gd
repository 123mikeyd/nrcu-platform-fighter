extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ", label)
func _initialize() -> void:
	var path := "res://scripts/core/kits/turbofit_specials.gd"
	if not ResourceLoader.exists(path):
		check(false, "Power Chord caller-ticked module missing")
		quit(1); return
	var kit = load(path).new()
	var other = load(path).new()
	check(not kit.start("", Vector2.ZERO, 1), "caller ID required")
	check(kit.start("charge:1", Vector2.ZERO, -1), "neutral starts")
	check(not kit.start("charge:2", Vector2.ZERO, 1), "cannot replace owned episode")
	kit.tick(12.0, {"held": true})
	check(kit.snapshot().phase == "anticipation" and kit.snapshot().age == 12, "indefinite hold")
	check(kit.snapshot().power == 1.0, "power caps at 1.5 seconds")
	var before: Dictionary = kit.snapshot()
	kit.tick(1.0, {"held": false, "advance": false})
	check(kit.snapshot() == before, "no-advance freezes clock and release")
	kit.tick(0.01, {"held": false})
	var targets := [{"id": 9, "position": Vector3(-3,0,0)}, {"id": 2, "position": Vector3(-1,0,0)}, {"id": 4, "position": Vector3(1,0,0)}, {"id": 5, "position": Vector3(-3.001,0,0)}, {"id": 6, "position": Vector3(-1,0,1.5)}]
	var hits: Array = kit.collect(1, Vector3.ZERO, targets)
	check(hits.size() == 2 and hits[0].victim == 2 and hits[1].victim == 9, "sorted inclusive range, strict depth and cone")
	if hits.size() > 0:
		check(hits[0].damage == 26 and hits[0].base_knockback == 9 and hits[0].direction == Vector3(-1,.35,0), "capped payload and committed facing")
		check(hits[0].activation_id == "charge:1", "stable activation")
	check(kit.collect(1,Vector3.ZERO,targets).is_empty(), "release exactly once")
	check(kit.snapshot().cooldown == .7, "release cooldown starts at contact")
	check(other.snapshot().phase == "idle", "two instances isolated")
	kit.tick(.7)
	check(kit.snapshot().phase == "idle", "release lifetime expires")
	for hold in [0.0, .75, 1.5]:
		kit.start("tap:" + str(hold), Vector2.ZERO, 1)
		kit.tick(hold, {"held": true})
		kit.tick(.001, {"held": false})
		hits = kit.collect(1, Vector3.ZERO, [{"id": 2, "position": Vector3.RIGHT}])
		check(hits.size() == 1 and is_equal_approx(hits[0].damage, lerpf(10,26,hold/1.5)) and is_equal_approx(hits[0].base_knockback,lerpf(4,9,hold/1.5)), "charge endpoints")
		kit.cancel()
	check(kit.snapshot().activation_id == "" and kit.collect(1,Vector3.ZERO,targets).is_empty(), "cancel cleans ownership")
	if failures == 0: print("PASS core Turbofit Power Chord")
	quit(1 if failures else 0)

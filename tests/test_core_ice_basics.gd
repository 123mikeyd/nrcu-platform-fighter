extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func run():
	var path := "res://scripts/core/kits/ice_mage_kit.gd"
	check(ResourceLoader.exists(path), "IceStrike definition/runtime exists")
	if failures: quit(1); return
	var script = load(path)
	for facing in [-1.0, 1.0]:
		for airborne in [false, true]:
			for aim in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1,-1), Vector2(-1,1)]:
				var kit = script.new()
				var direction := Vector3(facing, 0, 0)
				if aim.y < -.1: direction = Vector3.UP
				elif aim.y > .1: direction = Vector3.DOWN if airborne else Vector3(facing,-.25,0).normalized()
				elif absf(aim.x) > .1: direction.x = signf(aim.x)
				var targets := [{"id":2,"position":direction * 2.0},{"id":3,"position":-direction},{"id":4,"position":direction,"eligible":false}]
				check(kit.start("strike",aim,airborne,facing), "all source basic routes accepted")
				check(kit.snapshot().clip == "IceStrike", "authored clip, no fallback")
				kit.tick(.199)
				check(kit.contacts(1,Vector3.ZERO,targets).is_empty(), "windup")
				kit.tick(.001)
				var hits = kit.contacts(1,Vector3.ZERO,targets)
				check(hits.size() == 1, "one source cone contact")
				if hits.size() == 1:
					var launch := direction
					if absf(direction.y) < .5: launch.y = .35
					check(hits[0].damage == 8 and hits[0].base_knockback == 3.8 and hits[0].direction == launch, "source payload/directional launch")
				check(kit.contacts(1,Vector3.ZERO,targets).is_empty(), "single query consumed")
				kit.tick(.35)
				check(not kit.snapshot().active, "exact .55 action endpoint")
	var k = script.new()
	k.start("cancel",Vector2.ZERO,false,1)
	k.tick(.19)
	k.cancel()
	k.tick(.5)
	check(k.contacts(1,Vector3.ZERO,[{"id":2,"position":Vector3.RIGHT}]).is_empty(), "cancel cannot leave pending impact")
	k.start("cross",Vector2.ZERO,false,1)
	k.tick(.6)
	check(k.contacts(1,Vector3.ZERO,[{"id":2,"position":Vector3.RIGHT}]).size()==1, "source event precedes expiry on large crossing step")
	if failures == 0: print("PASS: IceStrike source directional routes, clocks, cancel, one-shot candidates")
	quit(1 if failures else 0)

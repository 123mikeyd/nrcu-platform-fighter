extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func step(h):
	h.prepare(false)
	h.advance(false)
func run():
	var path := "res://scripts/core/kits/ice_mage_host.gd"
	check(ResourceLoader.exists(path), "Ice host protocol exists")
	if failures: quit(1); return
	var script = load(path)
	var registry = load("res://scripts/core/kits/kit_registry.gd").new()
	registry.register_factory("ice_mage",script)
	var h = registry.create("ice_mage")
	var other = registry.create("ice_mage")
	for facing in [-1.0,1.0]:
		for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.DOWN]:
			h.cancel(true)
			h.prepare(false)
			check(h.start_special("cast",aim,facing,true), "cast route")
			check(h.initial_requests(1,Vector3.ZERO).is_empty(), "cast no immediate spawn")
			h.advance(false)
			for i in 10: step(h)
			check(h.collect(1,Vector3.ZERO,[]).is_empty(), "before .2 no spawn")
			step(h)
			var effects = h.collect(1,Vector3(5,2,0),[])
			check(effects.size()==1, "accepted tick advances cast to .2")
			if effects.size()==1:
				var f: float = signf(aim.x) if absf(aim.x)>.1 else facing
				check(effects[0].kind=="spawn_projectile" and effects[0].projectile_kind=="frost_bolt" and effects[0].position==Vector3(5+f*.85,3.5,0), "typed bolt spawn at post-move source offset")
			check(h.collect(1,Vector3.ZERO,[]).is_empty(), "spawn once")
			for i in 20: step(h) # Source subtracts cooldown before acceptance, strict >0 gate.
			check(not h.locked(), ".5 action expires independently of cast budget")
			check(not h.start_special("early",aim,facing,true), "1.6 cast budget retained")
			check(h.start_basic("basic",Vector2.ZERO,false,facing), "cast budget does not block basic")
			h.cancel()
			for i in 100: step(h)
			check(h.start_special("late",aim,facing,true), "cast replenishes by explicit ticks")
	h.cancel(true)
	check(not h.start_special("no-rise",Vector2.UP,1,false) and not h.locked(), "unavailable recovery rejection pure")
	check(h.start_special("rise",Vector2.UP,-1,true), "Frost Rise accepted")
	var rise = h.initial_requests(1,Vector3.ZERO)
	check(rise.size()==1 and rise[0].kind=="recovery_request" and rise[0].vertical_speed==13.5 and rise[0].jumps_used==2, "existing recovery resource request")
	for i in 45:
		step(h)
		check(h.collect(1,Vector3.ZERO,[]).is_empty(), "rise never emits bolt")
	h.cancel(true)
	h.start_special("cancel",Vector2.ZERO,1,true)
	for i in 11: step(h)
	var before = h.snapshot()
	check(h.snapshot()==before, "without host tick hitstop/pause leaves clocks unchanged")
	h.cancel()
	for i in 30: step(h)
	check(h.collect(1,Vector3.ZERO,[]).is_empty() and not h.start_special("budget",Vector2.ZERO,1,true), "interruption kills pending spawn not cast budget")
	check(not other.locked() and other.snapshot().cast_cooldown==0, "duplicate host independence")
	h.cancel(true)
	check(not h.locked() and h.snapshot().cast_cooldown==0, "reset clears both budgets")
	if failures == 0: print("PASS: Ice registry adapter, cast/recovery routing, accepted clocks and cancellation")
	quit(1 if failures else 0)

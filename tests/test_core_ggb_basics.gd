extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func run():
	var path := "res://scripts/core/kits/ggb_kit.gd"
	check(ResourceLoader.exists(path), "GGB independent kit exists")
	if failures: quit(1); return
	var script = load(path)
	for air in [false,true]:
		for facing in [-1.0,1.0]:
			for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(1,-1),Vector2(-1,1),Vector2(.1,-.1)]:
				var k = script.new()
				var direction := Vector3(facing,0,0)
				var label := "AIR STRIKE" if air else "SIDE STRIKE"
				if aim.y < -.1:
					direction = Vector3.UP
					label = "UP AIR" if air else "UPPERCUT"
				elif aim.y > .1:
					direction = Vector3.DOWN if air else Vector3(facing,-.25,0).normalized()
					label = "DOWN STRIKE" if air else "LOW SWEEP"
				elif absf(aim.x) > .1: direction.x = signf(aim.x)
				check(k.start_basic("a",aim,air,facing), "basic route accepted")
				# Non-axis normalized vectors round outside exact radius at *2.5.
				var target := {"id":2,"position":direction*(2.0 if aim.y > .1 and not air else 2.5)}
				var hits = k.collect(1,Vector3.ZERO,[target,target,{"id":3,"position":-direction},{"id":4,"position":direction,"eligible":false}])
				check(hits.size()==1, "instant inclusive range contact, dedup and eligibility")
				if hits.size()==1:
					check(hits[0].damage==8 and hits[0].base_knockback==3.8 and hits[0].activation_id=="a", "source payload")
				check(k.snapshot().basic.clip==label, "six source route labels")
				check(k.collect(1,Vector3.ZERO,[target]).is_empty(), "one collection")
				check(not k.start_basic("b",aim,air,facing), "cooldown blocks restart")
				for i in 19: k.prepare(false)
				check(k.locked(), "source .32 cooldown remains before crossing")
				k.prepare(false)
				check(k.start_basic("b",aim,air,facing), "next committed cooldown crossing accepts")
	var a = script.new()
	var b = script.new()
	a.start_basic("a",Vector2.RIGHT,false,1)
	b.start_basic("b",Vector2.LEFT,false,-1)
	var trade = a.collect(1,Vector3.ZERO,[{"id":2,"position":Vector3.RIGHT}]) + b.collect(2,Vector3.RIGHT,[{"id":1,"position":Vector3.ZERO}])
	check(trade.size()==2, "caller can snapshot reciprocal candidates before cancellation")
	a.cancel()
	check(b.locked(), "independent instances")
	if failures==0: print("PASS: GGB six instant basic routes, endpoints, latches, trades, cooldown")
	quit(1 if failures else 0)

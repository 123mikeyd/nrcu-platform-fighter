extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: "+message)
func run():
	var path := "res://scripts/core/kits/ggb_host.gd"
	check(ResourceLoader.exists(path),"GGB host exists")
	if failures: quit(1); return
	var h = load(path).new()
	for facing in [-1.0,1.0]:
		h.cancel(true)
		check(not h.start_special("tiny",Vector2(.05,0),facing,true),"nonzero deadband is not neutral charge")
		check(h.start_special("goo",Vector2(facing,0),-facing,true),"side goo")
		var requests = h.initial_requests(1,Vector3(3,4,0))
		check(requests.size()==1 and requests[0].kind=="spawn_projectile" and requests[0].projectile_kind=="sticky_goo" and requests[0].position==Vector3(3+facing*.8,5,0),"source immediate goo origin")
		check(h.initial_requests(1,Vector3.ZERO).is_empty(),"spawn only once")
		check(h.cooldown==.55,"side budget")
		h.cancel(true)
		check(not h.start_special("rise",Vector2.UP,facing,false),"recovery rejection pure")
		check(h.start_special("rise",Vector2(1,-1),facing,true),"vertical priority recovery")
		requests = h.initial_requests(1,Vector3.ZERO)
		check(requests.size()==1 and requests[0].kind=="recovery_request" and requests[0].vertical_speed==13.5 and requests[0].jumps_used==2,"shared source recovery request")
		h.cancel(true)
		check(h.start_special("charge",Vector2.ZERO,facing,true),"charge ground or air")
		h.advance(true)
		check(h.snapshot().special.power==0 and h.braking(),"entry not held interval")
		for i in 120: h.prepare(true)
		check(h.snapshot().special.power==1 and h.locked(),"capped power indefinite hold")
		h.prepare(false)
		var hits = h.collect(1,Vector3.ZERO,[{"id":2,"position":Vector3(facing*3,0,0)}])
		check(hits.size()==1 and hits[0].damage==26 and hits[0].base_knockback==9,"full charge source cone")
		check(h.cooldown==.7 and not h.braking(),"release retains fresh cooldown")
		h.cancel(true)
		h.start_special("tap",Vector2.ZERO,facing,true)
		h.prepare(false)
		hits = h.collect(1,Vector3.ZERO,[{"id":2,"position":Vector3(facing,0,0)}])
		check(hits.size()==1 and is_equal_approx(hits[0].damage,lerpf(10,26,(1.0/60.0)/1.5)),"legacy release frame adds held delta before releasing")
	h.cancel(true)
	check(h.start_special("drop",Vector2(1,1),1,true),"drop vertical priority")
	check(h.pre_move_requests(1)[0].velocity==Vector3(0,-24,0),"committed descent each move")
	h.landed(false)
	check(h.collect(1,Vector3.ZERO,[]).is_empty() and h.snapshot().presentation.lead,"air no slam")
	h.landed(true)
	var targets := [{"id":2,"position":Vector3(-2,0,0)},{"id":3,"position":Vector3(2.8001,0,0)}]
	var slam = h.collect(1,Vector3.ZERO,targets+targets)
	var hits := []
	for event in slam:
		if event.kind=="hit": hits.append(event)
	check(hits.size()==1 and hits[0].damage==18 and hits[0].direction==Vector3(-1,.8,0),"once radial strict 2.8 slam")
	check(h.cooldown==.65 and h.braking() and not h.snapshot().presentation.lead,"land locks and restores gummy")
	h.landed(true)
	check(h.collect(1,Vector3.ZERO,targets).is_empty(),"landing idempotent")
	for status in ["hitstun","frozen","caught","disabled"]:
		h.cancel(true); h.start_special(status,Vector2.DOWN,1,true); h.cancel_for_status(status)
		check(h.pre_move_requests(1).is_empty() and h.collect(1,Vector3.ZERO,targets).is_empty() and not h.snapshot().presentation.lead,"interruption cancels lead/motion/contact")
	if failures==0: print("PASS: GGB host specials, charge source clocks, drop motion/landing, interruption")
	quit(1 if failures else 0)

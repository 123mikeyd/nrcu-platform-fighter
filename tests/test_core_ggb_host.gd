extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures+=1;printerr("FAIL: "+message)
func run():
	var h = load("res://scripts/core/kits/ggb_host.gd").new()
	check(h.has_method("commit_jump") and h.has_method("motion_requests"),"host composes GGB air resource/motion seam")
	if failures:quit(1);return
	h.commit_jump(1,{})
	h.start_special("rise",Vector2.UP,1,true)
	check(h.snapshot().air.recovery_spent and h.snapshot().air.jumps_used==2,"accepted recovery atomically spends own policy")
	h.cancel_for_status("frozen")
	check(h.commit_jump(1,{}).is_empty() and h.snapshot().air.recovery_spent,"freeze no air refund")
	h.cancel(true)
	check(h.snapshot().air.jumps_used==0 and h.commit_jump(1,{}).vertical_speed==10.5,"life reset refunds")
	h.cancel(true);h.start_special("drop",Vector2.DOWN,1,true);h.landed(true)
	for status in ["hitstun","frozen","caught"]:
		h.cancel_for_status(status)
		check(h.landing_lag==.65 and h.commit_jump(1,{}).is_empty(),"source landing lag survives "+status)
	h.advance_inactive(.2)
	check(is_equal_approx(h.landing_lag,.45),"inactive lag advances explicit clock")
	h.cancel(true);h.start_special("goo",Vector2.RIGHT,1,true);h.initial_requests(1,Vector3.ZERO)
	for i in 34:h.prepare(false)
	check(h.start_basic("basic",Vector2.UP,false,1) and h.snapshot().special.move=="", "new basic clears stale special presentation")
	h.cancel(true)
	var floor_body := StaticBody3D.new();var box := BoxShape3D.new();box.size=Vector3(8,.2,4)
	var shape := CollisionShape3D.new();shape.shape=box;floor_body.add_child(shape);root.add_child(floor_body);floor_body.position.y=2
	var body := CharacterBody3D.new();var capsule := CapsuleShape3D.new();capsule.radius=.4;capsule.height=2
	shape=CollisionShape3D.new();shape.shape=capsule;shape.position.y=1;body.add_child(shape);root.add_child(body);body.position.y=5
	await physics_frame;await process_frame
	h.commit_jump(1,{})
	h.start_special("real-drop",Vector2.DOWN,1,true)
	var stopped = h.snapshot()
	await physics_frame;await process_frame
	check(h.snapshot()==stopped,"no autonomous clocks while stopped")
	var count := 0;var landed := false
	for i in 90:
		await physics_frame;await process_frame
		h.prepare(false)
		var requests = h.motion_requests(1,1.0/60.0,{"velocity":body.velocity,"jump_held":true})
		for request in requests:
			if request.mode=="velocity_override":body.velocity=request.velocity
		check(h.commit_jump(1,{}).is_empty(),"drop cannot jump cancel")
		body.move_and_slide()
		var support: bool = h.air.terrain_grounded(body,[])
		h.landed(support)
		for event in h.collect(1,body.position,[{"id":2,"position":Vector3(1,2.1,0)}]):
			if event.kind=="hit":count+=1
		if support:
			landed=true;break
	check(landed and absf(body.position.y-2.1)<.02 and count==1,"real raised top movement leads exactly one slam")
	check(h.snapshot().air.jumps_used==0 and h.snapshot().air.float_remaining==1.2 and h.braking(),"post-slide terrain refills and locks")
	body.free();floor_body.free()
	# Existing generic host accepts Goo factory and preserves lifecycle ownership.
	var projectiles = load("res://scripts/core/combat/projectile_host.gd").new()
	projectiles.register_factory("sticky_goo",load("res://scripts/core/kits/ggb_goo_projectile.gd"))
	h.cancel(true);h.start_special("factory",Vector2.RIGHT,1,true)
	check(projectiles.spawn(h.initial_requests(1,Vector3(0,20,0))[0],1),"established generic factory accepts goo")
	projectiles.reflect("factory",2,2);projectiles.expire_source(1)
	check(projectiles.snapshots().size()==1,"shared host reflected owner survives")
	projectiles.expire_source(2)
	check(projectiles.snapshots().is_empty(),"shared host current source cleanup")
	if failures==0:print("PASS: GGB independent host air/drop native motion, source cancellation and generic projectile protocol")
	quit(1 if failures else 0)

extends SceneTree
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures+=1;printerr("FAIL: "+message)
func run():
	var h = load("res://scripts/core/kits/ggb_host.gd").new()
	var projectiles = load("res://scripts/core/combat/projectile_host.gd").new()
	projectiles.register_factory("sticky_goo",load("res://scripts/core/kits/ggb_goo_projectile.gd"))
	var pools = load("res://scripts/core/kits/ggb_puddles.gd").new()
	var floor_body := StaticBody3D.new();var box := BoxShape3D.new();box.size=Vector3(20,.2,5)
	var shape := CollisionShape3D.new();shape.shape=box;floor_body.add_child(shape);root.add_child(floor_body);floor_body.position.y=2
	await physics_frame;await process_frame
	h.start_special("flight",Vector2.RIGHT,1,true)
	projectiles.spawn(h.initial_requests(1,Vector3(0,3,0))[0],1)
	h.cancel_for_status("frozen")
	check(projectiles.snapshots().size()==1,"actor freeze does not retract emitted goo")
	projectiles.advance(.1,{})
	var before = projectiles.snapshots()[0]
	projectiles.reflect("flight",2,2)
	check(projectiles.snapshots()[0].remaining==before.remaining,"generic reflection does not refresh goo ttl")
	var spawned := false
	for i in 80:
		var events = projectiles.advance(1.0/60.0,{"space":floor_body.get_world_3d().direct_space_state,"targets":[]})
		for event in events:
			if event.kind=="spawn_puddle":
				spawned=pools.spawn(event)
		if spawned:break
	check(spawned and projectiles.snapshots().is_empty(),"real projectile top event consumed by independent hazard host")
	if spawned:
		var pool = pools.snapshots()[0]
		check(pool.source==2 and absf(pool.position.y-2.125)<.001,"reflected ownership and physical top carried through")
		var target := {"id":1,"team":1,"position":pool.position-Vector3.UP*.025,"velocity":Vector3.ZERO,"grounded":true,"support_surface":floor_body}
		check(pools.collect([target]).size()==1,"reflected pool slows old source")
		pools.expire_source(1);check(pools.snapshots().size()==1,"old source cleanup not new pool")
		pools.expire_source(2);check(pools.collect([target]).is_empty(),"KO/reset current source immediately removes modifier")
	# The existing recovery contact implementation is the source-identical seam,
	# not Teknium Force/Grab or a different GGB invented attack.
	h.cancel(true);h.start_special("recovery",Vector2.UP,-1,true)
	var request = h.initial_requests(1,Vector3.ZERO)[0]
	var rise = load("res://scripts/core/combat/recovery_ability.gd").new(request.facing,request.activation_id)
	for i in 23:rise.advance()
	var hit = rise.contact(1,2,Vector3(1,2,0),23)
	check(rise.age==23 and hit.damage==12 and hit.base_knockback==5.5 and hit.direction==Vector3(-.2,1,0),"existing recovery final crossing payload")
	check(rise.contact(1,2,Vector3(1,2,0),23).is_empty(),"recovery target once ledger")
	floor_body.free()
	if failures==0:print("PASS: GGB emitted goo -> native top -> reflected finite slow and shared recovery seam")
	quit(1 if failures else 0)

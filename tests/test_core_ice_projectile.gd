extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func body(at: Vector3):
	var b := CharacterBody3D.new()
	var c := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .55
	shape.height = 1.8
	c.shape = shape
	c.position.y = .9
	b.add_child(c)
	root.add_child(b)
	b.position = at
	return b
func run():
	var path := "res://scripts/core/kits/ice_frost_projectile.gd"
	check(ResourceLoader.exists(path), "caller-owned frost projectile exists")
	if failures: quit(1); return
	var script = load(path)
	var source = body(Vector3(-4,0,0))
	var victim = body(Vector3.ZERO)
	await physics_frame
	await physics_frame
	var targets := [{"id":1,"body":source,"position":source.position},{"id":2,"body":victim,"position":victim.position}]
	var context := {"space":root.world_3d.direct_space_state,"targets":targets}
	for facing in [-1.0,1.0]:
		var p = script.new()
		p.start("contact",1,-1,Vector3(-facing*2,1.5,0),facing)
		var hits = p.tick(.2,context)
		check(hits.size()==1 and hits[0].kind=="hit", "actual capsule ray contact both facings")
		if hits.size()==1:
			check(hits[0].damage==4 and hits[0].base_knockback==1 and hits[0].direction==Vector3(facing,.2,0), "source bolt payload")
			check(hits[0].status_requests.size()==1 and hits[0].status_requests[0].duration==1.0 and hits[0].status_requests[0].immunity==1.0, "freeze request on ordered accepted damage, not mutation")
		check(not p.active and p.tick(.1,context).is_empty(), "one impact consumes projectile")
		check(victim.velocity==Vector3.ZERO, "contact module cannot mutate victim")
	var p = script.new()
	p.start("budget",1,-1,Vector3(10,3,0),1)
	p.tick(1.59)
	check(p.active, "just before TTL live")
	var pos: Vector3 = p.position
	p.tick(.011)
	check(not p.active and p.position==pos, "TTL advances before movement/contact, no expiry epsilon")
	p.start("exact",1,-1,Vector3.ZERO,1)
	p.tick(1.6,context)
	check(not p.active and p.position==Vector3.ZERO, "exact TTL skips query")
	p.start("reflect",1,7,Vector3(10,3,0),1)
	p.tick(1.2)
	var age: float = p.age
	check(p.reflect(2,8), "reflect supported")
	check(p.source==2 and p.team==8 and p.facing==-1 and p.remaining==.8 and p.age==age and p.activation_id=="reflect", "source reflect extends remaining to .8, identity/age retained")
	p.expire_source(1)
	check(p.active, "old owner KO does not expire reflected bolt")
	p.expire_source(2)
	check(not p.active, "current owner KO expires")
	p.start("reflected-contact",1,-1,Vector3(2,1.5,0),1)
	p.reflect(2,-1)
	var reflected = p.tick(.5,context)
	check(reflected.size()==1 and reflected[0].victim==1 and reflected[0].source==2 and reflected[0].status_requests.size()==1,"reflected real ray excludes new owner and freezes original caster by request")
	p.start("detached",1,-1,Vector3(10,3,0),1)
	p.tick(.1,{"hitstop":true})
	check(p.age==.1, "actor hitstop does not stop detached world tick")
	var snapshot = p.snapshot()
	p.tick(.1,{"paused":true})
	check(p.snapshot()==snapshot, "global pause stops world clock")
	p.tick(.1,{"owner_enabled":false})
	check(not p.active, "disabled source cleanup")
	# Source fallback radius .75 around target+UP, after a miss in physics space.
	p.start("fallback",1,-1,Vector3(-2,1,.7),1)
	check(p.tick(.2,context).size()==1, "legacy unsynchronized-body fallback preserved")
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2,4,4)
	cs.shape = box
	wall.add_child(cs)
	root.add_child(wall)
	wall.position.x = -1
	await physics_frame
	await physics_frame
	p.start("terrain",1,-1,Vector3(-2,1.5,0),1)
	var terrain = p.tick(.2,context)
	check(terrain.size()==1 and terrain[0].kind=="terrain", "terrain ray precedes fallback target")
	wall.free()
	await physics_frame
	await physics_frame
	targets[1].shielding = true
	p.start("shield",1,-1,Vector3(-2,1.5,0),1)
	var shield = p.tick(.2,context)
	check(shield.size()==1 and shield[0].damage==4 and shield[0].status_requests.is_empty(), "shield retains shared chip candidate but suppresses freeze")
	targets[1].shielding = false
	targets[1].absorbing = true
	p.start("absorb",1,-1,Vector3(-2,1.5,0),1)
	var absorb = p.tick(.2,context)
	check(absorb.size()==1 and absorb[0].kind=="absorb" and absorb[0].payload_damage==4, "absorption consumes payload only after contact")
	targets[1].absorbing = false
	targets[1].team = 3
	p.start("team",1,3,Vector3(-2,1.5,0),1)
	check(p.tick(.2,context).is_empty() and p.active, "friendly real collider excluded")
	p.cancel()
	source.free()
	victim.free()
	if failures==0: print("PASS: Ice real ray/fallback contacts, terrain, reflection, budgets, payload/status requests")
	quit(1 if failures else 0)

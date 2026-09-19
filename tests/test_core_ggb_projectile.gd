extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1; printerr("FAIL: "+message)
func box(pos: Vector3, size: Vector3):
	var body := StaticBody3D.new(); var shape := CollisionShape3D.new();var resource := BoxShape3D.new()
	resource.size=size;shape.shape=resource;body.add_child(shape);root.add_child(body);body.position=pos
	return body
func run():
	var path := "res://scripts/core/kits/ggb_goo_projectile.gd"
	check(ResourceLoader.exists(path),"independent GGB goo projectile exists")
	if failures: quit(1); return
	var script = load(path)
	var p = script.new(); p.start("arc",1,1,Vector3(0,30,0),1)
	p.tick(.1)
	check(p.position.is_equal_approx(Vector3(.55,30.16,0)) and is_equal_approx(p.fall_speed,1.6),"source semi-implicit arc")
	var before = p.snapshot()
	p.tick(.2,{"paused":true})
	check(p.snapshot()==before,"world pause freezes all budgets")
	p.tick(.1,{"stopped":true})
	check(p.age>.1,"actor hitstop does not freeze detached goo")
	var remaining: float = p.remaining
	var travel: float = p.travel
	p.reflect(2,2)
	check(p.source==2 and p.team==2 and p.facing==-1 and p.remaining==remaining and p.travel==travel,"reflection transfers no budget refund")
	p.expire_source(1);check(p.active,"old owner reset not reflected owner")
	p.expire_source(2);check(not p.active,"current owner reset expires")
	p=script.new();p.start("cap",1,1,Vector3(0,30,0),1)
	for i in 10: p.tick(.1)
	check(p.travel==4.5 and p.position.x<=4.50001,"finite travel cap")
	p.tick(.6);check(not p.active,"finite TTL no final expired contact")
	var body := CharacterBody3D.new();var shape := CollisionShape3D.new();var capsule := CapsuleShape3D.new()
	capsule.radius=.4;capsule.height=2;shape.shape=capsule;shape.position.y=1;body.add_child(shape);root.add_child(body)
	var world := body.get_world_3d().direct_space_state
	var targets := [{"id":2,"team":2,"body":body,"position":Vector3.ZERO}]
	await physics_frame;await process_frame
	for facing in [-1.0,1.0]:
		p=script.new();p.start("capsule",1,1,Vector3(-facing*1.5,1.2,0),facing)
		p.fall_speed=5.4 # cancels .3 gravity: isolate ordered horizontal segment
		var hits = p.tick(.3,{"space":world,"targets":targets})
		check(hits.size()==1 and hits[0].kind=="hit" and hits[0].damage==11 and hits[0].base_knockback==4.5,"native capsule sweep in both facings")
		check(not p.active and p.tick(.1,{"space":world,"targets":targets}).is_empty(),"one swept hit")
	var wall = box(Vector3(-.8,1,0),Vector3(.05,4,3))
	await physics_frame;await process_frame
	p=script.new();p.start("wall",1,1,Vector3(-1.5,1.2,0),1);p.fall_speed=5.4
	var events = p.tick(.3,{"space":world,"targets":targets})
	check(events.size()==1 and events[0].kind=="terrain","thin wall occludes fighter; no wall pool")
	wall.free();body.position=Vector3(10,0,0)
	var floor_body = box(Vector3(0,2,0),Vector3(5,.2,3))
	await physics_frame;await process_frame
	p=script.new();p.start("top",1,1,Vector3(0,3,0),1);p.fall_speed=-5;p.travel=4.5
	events=p.tick(.2,{"space":world,"targets":targets})
	check(events.size()==1 and events[0].kind=="spawn_puddle" and events[0].surface==floor_body and absf(events[0].position.y-2.125)<.001,"actual raised terrain top spawn")
	p=script.new();p.start("ceiling",1,1,Vector3(0,1.5,0),1);p.fall_speed=8;p.travel=4.5
	events=p.tick(.1,{"space":world,"targets":targets})
	check(events.size()==1 and events[0].kind=="terrain","ascending underside no pool")
	floor_body.free();body.position=Vector3.ZERO
	await physics_frame;await process_frame
	targets[0].absorbing=true
	p=script.new();p.start("absorb",1,1,Vector3(-1.5,1,0),1);p.fall_speed=5.4
	events=p.tick(.3,{"space":world,"targets":targets})
	check(events.size()==1 and events[0].kind=="absorb" and events[0].payload_damage==11,"shared absorb payload before damage")
	targets[0].team=1
	p=script.new();p.start("friend",1,1,Vector3(-1.5,1,0),1);p.fall_speed=5.4
	check(p.tick(.3,{"space":world,"targets":targets}).is_empty() and p.active,"friendly native body excluded")
	p.tick(.1,{"owner_enabled":false});check(not p.active,"disabled owner cancels")
	body.free()
	if failures==0: print("PASS: GGB goo native swept capsule/terrain, arc, finite budgets, reflect and absorb")
	quit(1 if failures else 0)

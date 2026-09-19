extends SceneTree
const L = preload("res://scripts/fighter.gd")
const C = preload("res://scripts/core/fighter/fighter_actor.gd")
const OUT = "res://.verification/core/body-contact/"
class Driver extends L:
	var axis := 0.0
	func read_controls(_dt: float) -> Dictionary:
		return {"left":axis < 0,"right":axis > 0,"up":false,"down":false,"jump":false,"attack":false,"special":false,"shield":false}
var reports: Array = []
var failures := 0
func check(ok, label):
	if not ok: failures += 1; print("FAIL: ",label)
func _initialize(): call_deferred("run")
func block(world, at, size):
	var b = StaticBody3D.new()
	b.position = at
	b.collision_layer = 1; b.collision_mask = 0
	var s = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = size; s.shape = box; b.add_child(s); world.add_child(b)
func grounded(a, mode): return a.is_grounded() if mode == "legacy" else a.runtime.grounded
func reset_actor(a, mode, at):
	if mode == "legacy": a.reset_fighter(at)
	else: a.reset_at(at)
func tick(actors, mode, order, commands):
	await physics_frame
	for id in order:
		var a = actors[id]
		if mode == "legacy":
			a.axis = commands[id].get("move_x", 0.0)
			a._physics_process(1.0 / 60.0)
		else: a.simulate(commands[id])
func run_case(mode, scenario, mover, reverse, direction):
	var world = Node3D.new(); root.add_child(world)
	block(world, Vector3(0,-0.5,0), Vector3(60,1,6))
	var order = [2,1] if reverse else [1,2]
	var actors = {}
	for id in order:
		var a = Driver.new() if mode == "legacy" else C.new()
		if mode == "legacy": a.character_id = "probe"; a.player_index = id
		else: a.profile = load("res://data/characters/teknium_movement.tres")
		a.position = Vector3(id * 4, 0.1, 0)
		world.add_child(a); a.set_physics_process(false)
		if a.has_method("set_body_contacts"): a.set_body_contacts(true)
		actors[id] = a
	var target = 3 - mover
	var a = actors[mover]; var b = actors[target]
	for i in 15: await tick(actors, mode, order, {1:{},2:{}})
	reset_actor(b,mode,Vector3.ZERO)
	var head = scenario.begins_with("head")
	var offset = 0.2 * direction if scenario == "head_offset" else 0.0
	reset_actor(a,mode,Vector3(offset,3.5,0) if head else Vector3(-3*direction,0.01,0))
	if scenario == "air_cross":
		reset_actor(a,mode,Vector3(-1.5*direction,8,0)); reset_actor(b,mode,Vector3(0,8,0))
	if scenario == "head_wall": block(world,Vector3(0.95,3,0),Vector3(0.2,6,6))
	if scenario == "pair_exception":
		a.add_collision_exception_with(b); b.add_collision_exception_with(a)
	if mode == "legacy":
		a.jumps_used = 2; a.recovery_spent = true
		if scenario == "knockback": a.velocity = Vector3(18*direction,0,0); a.hitstun = 2.0
	else:
		a.runtime.air_jumps_left = 0; a.runtime.recovery_spent = true
		if scenario == "knockback": a.apply_combat_launch(Vector3(18*direction,0,0),120)
	var trace: Array = []; var contacts = 0; var head_contacts = 0
	var crossed = false; var false_ground = false; var head_refund = false
	var max_target_displacement = 0.0; var max_z = 0.0
	for i in (150 if head else 75):
		var commands = {1:{},2:{}}
		if not head and scenario != "knockback": commands[mover] = {"move_x":direction}
		if scenario == "both_walk": commands[target] = {"move_x":-direction}
		await tick(actors,mode,order,commands)
		var normals: Array = []
		for j in a.get_slide_collision_count():
			var c = a.get_slide_collision(j)
			for k in c.get_collision_count():
				if c.get_collider(k) == b:
					contacts += 1; var n = c.get_normal(k); normals.append([n.x,n.y,n.z])
					if n.y > 0.7:
						head_contacts += 1
						false_ground = false_ground or grounded(a,mode)
						head_refund = head_refund or (a.jumps_used != 2 or not a.recovery_spent if mode == "legacy" else a.runtime.air_jumps_left != 0 or not a.runtime.recovery_spent)
		crossed = crossed or (not head and (a.position.x-b.position.x)*direction > 0.05)
		max_target_displacement = maxf(max_target_displacement,absf(b.position.x))
		max_z = maxf(max_z,maxf(absf(a.position.z),absf(b.position.z)))
		trace.append({"tick":i,"a":[a.position.x,a.position.y,a.position.z],"b":[b.position.x,b.position.y,b.position.z],"vx":a.velocity.x,"vy":a.velocity.y,"grounded":grounded(a,mode),"native_floor":a.is_on_floor(),"normals":normals})
	var r = {"mode":mode,"scenario":scenario,"mover":mover,"reverse":reverse,"direction":direction,"contacts":contacts,"head_contacts":head_contacts,"crossed":crossed,"false_head_ground":false_ground,"head_refund":head_refund,"final_a":trace[-1].a,"final_b":trace[-1].b,"final_grounded":grounded(a,mode),"max_target_dx":max_target_displacement,"max_z":max_z,"trace":trace}
	reports.append(r)
	print(JSON.stringify(r.duplicate().merged({"trace":[]},true)))
	world.free(); await process_frame
func run():
	Engine.physics_ticks_per_second = 60
	for scenario in ["walk","both_walk","air_cross","knockback","pair_exception","head_center","head_offset","head_wall"]:
		for mover in [1,2]:
			for reverse in [false,true]:
				for direction in [-1,1]: await run_case("core",scenario,mover,reverse,direction)
	for r in reports:
		var ok: bool
		if r.scenario == "pair_exception": ok = r.crossed and r.contacts == 0
		elif r.scenario.begins_with("head"):
			ok = r.head_contacts > 0 and not r.false_head_ground and not r.head_refund and r.final_grounded and absf(r.final_a[1]) < 0.03 and absf(r.final_a[0]-r.final_b[0]) >= 0.78
			if r.scenario == "head_center": ok = ok and r.final_a[0] > r.final_b[0]
			if r.scenario == "head_offset": ok = ok and r.final_a[0]*r.direction > 0
			if r.scenario == "head_wall": ok = ok and r.final_a[0] < r.final_b[0]
		else:
			ok = r.contacts > 0 and not r.crossed
			if r.scenario == "walk": ok = ok and r.max_target_dx < 0.02
		check(ok and r.max_z == 0, "%s/%s/%s/%s" % [r.scenario,r.mover,r.reverse,r.direction])
	FileAccess.open(OUT+"differential.json",FileAccess.WRITE).store_string(JSON.stringify(reports))
	if not failures: print("PASS body contact 64 cases")
	quit(1 if failures else 0)

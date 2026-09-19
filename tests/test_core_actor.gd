extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func tick(actor, commands: Dictionary = {}) -> void:
	await physics_frame
	actor.simulate(commands)
func floor_body(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	root.add_child(body)
	return body
func run() -> void:
	var path := "res://scripts/core/fighter/fighter_actor.gd"
	if not ResourceLoader.exists(path):
		check(false, "match-ticked CharacterBody3D actor exists")
	else:
		await test_actor(load(path))
	if failures == 0: print("PASS: core actor (%d checks)" % checks)
	quit(1 if failures else 0)
func test_actor(script) -> void:
	Engine.physics_ticks_per_second = 60
	var floor = floor_body(Vector3(0, -0.5, 0), Vector3(20, 1, 4))
	var a = script.new()
	root.add_child(a)
	a.reset_at(Vector3(0, 2, 0))
	var original: Vector3 = a.position
	for i in range(5): await physics_frame
	check(a.position == original and a.runtime.tick == 0, "actor has no independent physics ticking")
	for i in range(60): await tick(a)
	check(a.runtime.grounded and absf(a.position.y) < 0.03, "real floor supports capsule feet")
	check(a.collision_layer == 2 and a.collision_mask == 1 and a.is_in_group("core_fighters"), "fighter collision uses terrain only")
	check(a.can_accept_jump(), "settled actor can accept jump")
	await tick(a, {"move_x": 1.0})
	var moved: Vector3 = a.position
	var t: int = a.runtime.tick
	a.simulate({"move_x": 1.0})
	check(a.position == moved and a.runtime.tick == t, "duplicate same physics tick ignored")
	await tick(a, {"jump": true, "jump_held": true})
	check(a.telemetry().locomotion == "jump_startup", "actor publishes jump startup")
	for i in range(a.profile.jump_startup_ticks): await tick(a, {"jump_held": true})
	check(a.velocity.y > 0 and not a.telemetry().grounded, "physics jump leaves floor")
	var saw_fall := false
	var saw_land := false
	for i in range(90):
		await tick(a, {"jump_held": true})
		saw_fall = saw_fall or a.telemetry().locomotion == "falling"
		saw_land = saw_land or a.telemetry().locomotion == "landing"
	check(saw_fall and saw_land and a.runtime.grounded, "actual trajectory reconciles fall and landing")
	var telemetry: Dictionary = a.telemetry()
	for field in ["locomotion", "action", "status", "velocity", "grounded", "air_jumps_left", "transition_reason"]:
		check(telemetry.has(field), "telemetry contains " + field)
	var other = script.new()
	root.add_child(other)
	other.reset_at(Vector3(0, 0, 0))
	a.reset_at(Vector3(0, 4, 0))
	var stood_on_head := false
	for i in range(90):
		await tick(a)
		stood_on_head = stood_on_head or (a.runtime.grounded and a.position.y > 1)
	check(not stood_on_head and a.position.y < 0.03, "fighter head never grants floor support")
	var ceiling = floor_body(Vector3(4, 2.7, 0), Vector3(3, 0.3, 4))
	a.reset_at(Vector3(4, 0, 0))
	for i in range(10): await tick(a)
	await tick(a, {"jump": true, "jump_held": true})
	var hit_head := false
	for i in range(20):
		await tick(a, {"jump_held": true})
		if a.is_on_ceiling():
			hit_head = true
			check(not a.runtime.grounded, "ceiling is not ground")
	check(hit_head, "real capsule reaches solid ceiling")
	a.reset_at(Vector3(12, 3, 0))
	check(a.runtime.tick == 0 and a.velocity == Vector3.ZERO and not a.runtime.grounded, "reset clears body and runtime")
	for i in range(60): await tick(a)
	check(not a.runtime.grounded and a.position.y < -3, "gap produces unsupported fall")
	a.free()
	other.free()
	ceiling.free()
	floor.free()

extends SceneTree
## Same-build physics trace; invoke at --max-fps 30 and 144, compare TRACE lines.
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	Engine.physics_ticks_per_second = 60
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 4)
	collider.shape = box
	floor.position.y = -0.5
	floor.add_child(collider)
	root.add_child(floor)
	var script = load("res://scripts/core/fighter/fighter_actor.gd")
	var a = script.new()
	root.add_child(a)
	var traces: Array = []
	var apexes: Array = []
	for playback in range(2):
		a.reset_at(Vector3.ZERO)
		var trace: Array = []
		var apex := 0.0
		for t in range(180):
			await physics_frame
			var commands := {"move_x": 0.4 if t < 80 else -0.7, "jump_held": t >= 12 and t < 50, "jump": t == 12 or t == 65, "jump_released": t == 50, "down": t == 100}
			a.simulate(commands)
			apex = maxf(apex, a.position.y)
			trace.append([a.position.x, a.position.y, a.velocity.x, a.velocity.y, a.runtime.states.locomotion, a.runtime.states.action, a.runtime.air_jumps_left])
		traces.append(trace)
		apexes.append(apex)
	if traces[0] != traces[1]:
		failures += 1
		printerr("FAIL: reset replay produces identical same-build physics trace")
	if apexes[0] < 2.0:
		failures += 1
		printerr("FAIL: replay exercises actual jumping")
	print("TRACE: ", JSON.stringify(traces[0]).sha256_text())
	print("MEASURED full-jump replay apex: ", apexes[0])
	a.free()
	floor.free()
	if failures == 0: print("PASS: core actor replay (2 checks)")
	quit(1 if failures else 0)

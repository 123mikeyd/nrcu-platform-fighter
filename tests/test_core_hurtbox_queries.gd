extends SceneTree
var checks := 0
var failures := 0
var q: GDScript
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)
func cap(id: String = "torso") -> Dictionary:
	return {"id": id, "a": Vector3(0, -1, 0), "b": Vector3(0, 1, 0), "radius": 0.5}
func _initialize() -> void:
	if not FileAccess.file_exists("res://scripts/core/collision/hurtbox_queries.gd"):
		check(false, "hurtbox query module exists")
	else:
		q = load("res://scripts/core/collision/hurtbox_queries.gd")
		run()
	print("%s: hurtbox queries: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
func run() -> void:
	check(q.has_method("sphere_overlap"), "sphere_overlap API exists")
	if not q.has_method("sphere_overlap"): return
	check(q.sphere_overlap(Vector3(1, 0, 0), 0.5, cap()), "inclusive middle tangent")
	check(not q.sphere_overlap(Vector3(1.001, 0, 0), 0.5, cap()), "middle near miss")
	check(q.sphere_overlap(Vector3(0, 2, 0), 0.5, cap()), "inclusive cap tangent")
	check(q.sphere_overlap(Vector3.ZERO, 0.0, cap()), "point sphere inside")
	var ball := cap(); ball.b = ball.a
	check(q.sphere_overlap(Vector3(0, -2, 0), 0.5, ball), "zero segment sphere")
	for bad in [{}, {"id": "x", "a": Vector3.ZERO, "b": Vector3.ONE, "radius": -1}, {"id": "x", "a": Vector3(INF, 0, 0), "b": Vector3.ONE, "radius": 1}]:
		check(not q.sphere_overlap(Vector3.ZERO, 1.0, bad), "invalid capsule fails closed")
	check(not q.sphere_overlap(Vector3.ZERO, -1.0, cap()), "negative sphere fails closed")
	check(not q.sphere_overlap(Vector3(NAN, 0, 0), 0.0, cap()), "nonfinite sphere fails closed")
	var wide := {"id": "finite-wide", "a": Vector3(-3e38, 0, 0), "b": Vector3(3e38, 0, 0), "radius": 1.0}
	check(q.sphere_overlap(Vector3.ZERO, 0.0, wide), "finite endpoints must not overflow Vector3 subtraction")
	check(q.sweep_sphere(Vector3.ZERO, Vector3.ONE, 0.0, wide).get("t", -1) == 0.0, "extreme finite initial overlap")

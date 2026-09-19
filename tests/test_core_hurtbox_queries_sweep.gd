extends "res://tests/test_core_hurtbox_queries.gd"
func hit(start: Vector3, finish: Vector3, radius: float, c: Dictionary, t: float, label: String) -> void:
	var result: Dictionary = q.sweep_sphere(start, finish, radius, c, "attack-7", "victim-2")
	check(not result.is_empty(), label + " hit")
	if not result.is_empty():
		check(absf(result.t - t) < 0.000002, label + " earliest t")
		check(result.source_id == "attack-7" and result.victim_id == "victim-2" and result.hurtbox_id == c.id, label + " identity")
func run() -> void:
	check(q.has_method("sweep_sphere"), "sweep_sphere API exists")
	if not q.has_method("sweep_sphere"): return
	hit(Vector3(-10, 0, 0), Vector3(10, 0, 0), 0.5, cap(), 0.45, "whole body crossing")
	hit(Vector3(-100000, 0, 0), Vector3(100000, 0, 0), 0.0, cap(), 0.4999975, "fast thin crossing")
	hit(Vector3(0, 4, 0), Vector3(0, -4, 0), 0.5, cap(), 0.25, "endpoint before cylinder")
	hit(Vector3(-2, 2, 0), Vector3(2, 2, 0), 0.5, cap(), 0.5, "cap grazing")
	hit(Vector3(-2, 0, 1), Vector3(2, 0, 1), 0.5, cap(), 0.5, "cylinder grazing")
	hit(Vector3(-2, 0, 0), Vector3(-1, 0, 0), 0.5, cap(), 1.0, "last endpoint tangent")
	hit(Vector3.ZERO, Vector3(5, 0, 0), 0.0, cap(), 0.0, "initial overlap")
	hit(Vector3(1, 0, 0), Vector3(1, 0, 0), 0.5, cap(), 0.0, "stationary tangent")
	var ball := cap(); ball.a = Vector3.ZERO; ball.b = Vector3.ZERO
	hit(Vector3(-2, 0, 0), Vector3(2, 0, 0), 0.0, ball, 0.375, "degenerate capsule")
	for ends in [[Vector3(-2, 2.001, 0), Vector3(2, 2.001, 0)], [Vector3(-2, 0, 1.001), Vector3(2, 0, 1.001)], [Vector3(2, 0, 0), Vector3(2, 0, 0)], [Vector3(2, 0, 0), Vector3(3, 0, 0)]]:
		check(q.sweep_sphere(ends[0], ends[1], 0.5, cap()).is_empty(), "near miss / zero motion / away")
	for c in [{}, {"id": "zero", "a": Vector3.ZERO, "b": Vector3.ZERO, "radius": 0.0}]:
		check(q.sweep_sphere(Vector3.ZERO, Vector3.ONE, 0.0, c).is_empty(), "invalid capsule")
	check(q.sweep_sphere(Vector3.ZERO, Vector3(INF, 0, 0), 1, cap()).is_empty(), "nonfinite end")
	check(q.sweep_sphere(Vector3.ZERO, Vector3.ONE, NAN, cap()).is_empty(), "nonfinite radius")

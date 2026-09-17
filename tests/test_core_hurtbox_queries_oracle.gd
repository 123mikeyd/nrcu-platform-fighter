extends "res://tests/test_core_hurtbox_queries.gd"
# Supplemental oracle: direct sampled point-to-segment distance, never query code.
func sampled_inside(p: Vector3, r: float, c: Dictionary) -> bool:
	var axis: Vector3 = c.b - c.a
	var along := 0.0
	if axis.length_squared() > 0:
		along = clampf((p - c.a).dot(axis) / axis.length_squared(), 0, 1)
	return p.distance_squared_to(c.a + axis * along) <= (r + c.radius) * (r + c.radius)
func run() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 491871
	var hit_count := 0; var miss_count := 0
	for index in 80:
		var c := cap("oracle")
		c.a = Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		c.b = c.a + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		c.radius = rng.randf_range(0.15, 0.7)
		var start := Vector3(-5, rng.randf_range(-3, 3), rng.randf_range(-2, 2))
		var finish := Vector3(5, rng.randf_range(-3, 3), rng.randf_range(-2, 2))
		var radius := 0.2
		var actual: Dictionary = q.sweep_sphere(start, finish, radius, c)
		var sampled_t := INF
		for step in 10001:
			var t := float(step) / 10000
			if sampled_inside(start.lerp(finish, t), radius, c):
				sampled_t = t
				break
		if is_finite(sampled_t):
			hit_count += 1
			check(not actual.is_empty(), "oracle sampled hit %d" % index)
			if not actual.is_empty(): check(actual.t <= sampled_t + 0.000002 and sampled_t - actual.t <= 0.000102, "oracle earliest within one sample %d" % index)
		else:
			miss_count += 1
			check(actual.is_empty(), "oracle sampled miss %d (not a general proof)" % index)
	check(hit_count > 5 and miss_count > 5, "oracle exercised both hit and miss")
	print("oracle: %d hits, %d misses; 10001 samples per full path" % [hit_count, miss_count])

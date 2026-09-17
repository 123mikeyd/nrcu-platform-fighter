extends SceneTree
const Kit = preload("res://scripts/core/kits/turbofit_kit.gd")
const Pose = preload("res://scripts/core/kits/turbofit_contact_pose.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var pose = Pose.new()
	for down in [false, true]:
		var clip := "AirDownKick" if down else "AirSideKick"
		var first := 0.4 if down else 5.0 / 30.0
		var last := 0.5 if down else 0.2
		var duration := 38.0 / 30.0 if down else 0.5
		for facing in [-1.0, 1.0]:
			for time in [first - 0.001, first, (first + last) / 2, last, last + 0.001]:
				var kit = Kit.new()
				check(kit.start("air:1", Vector2(facing, 1 if down else 0), true, -facing), "air route " + clip)
				kit.tick(time)
				var center: Vector3 = Vector3(0, 3, 0) + pose.center(clip, time, facing)
				var body := {"id": 2, "position": center - Vector3(0, 1.6 if down else 0.9, 0), "capsules": [{"transform": Transform3D(Basis.IDENTITY, center), "radius": 0.55, "height": 1.8}]}
				var hits: Array = kit.contacts(1, Vector3(0, 3, 0), [body])
				var active: bool = time >= first and time <= last
				check(hits.size() == (1 if active else 0), "%s contact boundary %s" % [clip, time])
				if not hits.is_empty():
					check(hits[0].damage == 14 and hits[0].base_knockback == 5.5, "air preserves damage")
					check(hits[0].direction == Vector3.DOWN if down else hits[0].direction.x == facing, "air launch")
				check(kit.contacts(1, Vector3(0, 3, 0), [body]).is_empty(), "dedup")
				check(is_equal_approx(kit.snapshot().duration, duration), "full source recovery duration")
				kit.tick(duration - time)
				check(not kit.snapshot().active, "source duration ends episode")
	# Real CharacterBody/terrain, not a feet-only mocked hurtbody.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var body := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	body.add_child(collider)
	root.add_child(body)
	body.position = Vector3(1.2, 0.05, 0)
	await physics_frame
	body.velocity = Vector3(0, -6, 0)
	body.move_and_slide()
	check(body.is_on_floor(), "actual terrain collision")
	var kit = Kit.new()
	kit.start("physics:1", Vector2.RIGHT, true, 1)
	kit.tick(5.0 / 30.0)
	var center: Vector3 = pose.center("AirSideKick", 5.0 / 30.0, 1)
	var origin := collider.global_position - center
	var targets := [{"id": 2, "position": body.global_position, "capsules": [{"transform": collider.global_transform, "radius": capsule.radius, "height": capsule.height}]}]
	var hits: Array = kit.contacts(1, origin, targets)
	check(hits.size() == 1, "real physics hurt capsule overlaps authored kick")
	check(body.velocity.y <= 0 and is_equal_approx(body.position.x, 1.2), "candidate emission never moves victim")
	var resolver = load("res://scripts/core/combat/combat_resolver.gd").new()
	var resolved: Array = resolver.resolve(hits, {2: 0.0})
	check(resolved.size() == 1 and resolved[0].percent == 14, "existing resolver accepts candidate contract")
	kit.tick(0, {"grounded": body.is_on_floor()})
	check(not kit.snapshot().active and kit.contacts(1, origin, targets).is_empty(), "real landing cancels before post-move contacts")
	body.free()
	floor_body.free()
	if failures == 0: print("PASS: core Turbofit air windows, both facings, capsule/terrain and resolver")
	quit(1 if failures else 0)

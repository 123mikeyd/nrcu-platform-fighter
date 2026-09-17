extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + message)
func _init() -> void:
	var path := "res://scripts/core/collision/character_collision_profile.gd"
	check(ResourceLoader.exists(path), "authorable collision profile exists")
	if ResourceLoader.exists(path):
		var p = load(path).new()
		check(not p.validate().is_empty(), "empty definition invalid")
		p.character_id = "fixture"
		p.body_radius = 0.3; p.body_height = 2.0; p.body_center = Vector3(0, 1, 0)
		check(p.validate().is_empty(), "positive grounded capsule valid")
		var a = p.instantiate_body(); var b = p.instantiate_body()
		a.shape.radius = 0.4
		check(is_equal_approx(b.shape.radius, 0.3) and p.body_radius == 0.3, "independent shape instances")
		a.free(); b.free()
		p.body_radius = NAN
		check(not p.validate().is_empty(), "nonfinite rejected")
		var h = load("res://scripts/core/collision/generated_hurtbox.gd").new()
		h.bone_name = "Head"; h.hurtbox_id = "head"; h.radius = 0.2; h.height = 0.4
		check(h.validate().is_empty(), "named bone capsule valid")
		var c = h.instantiate_shape(); c.shape.radius = 0.1
		check(h.radius == 0.2, "hurtbox definition not mutated")
		h.radius = 0.00000001; h.height = -0.00000001
		check(not h.validate().is_empty(), "negative tiny dimensions cannot pass roundtrip tolerance")
		p.body_radius = 0.00000001; p.body_height = -0.00000001
		check(not p.validate().is_empty(), "body height strictly positive even near zero")
		c.free()
	if failures == 0: print("PASS: core collision generator schema")
	quit(1 if failures else 0)

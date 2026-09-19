extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + text)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var p = load("res://scripts/core/collision/character_collision_profile.gd").new()
	p.character_id = "fixture"; p.body_radius = 0.3; p.body_height = 2.0; p.body_center = Vector3(0,1,0)
	ResourceSaver.save(p, "user://collision_authoring_fixture.tres")
	var path := "res://scenes/collision_authoring_lab.tscn"
	check(ResourceLoader.exists(path), "standalone authoring scene exists")
	if ResourceLoader.exists(path):
		var lab = load(path).instantiate(); root.add_child(lab)
		check(lab.open_profile("user://collision_authoring_fixture.tres"), "opens valid real resource path")
		check(lab.working.body_radius == 0.3, "uses profile radius")
		check(lab.body_wire.position == p.body_center, "body preview uses declared center")
		check(lab.body_wire.get_meta("radius") == p.body_radius, "wire geometry radius is declared radius")
		check(lab.find_child("ProfilePath", true, false) != null, "visible path entry")
		lab.free()
	print("PASS collision authoring load" if failures == 0 else "FAILED collision authoring load")
	quit(1 if failures else 0)

extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	lab.open_profile("res://data/collision/generated/teknium.tres")
	var before: float = lab.working.body_radius
	var bad = lab.generated.duplicate(true); bad.manual_override = true; bad.body_radius = 10; bad.body_height = 20; bad.override_fields = PackedStringArray(["body_radius"])
	ResourceSaver.save(bad,"user://collision_authoring_badmerge.tres")
	check(not lab.reload_override("user://collision_authoring_badmerge.tres"),"merged capsule validated atomically")
	check(lab.working.body_radius == before,"bad merge preserves working copy")
	check(not lab.open_profile("user://collision_authoring_badmerge.tres"),"override cannot become generated baseline")
	lab.open_profile("res://data/collision/generated/teknium.tres")
	var bounds: AABB = lab.body_wire.mesh.get_aabb()
	check(is_equal_approx(bounds.size.x, lab.working.body_radius*2) and is_equal_approx(bounds.size.y,lab.working.body_height),"actual wire bounds equal profile capsule dimensions")
	check(lab.find_child("ProfileMetadata",true,false) != null,"persistent warnings and provenance distinct from operation status")
	lab.free()
	print("PASS collision authoring safety" if not failures else "FAILED collision authoring safety")
	quit(1 if failures else 0)

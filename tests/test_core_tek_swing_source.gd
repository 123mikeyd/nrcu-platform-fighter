extends SceneTree
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1; print("FAIL: ",label)
func _initialize():
	check(ResourceLoader.exists("res://data/animation/teknium_swing_v1.tres"),"versioned authored swinging punch library exists")
	if not failures: print("PASS: Tek swing source")
	quit(1 if failures else 0)

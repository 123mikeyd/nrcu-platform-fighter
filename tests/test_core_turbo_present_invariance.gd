extends SceneTree
## Characterization: gameplay module is unchanged, not a manufactured RED.
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ",label)
func _init() -> void: call_deferred("run")
func trace(mode: String) -> Array:
	var result: Array = []
	var kit = load("res://scripts/core/kits/turbofit_kit.gd").new()
	var v = load("res://scripts/core/presentation/turbofit_presenter.gd").new()
	root.add_child(v)
	v.visible = mode != "hidden"
	var tick := 0
	for route in [[Vector2.RIGHT,false],[Vector2.UP,false],[Vector2.DOWN,false],[Vector2.RIGHT,true],[Vector2.UP,true],[Vector2.DOWN,true]]:
		kit.cancel()
		kit.start(str(route),route[0],route[1],1)
		for step in 90:
			var stopped: bool = step in [8,9,10]
			var snapshot: Dictionary = kit.tick(1.0/60,{"paused":stopped})
			var before := var_to_str(snapshot)
			if is_instance_valid(v):
				v.present({"presentation":snapshot.presentation,"stopped":stopped,"grounded":not route[1]},tick)
				if mode == "removed" and tick == 12: v.free()
			check(before == var_to_str(snapshot),"presentation never mutates committed snapshot")
			if route[0] == Vector2.RIGHT and not route[1] and step == 25 and is_instance_valid(v):
				check(snapshot.duration != 0.8,"gameplay cooldown actually replaced")
				check(is_equal_approx(v.output.seconds, snapshot.elapsed/0.8*v.animation_player.get_animation("MeleeHorizontal").length),"guitar uses .8 presentation not replaced duration")
			var targets := [{"id":2,"position":Vector3(1,0,0),"capsules":[{"transform":Transform3D(Basis.IDENTITY,Vector3(1,1,0)),"radius":0.4,"height":2.0}]}]
			result.append([snapshot,kit.contacts(1,Vector3.ZERO,targets)])
			tick += 1
	if is_instance_valid(v): v.free()
	return result
func run() -> void:
	var visible := trace("visible")
	check(trace("hidden") == visible,"hidden presenter identical complete gameplay module trace")
	check(trace("removed") == visible,"deleted presenter identical complete gameplay module trace")
	if not failures: print("PASS: core turbo presenter visible hidden removed gameplay trace and guitar independent clock")
	quit(1 if failures else 0)

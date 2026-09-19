extends "res://tests/test_core_recovery_acceptance.gd"
## Characterization of unchanged real match, not a claimed missing-feature RED.
func trace(mode: String) -> Array:
	var m = Match.new()
	var a = Actor.new()
	var b = Actor.new()
	root.add_child(a)
	root.add_child(b)
	m.register_actor(1,a,-1,"ice_mage")
	m.register_actor(2,b,-1,"ice_mage")
	m.reset({1:Vector3(0,80,0),2:Vector3(1.5,80,0)})
	var v = load("res://scripts/core/presentation/ice_mage_presenter.gd").new()
	root.add_child(v)
	v.visible = mode != "hidden"
	var result: Array = []
	for i in 130:
		var frames := {}
		if i == 0: frames[1] = press(Vector2.RIGHT,"attack")
		if i == 40: frames[1] = press(Vector2.RIGHT)
		if i == 90: frames[1] = press(Vector2.UP)
		await step(m,frames)
		var kit: Dictionary = m.kit_telemetry(1)
		var snap := {"presentation":kit.presentation,"status":a.runtime.states.status,"grounded":a.runtime.grounded,"velocity":a.runtime.velocity,"facing":m.fighters[1].facing}
		var before := var_to_str(snap)
		if is_instance_valid(v):
			v.present(snap,a.runtime.tick)
			if mode == "removed" and i == 12: v.free()
		check(var_to_str(snap)==before,"detached snapshot is never mutated")
		result.append([kit,m.kit_telemetry(2),m.status_telemetry(1),m.status_telemetry(2),m.projectile_telemetry(),m.events.duplicate(true),a.position,b.position,a.runtime.velocity,b.runtime.velocity,a.runtime.tick,b.runtime.tick,m.fighters[1].percent,m.fighters[2].percent])
	check(m.fighters[2].percent >= 8,"trace actually resolves source strike")
	if is_instance_valid(v): v.free()
	a.free()
	b.free()
	return result
func run() -> void:
	var visible_trace := await trace("visible")
	check(await trace("hidden") == visible_trace,"hidden presenter exactly equal real duplicate Ice match trace")
	check(await trace("removed") == visible_trace,"deleted presenter exactly equal real duplicate Ice match trace")
	if not failures: print("PASS: Ice presentation real match trace visible hidden deleted and input immutability")
	quit(1 if failures else 0)

extends SceneTree
const Specials = preload("res://scripts/core/kits/turbofit_specials.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var kit = Specials.new()
	if not kit.start("orb:1", Vector2.DOWN, -1):
		check(false, "Sound Orb starts caller-owned radial utility")
		quit(1); return
	var host := Node3D.new(); root.add_child(host)
	host.position = Vector3.ZERO # Avoid translated float32 rounding at exact radius.
	var targets: Array = []
	for entry in [[9,Vector3(1.15,0,0)], [2,Vector3.ZERO], [4,Vector3(1.151,0,0)], [5,Vector3(0,.8,.8)]]:
		var body := CharacterBody3D.new(); root.add_child(body); body.position = host.position + entry[1]
		var shape := CollisionShape3D.new(); shape.shape = CapsuleShape3D.new(); body.add_child(shape)
		targets.append({"id":entry[0], "position":body.global_position, "body":body})
	var shot := Node3D.new(); root.add_child(shot); shot.position = host.position + Vector3(0,1,1.15)
	var projectiles := [{"id":"ally-shot", "owner":7, "team":1, "reflectable":true, "position":shot.global_position}, {"id":"self-shot", "owner":1, "reflectable":true, "position":shot.global_position}]
	await physics_frame
	var effects: Array = kit.collect(1,host.global_position,targets,projectiles)
	check(effects.size() == 4, "real node origins: inclusive radius pushes three and reflects nonself ally")
	if effects.size() == 4:
		check(effects[0].victim == 2 and effects[1].victim == 5 and effects[2].victim == 9, "stable target ordering")
		check(effects[0].direction.is_equal_approx(Vector3(-1,.25,0).normalized()), "coincident fallback")
		check(effects[1].direction.is_equal_approx(Vector3(0,.8,.8).normalized()), "3D radial push")
		for i in 3: check(effects[i].damage == 0 and effects[i].base_knockback == 7, "zero damage is a hit intent")
		check(effects[3].kind == "reflect" and effects[3].projectile_id == "ally-shot", "reflection intent")
	check(kit.collect(1,host.position,targets,projectiles).is_empty(), "once per target and projectile despite uncommitted ownership")
	check(targets[0].body.velocity == Vector3.ZERO, "core did not mutate body")
	var duplicate = Specials.new(); duplicate.start("orb:2",Vector2.DOWN,1)
	check(duplicate.collect(1,host.position,targets,projectiles).size() == 4, "independent ledgers")
	var before: Dictionary = kit.snapshot()
	kit.tick(.3,{"advance":false})
	check(kit.snapshot() == before and kit.collect(1,host.position,[{"id":22,"position":host.position}]).is_empty(), "paused no contacts or clock")
	kit.tick(.549)
	check(kit.collect(1,host.position,[{"id":22,"position":host.position}]).size() == 1, "active before .55")
	kit.tick(.001)
	check(kit.collect(1,host.position,[{"id":23,"position":host.position}]).is_empty(), "expired at .55")
	check(is_equal_approx(kit.snapshot().cooldown,.2), "orb expiry retains cooldown")
	kit.tick(.2)
	check(kit.snapshot().phase == "idle", "cooldown completes at .75")
	for reason in ["hit","freeze","grab","disabled","reset","stock","result","exit"]:
		kit.cancel() # Independent lifecycle scenario, not a cooldown-refund assertion.
		check(kit.start("orb:"+reason,Vector2.DOWN,1), "fresh orb lifecycle scenario")
		kit.tick(0,{"interrupted":true,"advance":false,"reason":reason})
		check(kit.snapshot().activation_id == "" and kit.collect(1,host.position,targets,projectiles).is_empty(), "synchronous interruption: "+reason)
	for target in targets: target.body.free()
	host.free(); shot.free()
	if failures == 0: print("PASS core Turbofit Sound Orb geometry lifecycle")
	quit(1 if failures else 0)

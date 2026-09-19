extends "res://tests/test_core_match_strikes.gd"
const LedgePolicy = preload("res://scripts/core/stage/ledge_policy.gd")
const Anchor = preload("res://scripts/core/stage/ledge_anchor.gd")
func body(at: Vector3, size: Vector3):
	var b = StaticBody3D.new(); var c = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = size; c.shape = box; b.add_child(c); b.position = at; root.add_child(b); return b
func setup_ledge(policy = null):
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b)
	m.reset({1:Vector3(-1,-1,0),2:Vector3(8,3,0)})
	var anchor = Anchor.new(); anchor.anchor_id = "left"
	if m.has_method("configure_ledges"): m.configure_ledges([anchor], policy if policy != null else LedgePolicy.new())
	return m
func cleanup(m):
	for f in m.fighters.values(): f.actor.free()
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0), Vector3(4,1,4))
	var m = setup_ledge()
	check(m.has_method("configure_ledges"), "explicit opt-in ledge API")
	if not m.has_method("configure_ledges"): cleanup(m); terrain.free(); quit(1); return
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left", "real actor catches authored terrain ledge")
	check(m.fighters[1].actor.position.is_equal_approx(Vector3(-0.65,-1.5,0)), "validated catch moves capsule to hang")
	var at = m.fighters[1].actor.position
	for i in 3: await tick(m)
	check(m.fighters[1].actor.position == at and m.fighters[1].actor.velocity == Vector3.ZERO, "hang owns motion with no normal gravity")
	check(m.ledge_telemetry(1).protected, "finite catch protection exposed")
	cleanup(m); terrain.free()
	if not failures: print("PASS: core ledge match (%d checks)" % checks)
	quit(1 if failures else 0)

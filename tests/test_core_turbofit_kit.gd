extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var path := "res://scripts/core/kits/turbofit_kit.gd"
	check(ResourceLoader.exists(path), "caller-ticked Turbofit kit exists")
	if failures:
		quit(1)
		return
	var kit = load(path).new()
	check(kit.start("1:1", Vector2.DOWN, false, -1), "ground down accepted")
	check(kit.snapshot().clip == "GoalkeeperKick", "real ground down clip")
	check(not kit.start("1:2", Vector2.DOWN, false, 1), "committed episode cannot restart")
	kit.tick(0.45 - 0.001)
	check(kit.contacts(1, Vector3.ZERO, [{"id": 2, "position": Vector3(-1, 0, 0)}]).is_empty(), "no startup contact")
	kit.tick(0.001)
	var hits: Array = kit.contacts(1, Vector3.ZERO, [{"id": 2, "position": Vector3(-1, 0, 0)}])
	check(hits.size() == 1, "impact at authored .45 seconds")
	if not hits.is_empty():
		check(hits[0].damage == 14 and hits[0].base_knockback == 5.5 and hits[0].activation_id == "1:1", "source damage and caller activation")
		check(hits[0].direction.x < 0 and is_equal_approx(hits[0].direction.y, 0.35), "latched low sweep launch")
	check(kit.contacts(1, Vector3.ZERO, [{"id": 2, "position": Vector3(-1, 0, 0)}]).is_empty(), "one victim once")
	kit.tick(1.0 / 60.0)
	check(kit.contacts(1, Vector3.ZERO, [{"id": 3, "position": Vector3(-1, 0, 0)}]).is_empty(), "ground impact is one tick not recovery volume")
	kit.tick(59.0 / 60.0 - 0.45 - 1.0 / 60.0)
	check(not kit.snapshot().active, "exact source duration and cleanup")
	if failures == 0: print("PASS: core Turbofit GoalkeeperKick tracer")
	quit(1 if failures else 0)

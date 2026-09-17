extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ",label)
func _initialize() -> void:
	var path := "res://scripts/core/kits/turbofit_wave.gd"
	if not ResourceLoader.exists(path):
		check(false,"finite caller-ticked Sound Wave module missing"); quit(1); return
	var wave = load(path).new(); var other = load(path).new()
	check(wave.start("wave:1",1,0,Vector3(.8,1,0),1), "caller wave identity")
	other.start("wave:2",1,0,Vector3(.8,1,0),1)
	wave.tick(.45)
	var s: Dictionary = wave.snapshot()
	check(is_equal_approx(s.age,.45) and is_equal_approx(s.speed,5.4) and is_equal_approx(s.radius,.65), "midlife speed and growth")
	check(is_equal_approx(s.distance,3.24) and is_equal_approx(s.position.x,4.04), "trapezoidal travel")
	wave.tick(99,{"advance":false})
	check(wave.snapshot() == s, "wave no-advance freezes finite clocks")
	check(wave.reflect(2,1), "reflect live wave")
	var r: Dictionary = wave.snapshot()
	check(r.source == 2 and r.team == 1 and r.facing == -1 and r.activation_id == "wave:1", "transfer keeps stable identity")
	for key in ["age","speed","radius","distance","opacity","remaining","position"]: check(r[key] == s[key], "reflection preserves "+key)
	check(other.snapshot().age == 0 and other.snapshot().facing == 1, "duplicate clocks independent")
	wave.tick(.2)
	check(not wave.snapshot().damage_active and is_equal_approx(wave.snapshot().opacity,.8), "fade starts harmless at .65")
	wave.tick(10)
	s = wave.snapshot()
	check(not s.active and is_equal_approx(s.age,.9) and is_equal_approx(s.distance,4.86), "bounded TTL and cumulative path after reflection")
	check(is_equal_approx(s.radius,.85) and is_equal_approx(s.speed,1.8) and s.opacity == 0, "finite endpoints")
	check(not wave.reflect(1,0) and wave.tick(1).is_empty(), "expired wave cannot reflect or act")
	other.tick(.1,{"interrupted":true})
	check(other.snapshot().active, "ordinary source hit does not cancel emitted wave")
	other.tick(0,{"owner_enabled":false,"advance":false})
	check(not other.snapshot().active, "disabled source cleanup precedes clock freeze")
	var reset = load(path).new(); reset.start("wave:3",1,0,Vector3.ZERO,1)
	reset.cancel()
	check(not reset.snapshot().active and reset.tick(.1).is_empty(), "idempotent external lifecycle cancel")
	if failures == 0: print("PASS core Turbofit wave finite clocks reflection lifecycle")
	quit(1 if failures else 0)

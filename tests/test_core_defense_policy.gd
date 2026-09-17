extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var path := "res://scripts/core/combat/defense_policy.gd"
	if not ResourceLoader.exists(path):
		check(false, "finite defense policy exists")
	else:
		var p = load("res://scripts/core/combat/defense_profile.gd").new()
		p.shield_max = 10.0
		p.shield_drain = 2.0
		p.break_ticks = 3
		var d = load(path).new(p)
		check(d.snapshot().shield_health == 10.0, "starts full")
		var out = d.advance({"shield_held": true, "grounded": true})
		check(out.state == "shield" and out.shield_health == 8.0, "held drain on committed tick")
		check(not out.damage_eligible and out.grab_eligible, "shield blocks damage but permits grabs")
		out = d.on_shield_hit(1000000.0)
		check(out.state == "break" and out.shield_health == 0.0 and out.damage_eligible, "arbitrary damage breaks without negative health")
		for i in range(2):
			check(d.advance({"shield_held": true}).state == "break", "break stays through penultimate tick")
		check(d.advance({}).state == "idle", "break endpoint recovers")
		if p.get("shield_regen") == null:
			check(false, "profile supports finite regen")
			quit(1)
			return
		p.shield_regen = 1.0
		p.regen_delay_ticks = 2
		p.break_restore_fraction = 0.5
		d = load(path).new(p)
		d.advance({"shield_held": true})
		check(d.advance({}).shield_health == 8.0, "release delay first tick")
		check(d.advance({}).shield_health == 8.0, "release delay endpoint")
		check(d.advance({}).shield_health == 9.0, "regeneration begins after delay")
		check(d.advance({}).shield_health == 10.0 and d.advance({}).shield_health == 10.0, "regen caps")
		d.advance({"shield_held": true})
		check(d.advance({"shield_held": true}).shield_health == 6.0, "holding never regens")
		d.on_shield_hit(1000.0)
		for i in range(3): d.advance({})
		check(d.snapshot().shield_health == 5.0, "break restores explicit fraction only at endpoint")
	if failures == 0: print("PASS: core defense policy (%d checks)" % checks)
	quit(1 if failures else 0)

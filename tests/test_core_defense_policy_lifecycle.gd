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
	var Policy = load("res://scripts/core/combat/defense_policy.gd")
	var p = load("res://scripts/core/combat/defense_profile.gd").new()
	var d = Policy.new(p)
	if not d.has_method("interrupt"):
		check(false, "interrupt and lifecycle API exists")
		quit(1)
		return
	p.air_startup_ticks = 1
	d = Policy.new(p)
	d.advance({"grounded": false, "dodge_requested": true, "dodge_direction": Vector2.UP})
	d.advance({"grounded": false})
	var before = d.snapshot()
	for gate in ["paused", "hitstop", "uncommitted"]:
		check(d.advance({gate: true, "grounded": true}) == before, "no progression or landing during " + gate)
	for gate in ["disabled", "frozen"]:
		var blocked = Policy.new(p)
		blocked.advance({"grounded": false, "dodge_requested": true})
		blocked.advance({"grounded": false})
		var out = blocked.advance({gate: true, "shield_held": true})
		check(out.state == "idle" and out.damage_eligible and out.motion_velocity == Vector2.ZERO, gate + " removes defensive episode")
		var stopped = blocked.snapshot()
		check(blocked.advance({gate: true}) == stopped, gate + " holds clocks and resources")
	var out = d.interrupt("hit")
	check(out.damage_eligible and out.grab_eligible and out.air_charges == 0 and out.motion_velocity == Vector2.ZERO, "hit clears invulnerability without refund")
	check(out.cooldown_ticks > 0, "interrupt retains cooldown penalty")
	d.reset(false)
	out = d.snapshot()
	check(out.state == "idle" and out.shield_health == p.shield_max and out.air_charges == 1 and out.cooldown_ticks == 0 and not out.grounded, "stock reset clears all episode state")
	d.advance({"grounded": false, "dodge_requested": true})
	d.advance({"grounded": false})
	out = d.advance({"grounded": true})
	check(out.state == "dodge_recovery" and out.damage_eligible and out.air_charges == 1, "landing cancels active air invulnerability into recovery")
	var a = Policy.new(p)
	var b = Policy.new(p)
	p.shield_max = 1.0
	a.advance({"shield_held": true})
	check(b.snapshot().shield_health == 100.0 and a.profile.shield_max == 100.0, "instances and source profile isolated")
	a.on_shield_hit(100000.0)
	var broken = a.snapshot()
	check(a.interrupt("grab").state == "break", "interrupt cannot bypass shield break")
	check(a.advance({"frozen": true}).remaining_ticks == broken.remaining_ticks, "freeze holds break recovery")
	p.policy_id = "legacy"
	var legacy = Policy.new(p)
	out = legacy.advance({"shield_held": true, "dodge_requested": true})
	check(out.delegate_legacy and out.state == "idle" and out.damage_eligible, "legacy selector delegates unchanged route, not finite policy")
	if failures == 0: print("PASS: core defense lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)

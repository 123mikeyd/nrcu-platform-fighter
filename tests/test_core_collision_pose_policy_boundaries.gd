extends "res://tests/test_core_collision_pose_policy.gd"
func run() -> void:
	var policy = load(POLICY).new(); var m := metadata("teknium"); policy.configure(m)
	var c := context(); c.locomotion = "landing"
	var landed: Dictionary = policy.sample(c,0)
	c.status = "frozen"; c.locomotion = "idle"
	check(policy.sample(c,30) == landed,"freeze preserves landing grace and full pose across lower transition")
	c.status = "normal"
	check(policy.sample(c,31).clip == "Jump","thaw still has landing grace")
	check(policy.sample(c,37).clip == "Idle","grace expires on actor ticks only")
	policy.reset(); c = context(); c.strike_id = "one"; c.strike_move = "SIDE STRIKE"
	policy.sample(c,0); var first: Dictionary = policy.sample(c,6)
	c.strike_id = "two"
	var second: Dictionary = policy.sample(c,6)
	check(second.source_seconds == 0 and second.episode_id != first.episode_id,"same clip strike restarts on unchanged tick")
	policy.reset(); c = context(); c.status = "hitstun"; c.hit_id = "hit"
	policy.sample(c,0); var hit: Dictionary = policy.sample(c,6)
	c.locomotion = "rising"; c.air_jumps_left = 0; c.hitstop = true
	check(policy.sample(c,6) == hit,"hitstop lower motion cannot reset Hit")
	c.hit_id = "new"
	check(policy.sample(c,6).source_seconds == 0,"new Hit still replaces stopped episode")
	var bad := m.duplicate(true); bad.sources[0].clips.erase("Idle")
	check(not policy.configure(bad).is_empty(),"incomplete imported clip coverage rejected at configure")
	policy.configure(m); c = context(); c.action = "invented"
	check(not policy.sample(c,0).get("ok",false),"unknown action is not fabricated idle")
	var special = load("res://scripts/core/kits/turbofit_specials.gd").new()
	special.start("charge",Vector2.ZERO,-1.0); special.tick(9.1)
	policy.configure(metadata("turbofit")); c = context(); c.presentation = special.snapshot()
	var charge: Dictionary = policy.sample(c,100)
	check(charge.ok and charge.clip == "TwoHandCombo","indefinite real charge telemetry")
	special.tick(1.0/60,{"held":false}); c.presentation = special.snapshot()
	var release: Dictionary = policy.sample(c,100)
	check(is_equal_approx(release.source_seconds,19.0/30) and release.episode_id != charge.episode_id,"phase-local release same tick new same-clip episode")
	check(policy.sample(c,100) == release,"release replay idempotent")
	policy.reset(); c = context(); c.status = "caught"; c.caught = {"activation_id":"g","elapsed":.6}
	check(policy.sample(c,0).source_seconds == 0,"Turbo caught uses accepted local block clock not owner age")
	policy.reset(); c = context(); c.paused = true
	policy.sample(c,0)
	check(is_equal_approx(policy.sample(c,1).source_seconds,1.0/60),"host paused manual step follows committed tick")
	if not failures: print("PASS: committed policy clock boundary regression")
	quit(1 if failures else 0)

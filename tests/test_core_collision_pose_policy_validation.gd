extends "res://tests/test_core_collision_pose_policy.gd"
func run() -> void:
	var policy = load(POLICY).new(); var manifest := metadata("teknium")
	var bad := manifest.duplicate(true); bad.sources[0].source_sha256 = "stale"
	check(not policy.configure(bad).is_empty(),"source/profile mismatch rejected")
	bad = manifest.duplicate(true); bad.sources[0].parents[0] = 0
	check(not policy.configure(bad).is_empty(),"invalid topology rejected")
	bad = manifest.duplicate(true); bad.sources[0].skeleton_path = NodePath("")
	check(not policy.configure(bad).is_empty(),"missing imported path rejected")
	bad = manifest.duplicate(true); bad.sources[0].clips.Idle = NAN
	check(not policy.configure(bad).is_empty(),"invalid source duration rejected")
	bad = manifest.duplicate(true); var alternate: Dictionary = bad.sources[0].duplicate(true)
	alternate.source_asset = "res://alternate.glb"; alternate.parents[1] = -1; bad.sources.append(alternate)
	check(not policy.configure(bad).is_empty(),"alternate magic topology mismatch fails closed")
	check(policy.configure(manifest).is_empty(),"real metadata accepted")
	for key in context():
		var c := context(); c.erase(key)
		check(not policy.sample(c,0).get("ok",false),"incomplete context error: "+key)
	for changes in [{"status":"invented"},{"locomotion":"ledge_hang"},{"facing":0.0},{"velocity":Vector3(NAN,0,0)},{"status":"hitstun"},{"strike_id":"x"},{"force_id":"x"},{"recovery_id":"x"},{"status":"frozen"}]:
		policy.reset(); var c := context(); c.merge(changes,true)
		check(not policy.sample(c,0).get("ok",false),"unsupported/incomplete context fails closed: "+str(changes))
	policy.configure(metadata("turbofit"))
	for request in [{"clip":"Invented","activation_id":"x"},{"clip":"AirSideKick","activation_id":"x"},{"move":"power_chord","phase":"bad","activation_id":"x","age":.1,"facing":1.0}]:
		var c := context(); c.presentation = request
		check(not policy.sample(c,0).get("ok",false),"incomplete ability telemetry rejected")
	var c := context(); var before: Dictionary = policy.sample(c,0)
	var invalid := c.duplicate(true); invalid.facing = NAN
	check(not policy.sample(invalid,100).get("ok",false),"nonfinite facing rejected")
	check(policy.sample(c,0) == before,"error leaves prior clock untouched")
	var next_life := context(); policy.sample(next_life,0); next_life.generation = 3; next_life.status = "frozen"
	check(not policy.sample(next_life,0).get("ok",false),"new frozen life cannot borrow old life pose or fabricate Idle")
	for changes in [{"force_id":"wrong-kit","force_source_time":.2},{"strike_id":"wrong-kit","strike_move":"SIDE STRIKE"},{"action":"basic"},{"frozen":true}]:
		policy.reset(); var wrong := context(); wrong.merge(changes,true)
		check(not policy.sample(wrong,0).get("ok",false),"unsupported kit identity or incomplete initial state rejected")
	policy.configure(manifest)
	var foreign := context(); foreign.presentation = {"clip":"AirSideKick","activation_id":"foreign","elapsed":.1,"facing":1.0}
	check(not policy.sample(foreign,0).get("ok",false),"Teknium cannot silently ignore foreign kit telemetry")
	var malformed := manifest.duplicate(true); malformed.sources = [null]
	check(not policy.configure(malformed).is_empty(),"malformed source entry rejects without accessing members")
	if not failures: print("PASS: committed pose policy metadata and fail-closed input")
	quit(1 if failures else 0)

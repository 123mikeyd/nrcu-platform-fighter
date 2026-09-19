extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ",label)
func _init() -> void: call_deferred("run")
func poses(v) -> Array:
	var result: Array = []
	for b in v.skeleton.get_bone_count(): result.append(v.skeleton.get_bone_pose(b))
	return result
func run() -> void:
	var v = load("res://scripts/core/presentation/ice_mage_presenter.gd").new()
	root.add_child(v)
	v.present({"grounded":true,"velocity":Vector3(2,0,0)},0)
	check(v.output.clip == "Walk","actual legacy speed selects Walk")
	if failures: v.free(); quit(1); return
	for pair in [[{"grounded":true,"velocity":Vector3(4,0,0)},"Run"],[{"grounded":true},"Idle"],[{"locomotion":"rising","grounded":false},"Idle"],[{"locomotion":"falling","grounded":false},"Idle"],[{"action":"block","grounded":true},"Idle"],[{"status":"hitstun","hit_id":"hit"},"Idle"]]:
		v.present(pair[0],1)
		check(v.output.clip == pair[1],"source available mapping")
		if pair[0].has("locomotion") or pair[0].has("action") or pair[0].has("status"): check(not v.output.fallback.is_empty(),"missing air hit shield explicitly labeled")
	var host = load("res://scripts/core/kits/ice_mage_host.gd").new()
	for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
		host.cancel(true)
		check(host.start_special(str(aim),aim,-1,true),"real cast accepted")
		var bolts := 0
		for step in 40:
			var snap: Dictionary = host.snapshot()
			v.present({"presentation":snap.presentation,"grounded":false},step)
			if not snap.presentation.clip.is_empty():
				check(v.output.clip == "IceCast" and is_equal_approx(v.output.seconds,snap.presentation.elapsed),"all specials source IceCast raw seconds, not .65 recovery duration")
			else: check(v.output.clip == "Idle","rise tail explicitly airborne Idle not extra cast")
			for event in host.collect(1,Vector3.ZERO,[]):
				if event.kind == "spawn_projectile": bolts += 1
			host.prepare(false)
		check(bolts == (0 if aim == Vector2.UP else 1),"presentation cannot create extra bolt for recovery")
	var request := {"clip":"IceStrike","elapsed":.3,"activation_id":"attack","facing":-1}
	v.present({"presentation":request,"status":"hitstun","hit_id":"h"},50)
	check(v.output.identity == "hit:h" and v.output.clip == "Idle","hit overrides stale attack")
	v.present({"presentation":request,"status":"hitstun","electrocution":{"activation_id":"grab","elapsed":.3}},50)
	check(v.output.clip == "Electrocution" and is_equal_approx(v.output.seconds,.3),"live committed electrocution overrides hit and ability")
	v.present({"presentation":request,"frozen":true,"electrocution":{"activation_id":"grab","elapsed":.3}},50)
	check(v.output.identity == "frozen" and v.output.clip == "Idle","freeze wins over electrocution and cancels attack pose")
	v.present({"presentation":request,"status":"ko","electrocution":{"activation_id":"grab","elapsed":.3}},50)
	check(v.output.identity == "inactive" and v.output.clip == "Idle","KO overrides all stale episodes")
	v.free()
	if not failures: print("PASS: core Ice presentation mapping source casts recovery and priority")
	quit(1 if failures else 0)

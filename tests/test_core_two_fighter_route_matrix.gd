extends "res://tests/test_core_recovery_acceptance.gd"
const Basic = preload("res://scripts/core/kits/turbofit_kit.gd")
const Special = preload("res://scripts/core/kits/turbofit_specials.gd")
const Pose = preload("res://scripts/core/kits/turbofit_contact_pose.gd")
func shifted(target: Dictionary, delta: Vector3) -> Dictionary:
	var copy := target.duplicate(true)
	for capsule in copy.hurtbox_snapshot.primitives: capsule.a += delta; capsule.b += delta
	return copy
func physical_route(target: Dictionary, clip: String, facing: float, character: String):
	# A real isolated match supplies source geometry; no fabricated cone or clock.
	var source_match = Match.new(); var source_actor = Actor.new(); root.add_child(source_actor)
	source_match.register_actor(1,source_actor,-1,"turbofit")
	check(source_match.reset_with_collision_profiles({1:Vector3(0,20,0)},{1:load("res://data/collision/generated/turbofit.tres")}),"actual Turbo source profile")
	source_actor.runtime.grounded = true; source_match.fighters[1].facing = facing
	var aim := Vector2(facing,-1 if clip == "MeleeBackhand" else (1 if clip == "GoalkeeperKick" else 0))
	await step(source_match,{1:press(aim,"attack")})
	var basic = source_match.fighters[1].kit.basic
	check(basic.clip == clip and not basic.activation_id.is_empty(),"real buffered activation "+clip)
	check(basic.contacts(1,source_actor.global_position,[target]).is_empty(),"inactive windup "+clip+character)
	check(basic.source_shapes.is_empty(),"startup has no source bound "+clip)
	var first: int = {"MeleeHorizontal":17,"MeleeBackhand":10,"GoalkeeperKick":23}[clip]
	for age in range(1,first+1):
		await step(source_match)
		if age < first: check(basic.source_shapes.is_empty(),"prewindow inactive "+clip)
	check(not basic.source_shapes.is_empty(),"actual input reaches active source window "+clip)
	if basic.source_shapes.is_empty(): source_actor.free(); return
	var shape: Dictionary = basic.source_shapes[0]
	check(shape.clip == clip and shape.source_seconds >= shape.source_window[0] and shape.source_seconds <= shape.source_window[1],"canonical window prerequisite "+clip)
	var origin: Vector3 = source_actor.global_position
	# Translate the unchanged full recipient snapshot, not its legacy origin,
	# onto the measured hand/foot. Far and invalid controls share this placement.
	var aligned := shifted(target,shape.a-target.hurtbox_snapshot.primitives[0].a)
	basic.tick(0,{"paused":true})
	check(basic.contacts(1,origin,[aligned]).is_empty(),"paused contact "+clip+character)
	basic.tick(0)
	check(basic.contacts(1,origin,[shifted(aligned,Vector3(50,0,0))]).is_empty(),"actual limb miss despite old origin "+clip+character)
	var invalid := aligned.duplicate(true); invalid.hurtbox_snapshot = {"ok":false,"primitives":[]}
	check(basic.contacts(1,origin,[invalid]).is_empty(),"invalid snapshot with genuinely active source fails closed "+clip+character)
	var committed_target := aligned.duplicate(true)
	committed_target.hurtbox_snapshot = {"ok":false,"primitives":[],"contact_snapshot":aligned.hurtbox_snapshot.duplicate(true)}
	var hits: Array = basic.contacts(1,origin,[committed_target])
	check(hits.size() == 1 and hits[0].geometry_mode == "generated_hurtboxes","actual full profile hit "+clip+character)
	if not hits.is_empty(): check(hits[0].contact_evidence.attack_shape == shape,"independent positive uses canonical hand/foot")
	check(basic.contacts(1,origin,[aligned]).is_empty(),"once victim "+clip+character)
	basic.tick(2)
	check(basic.contacts(1,origin,[aligned]).is_empty(),"expired episode "+clip+character)
	source_actor.free()
func run():
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(2,a)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({2:Vector3.ZERO},{2:load("res://data/collision/generated/"+character+".tres")}),"actual profile route matrix")
		m._commit_collision_poses([2])
		var record: Dictionary = m.collision_telemetry(2).contact_snapshot
		var target := {"id":2,"eligible":true,"position":a.global_position,"geometry_mode":"generated_hurtboxes","hurtbox_snapshot":record}
		var limb: Vector3 = record.primitives[0].a
		for facing in [-1.0,1.0]:
			for clip in ["MeleeHorizontal","MeleeBackhand","GoalkeeperKick","AirSideKick","AirDownKick"]:
				var air: bool = clip in ["AirSideKick","AirDownKick"]
				if not air:
					await physical_route(target,clip,facing,character)
					continue
				var aim := Vector2(facing, -1 if clip == "MeleeBackhand" else (1 if clip in ["GoalkeeperKick","AirDownKick"] else 0))
				var age: float = {"MeleeHorizontal":.28,"MeleeBackhand":.28,"GoalkeeperKick":.45,"AirSideKick":5.0/30,"AirDownKick":.4}[clip]
				var direction := Vector3.UP if clip == "MeleeBackhand" else Vector3(facing,-.25 if clip == "GoalkeeperKick" else 0,0).normalized()
				var origin: Vector3 = limb-(Pose.new().center(clip,age,facing) if air else direction)
				target.position = origin+Vector3(facing,-1 if clip == "AirDownKick" else 0,0)
				var basic = Basic.new(); basic.start(clip,aim,air,facing)
				check(basic.contacts(1,origin,[target]).is_empty(),"inactive windup "+clip+character)
				basic.tick(age); basic.tick(0,{"paused":true})
				check(basic.contacts(1,origin,[target]).is_empty(),"paused contact "+clip+character)
				basic.tick(0)
				check(basic.contacts(1,origin,[shifted(target,Vector3(50,0,0))]).is_empty(),"actual limb miss despite old origin "+clip+character)
				var committed_target := target.duplicate(true)
				committed_target.hurtbox_snapshot = {"ok":false,"primitives":[],"contact_snapshot":record.duplicate(true)}
				var hits: Array = basic.contacts(1,origin,[committed_target])
				check(hits.size() == 1 and hits[0].geometry_mode == "generated_hurtboxes","actual full profile hit "+clip+character)
				check(basic.contacts(1,origin,[target]).is_empty(),"once victim "+clip+character)
				basic.tick(2)
				check(basic.contacts(1,origin,[target]).is_empty(),"expired episode "+clip+character)
			for kind in ["power_chord","sound_orb"]:
				var special = Special.new(); special.start(kind,Vector2.ZERO if kind == "power_chord" else Vector2.DOWN,facing)
				var origin: Vector3 = limb-Vector3(facing,0,0) if kind == "power_chord" else limb
				if kind == "power_chord":
					check(special.collect(1,origin,[target]).is_empty(),"charge inactive "+character)
					special.tick(.2,{"held":false})
				special.tick(0,{"paused":true})
				check(special.collect(1,origin,[target]).is_empty(),"paused "+kind+character)
				special.tick(0)
				var hits: Array = special.collect(1,origin,[target])
				check(hits.size() == 1 and hits[0].geometry_mode == "generated_hurtboxes","actual full profile "+kind+character)
				check(special.collect(1,origin,[target]).is_empty(),"once victim "+kind+character)
				special.tick(2)
				check(special.collect(1,origin,[target]).is_empty(),"expired "+kind+character)
	a.free()
	if not failures: print("PASS: two fighter route matrix (%d checks)" % checks)
	quit(1 if failures else 0)

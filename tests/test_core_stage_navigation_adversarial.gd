extends "res://tests/test_core_stage_navigation_native.gd"
func run():
	for kind in ["repo_hard","sparring_easy"]:
		await interrupted(kind)
	if not failures: print("PASS: native navigation committed lock freeze hitstop moving target and jump resources")
	quit(1 if failures else 0)
func interrupted(kind: String):
	var stage = load("res://scripts/experimental/full_game_stage.gd").new(); root.add_child(stage)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"teknium"); m.register_actor(2,b,-1,"teknium")
	m.reset_with_collision_profiles({1:Vector3(1.4,6.25,0),2:Vector3(-5.2,3.3,0)},{1:fitted("teknium"),2:fitted("teknium")},"grounded_jostle")
	for i in 12: await step(m)
	var attack = Frame.new(); attack.axis=Vector2.RIGHT; attack.held.special=true; attack.pressed.special=true
	await step(m,{2:attack})
	check(m.fighters[2].force != null and not b.can_accept_jump(),"accepted real combat lock prerequisite")
	var owner = load("res://scripts/core/input/sparring_match_input.gd" if kind=="sparring_easy" else "res://scripts/core/input/repo_ai_match_input.gd").new()
	owner.configure(2,true,"easy" if kind=="sparring_easy" else "hard"); owner.stage_bounds=stage.ai_bounds(); owner.configure_navigation(geometry(stage))
	check(owner._observation(m,2).combat_locked,"wrapper observes accepted default-host combat lock")
	var human = Source.new()
	var saw_locked := false; var frozen := false; var stopped := false; var landed := false; var moving := false
	var freeze_left := 0; var jumps := 0; var airborne_spent := 0
	for i in 900:
		await physics_frame
		var legal: bool = b.can_accept_jump()
		if not legal and i < 12: saw_locked = true
		if not frozen and b.position.y > 4.0:
			m.set_frozen(2,true); frozen=true; freeze_left=35
		elif freeze_left==0 and m.fighters[2].frozen: m.set_frozen(2,false)
		if frozen and freeze_left==0 and not stopped and b.velocity.y>0:
			m.fighters[2].hitstop_left=6; stopped=true
		var age: int = owner.navigation._age
		var old_air: int = b.runtime.air_jumps_left
		var frozen_tick: bool = m.fighters[2].frozen
		var stopped_tick: bool = m.fighters[2].hitstop_left>0
		var frames = owner.sample_all(m,{1:human.sample(m.tick)})
		if frames[2].pressed.get("jump",false): jumps+=1
		if frozen_tick or stopped_tick:
			check(owner.navigation._age==age,"frozen/stopped navigation age does not spend retry budget")
			check(not frames[2].pressed.get("jump",false),"frozen/stopped never repeats jump edge")
		m.simulate(frames)
		if frozen_tick or stopped_tick: check(b.runtime.air_jumps_left==old_air,"status does not spend or restore jump resources")
		if b.runtime.grounded: airborne_spent=0
		elif b.runtime.air_jumps_left < old_air: airborne_spent += old_air-b.runtime.air_jumps_left
		check(airborne_spent<=1 and b.runtime.air_jumps_left>=0,"at most one actual air resource per grounded episode")
		if freeze_left>0: freeze_left-=1
		if b.runtime.grounded and owner.navigation.support(b.position)=="Platform3": landed=true
		if frozen and not moving:
			key(KEY_D,true); moving=true
		if moving and a.position.x > 5.5: key(KEY_D,false)
		if moving and i>450 and owner.navigation._goal==owner.navigation.support(a.position) and owner.navigation._goal!="Platform3": break
	print("ADVERSARIAL ",kind," locked=",saw_locked," frozen=",frozen," stopped=",stopped," landed=",landed," moved=",moving," jumps=",jumps," goal=",owner.navigation._goal," target=",a.position)
	check(saw_locked and frozen and stopped,"real accepted lock/freeze/hitstop prerequisites")
	check(landed,"interrupted upper route resumes with bounded legal retries")
	check(moving and owner.navigation._goal!="Platform3","moving target changes observed support during interrupted flight")
	check(jumps<=10,"bounded jump attempts under interruption")
	key(KEY_D,false); human.reset()
	if Input.joy_connection_changed.is_connected(human._on_joy_connection_changed): Input.joy_connection_changed.disconnect(human._on_joy_connection_changed)
	a.free(); b.free(); stage.free()

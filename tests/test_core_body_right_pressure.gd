extends "res://tests/test_core_ledge_match.gd"
const Source = preload("res://scripts/core/input/player_input_source.gd")
const Stage = preload("res://scripts/core/stage/combat_lab_stage.gd")
var registration_order := [1,2]
func run():
	for parsed in [false,true]:
		for side in [1,-1]:
			for release in [false,true]:
				await route(side,release,parsed)
	if not failures: print("PASS body right pressure (%d checks)" % checks)
	quit(1 if failures else 0)
func route(side, release, parsed):
	var terrain = body(Vector3(0,-0.4,0),Vector3(24,0.8,3))
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	var sources = {}
	for id in registration_order:
		var actor = Actor.new(); root.add_child(actor); m.register_actor(id,actor,-1,"ice_mage")
		var source = Source.new(); source.slot = id-1; sources[id] = source
	m.configure_ledges(Stage.new().create_anchors(),LedgePolicy.new())
	m.reset({1:Vector3(-1,0.1,0),2:Vector3(1,0.1,0)})
	var hanger = 2 if side == 1 else 1
	var walker = 3-hanger
	var outward = KEY_RIGHT if side == 1 else KEY_A
	var inward = KEY_LEFT if side == 1 else KEY_D
	var approach = KEY_D if side == 1 else KEY_LEFT
	var touched = false
	var native_contact = false
	var lost = false
	var held_position := Vector3.ZERO
	for t in range(1,290):
		var keys = {}
		if t > 40 and t <= 125: keys[outward] = true
		if t > 125 and t <= 144: keys[inward] = true
		if t > 144 and not (release and touched): keys[approach] = true
		if parsed:
			for key in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]:
				var event = InputEventKey.new(); event.physical_keycode = key; event.pressed = keys.get(key,false); Input.parse_input_event(event)
			Input.flush_buffered_events()
		var frames = {}
		for id in [1,2]:
			frames[id] = sources[id].sample(t) if parsed else sources[id].sample_snapshot(t,keys)
			check(not frames[id].held.get("attack",false) and not frames[id].held.get("special",false),"pressure is movement only")
		await tick(m,frames)
		var a = m.fighters[walker].actor; var b = m.fighters[hanger].actor
		if t == 144:
			check(m.ledge_telemetry(hanger).anchor_id != "" and m.ledge_telemetry(hanger).get("caught_at",-1) == 143,"keyboard route catches mirror %d at browser tick" % side)
			held_position = b.position
		if t > 144:
			for i in a.get_slide_collision_count():
				var contact = a.get_slide_collision(i)
				for j in contact.get_collision_count():
					if contact.get_collider(j) == b: native_contact = true
			if absf(a.position.x-b.position.x)<0.7 and absf(a.velocity.x)<0.001: touched = true
			if m.ledge_telemetry(hanger).anchor_id == "": lost = true
			check(b.position == held_position and b.velocity == Vector3.ZERO,"hanger remains stationary under pressure")
			if touched:
				var q = PhysicsShapeQueryParameters3D.new(); q.shape = a.get_node("CoreCapsule").shape
				q.transform = a.global_transform * a.get_node("CoreCapsule").transform; q.collision_mask = 2; q.exclude = [a.get_rid()]; q.margin = 0.0
				check(a.get_world_3d().direct_space_state.intersect_shape(q).is_empty(),"stopped grounded mover does not introduce penetration")
		if t == 244: check(touched and native_contact,"browser first native stop at tick 244")
		if t >= 242 and t <= 248:
			print("PRESSURE ",side," release=",release," parsed=",parsed," tick=",t," walker=",a.position," hanger=",b.position," velocity=",a.velocity," event=",m.ledge_events.get(hanger,{}))
	check(touched and native_contact,"native approach stops on hanger")
	check(not lost,"continued/released pressure retains anchor side=%d release=%s parsed=%s" % [side,release,parsed])
	check(m.fighters[1].percent == 0 and m.fighters[2].percent == 0,"no attack damage in pressure fixture")
	if parsed:
		for key in [KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT]:
			var event = InputEventKey.new(); event.physical_keycode = key; event.pressed = false; Input.parse_input_event(event)
		Input.flush_buffered_events()
	cleanup(m); terrain.free()

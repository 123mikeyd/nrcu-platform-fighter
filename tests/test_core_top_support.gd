extends "res://tests/test_core_grab_slice.gd"
const Source = preload("res://scripts/core/input/player_input_source.gd")
func floor_body():
	var body = StaticBody3D.new(); var c = CollisionShape3D.new(); var s = BoxShape3D.new()
	s.size = Vector3(40,1,4); c.shape = s; body.add_child(c); body.position.y = -0.5; root.add_child(body); return body
func key(code: int, pressed: bool):
	var e = InputEventKey.new(); e.physical_keycode = code; e.keycode = code; e.pressed = pressed
	Input.parse_input_event(e); Input.flush_buffered_events()
func fitted(id: String):
	return load("res://data/collision/generated/"+id+".tres").merged_with(load("res://data/collision/overrides/"+id+"_anatomical_v1.tres")).profile
func run():
	for lower in ["teknium","turbofit"]:
		for upper in ["teknium","turbofit"]:
			for facing in [-1,1]:
				for reverse in [false,true]:
					var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
					root.add_child(a); root.add_child(b)
					if reverse: m.register_actor(2,b,-1,lower); m.register_actor(1,a,-1,upper)
					else: m.register_actor(1,a,-1,upper); m.register_actor(2,b,-1,lower)
					check(m.reset_with_collision_profiles({1:Vector3(0,3.4,0),2:Vector3.ZERO},{1:fitted(upper),2:fitted(lower)},"legacy_solid"),"real generated mode")
					m.fighters[1].facing = facing; m.fighters[2].facing = facing
					var source = Source.new()
					key(KEY_SPACE,true)
					await step(m,{1:source.sample(m.tick)})
					key(KEY_SPACE,false)
					check(a.runtime.air_jumps_left == 0 and a.velocity.y > 0,"parsed Space accepted actual air jump")
					a.runtime.recovery_spent = true
					var entered = false; var minimum = INF; var contacts = 0
					# Mesh oracle: head max Idle includes canonical -.224 for Teknium.
					# Upper falling Jump ends at foot +.091913 (Tek), FallLoop Turbo >= -.01.
					var head = 1.915278 if lower == "teknium" else 2.389518
					var foot_offset = 0.0919 if upper == "teknium" else -0.01
					for i in 110:
						await step(m,{1:source.sample(m.tick)})
						var dx = absf(a.position.x-b.position.x)
						if a.velocity.y <= 0 and a.position.y < 2.8 and dx < 0.12:
							var actual_offset = foot_offset
							if m.collision_telemetry(1).pose_request.state == "supported": actual_offset = .001441 if upper == "teknium" else .057009
							entered = true; minimum = minf(minimum,a.position.y+actual_offset-b.position.y-head)
						for j in a.get_slide_collision_count():
							if a.get_slide_collision(j).get_collider() == b: contacts += 1
					check(entered,"descending centered head prerequisite")
					print("HEAD ",upper," on ",lower," face=",facing," reverse=",reverse," min_conservative_foot_gap=",minimum," native_contacts=",contacts)
					check(minimum >= 0.001,"descending conservative foot-anchor clearance: "+upper+" on "+lower)
					check(not a.runtime.grounded or absf(a.position.x-b.position.x)>0.4,"head is not terrain")
					a.free(); b.free(); floor_node.free()
	if not failures: print("PASS: separated top support parsed jump real physics")
	quit(1 if failures else 0)

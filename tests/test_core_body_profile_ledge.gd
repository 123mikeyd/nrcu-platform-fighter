extends "res://tests/test_core_body_profile.gd"
const Policy = preload("res://scripts/core/stage/ledge_policy.gd")
const Anchor = preload("res://scripts/core/stage/ledge_anchor.gd")
class RecordingPolicy extends Policy:
	var shapes: Array = []
	var transforms: Array = []
	func terrain_path_clear(space, shape, offset, points, mask: int = 1, exclude: Array[RID] = []) -> bool:
		shapes.append(shape)
		transforms.append(offset)
		return super.terrain_path_clear(space,shape,offset,points,mask,exclude)
func block(at, size):
	var b = StaticBody3D.new(); var c = CollisionShape3D.new(); var s = BoxShape3D.new()
	s.size = size; c.shape = s; b.add_child(c); b.position = at; root.add_child(b); return b
func run():
	for side in [-1,1]:
		for requester in [1,2]:
			for large in [false,true]:
				var radius = 0.6 if large else 0.25; var height = 2.8 if large else 1.0
				var terrain = block(Vector3(-side*2,-0.5,0),Vector3(4,1,4))
				var m = Match.new(); var a = Actor.new(); var b = Actor.new()
				a.configure_body_profile(body_profile(radius,height))
				b.configure_body_profile(body_profile(0.25 if large else 0.6,1.0 if large else 2.8))
				root.add_child(a); root.add_child(b)
				m.register_actor(requester,a); m.register_actor(3-requester,b)
				m.reset({requester:Vector3(side*1.2,-1,0),3-requester:Vector3(-side*8,4,0)})
				var anchor = Anchor.new(); anchor.anchor_id = "edge"; anchor.outward = side
				m.configure_ledges([anchor],RecordingPolicy.new())
				var f = Frame.new(); f.axis.x = -side
				await step(m,{requester:f})
				check(m.ledge_telemetry(requester).anchor_id == "edge", "actual unequal capsule catches either stage side")
				check(m.ledge_policy.shapes.has(a.get_node("CoreCapsule").shape), "clearance uses requesting shape, not first actor")
				check(m.ledge_policy.transforms.has(a.get_node("CoreCapsule").transform), "clearance preserves complete requesting shape transform")
				var hang = Vector3(side*(radius+0.25),-height+0.3,0)
				check(a.position.is_equal_approx(hang), "per-body safe hang placement")
				var up = Frame.new(); up.axis.y = -1
				await step(m,{requester:up})
				check(a.position.is_equal_approx(Vector3(-side*(radius+0.3),0.06,0)), "per-body complete elbow climb")
				for i in 5: await step(m)
				check(a.runtime.grounded, "climb hands terrain landing to native actor")
				check(anchor.edge == Vector3.ZERO and anchor.hang_offset == Vector3(0.65,-1.5,0), "stage geometry never mutated by body fit")
				a.free(); b.free(); terrain.free()
	if not failures: print("PASS body profile ledge (%d checks)" % checks)
	quit(1 if failures else 0)

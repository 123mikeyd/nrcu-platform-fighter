extends "res://tests/test_full_game_flow.gd"
func run():
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		var view := SubViewport.new()
		view.size = size; view.own_world_3d = true
		root.add_child(view)
		app = load("res://scenes/experimental_full_game.tscn").instantiate()
		view.add_child(app)
		app.show_select(); app.start_match()
		await frames(4)
		var camera: Camera3D = view.get_camera_3d()
		var safe := Rect2(12,app.hud.get_global_rect().end.y+12,size.x-24,0)
		safe.end.y = size.y-44
		for actor in app.session.actors:
			var collider: CollisionShape3D = actor.get_node("CoreCapsule")
			var shape: CapsuleShape3D = collider.shape
			var snapshot = {"body":{"radius":shape.radius,"height":shape.height,"center":collider.position}}
			var points := [Vector3(0,6.2,0),Vector3(-5.2,3.225,0),Vector3(5.2,3.225,0)]
			for anchor in app.session.stage.anchors():
				points.append_array([anchor.hang(snapshot),Vector3(anchor.hang(snapshot).x,anchor.climb(snapshot).y,0),anchor.climb(snapshot)])
			for origin in points:
				for x in [-shape.radius,shape.radius]:
					for y in [-shape.height/2,shape.height/2]:
						for z in [-shape.radius,shape.radius]:
							var p = camera.unproject_position(origin+collider.position+Vector3(x,y,z))
							assert(safe.has_point(p),"actual full collider clears HUD at top and both ledge paths")
			var height = camera.unproject_position(Vector3.ZERO).y-camera.unproject_position(Vector3(0,shape.height,0)).y
			assert(height >= size.y*0.09,"fighter remains readable")
		print("CAMERA ",size," full actual collider route bounds PASS")
		app.free(); view.free()
	await frames(2)
	print("PASS: full game camera actual full colliders top platform ledge routes at 1280 and 960")
	quit()

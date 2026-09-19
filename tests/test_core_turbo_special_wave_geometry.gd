extends SceneTree
const Wave = preload("res://scripts/core/kits/turbofit_wave.gd")
var failures := 0
var arena: Node3D
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func body_at(pos: Vector3, wall := false) -> PhysicsBody3D:
	var body: PhysicsBody3D = StaticBody3D.new() if wall else CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	if wall:
		var box := BoxShape3D.new(); box.size = Vector3(.02,5,5); collider.shape = box
	else:
		var capsule := CapsuleShape3D.new(); capsule.radius = .55; capsule.height = 1.8; collider.shape = capsule; collider.position.y = .9
	body.add_child(collider); arena.add_child(body); body.position = pos
	return body
func run() -> void:
	for mode in ["target","left","thinwall","shield","absorb","ally","fade","offaxis","overlap","tie","sorted","reflect","layer4"]:
		arena = Node3D.new(); root.add_child(arena)
		var facing := -1.0 if mode == "left" else 1.0
		var owner := body_at(Vector3.ZERO)
		var target := body_at(Vector3(3*facing,0,.85 if mode == "offaxis" else 0))
		if mode == "layer4": target.collision_layer = 4
		var entries: Array = [{"id":1,"body":owner,"team":0}, {"id":9,"body":target,"team":1,"shielding":mode == "shield","absorbing":mode == "absorb"}]
		if mode == "thinwall": body_at(Vector3(2,1,0),true)
		if mode == "ally": entries.append({"id":2,"body":body_at(Vector3(1.4,0,0)),"team":0})
		if mode in ["overlap","tie","sorted"]: target.position = Vector3(1,0,0)
		if mode == "tie": body_at(Vector3(1,1,0),true)
		if mode == "sorted": entries.append({"id":3,"body":body_at(Vector3(1,0,0)),"team":1})
		await physics_frame; await process_frame
		var wave = Wave.new(); wave.start("wave:"+mode,1,0,Vector3(.8*facing,1,0),facing)
		if mode == "fade": wave.tick(.65) # No scene query: position first, then harmless overlap.
		if mode == "fade":
			target.position = wave.snapshot().position - Vector3.UP
			await physics_frame; await process_frame
		if mode == "reflect":
			wave.position = Vector3(2.4,1,0); wave.reflect(9,1)
		var effects: Array = wave.tick(.4,{"space":arena.get_world_3d().direct_space_state,"targets":entries})
		if mode == "fade":
			check(effects.is_empty(), "faded pulse ignores overlapping fighter")
		else:
			check(effects.size() == 1, "single swept contact: "+mode)
			if effects.size() == 1:
				var e: Dictionary = effects[0]
				if mode in ["thinwall","tie"]: check(e.kind == "terrain", "terrain wins: "+mode)
				elif mode == "shield": check(e.kind == "shield_absorb" and e.damage == 0, "shield fully absorbs")
				elif mode == "absorb": check(e.kind == "absorb" and e.payload_damage == 11, "absorption intent after contact")
				else:
					check(e.kind == "hit" and e.damage == 11 and e.base_knockback == 4.5, "source wave payload: "+mode)
					check(e.victim == (1 if mode == "reflect" else (3 if mode == "sorted" else 9)), "deterministic contact victim: "+mode)
			check(not wave.snapshot().active and wave.tick(.1,{"space":arena.get_world_3d().direct_space_state,"targets":entries}).is_empty(), "one impact consumes: "+mode)
		check(target.velocity == Vector3.ZERO, "no actor mutation")
		arena.free()
	if failures == 0: print("PASS core Turbofit wave swept cylinder geometry and effect intents")
	quit(1 if failures else 0)

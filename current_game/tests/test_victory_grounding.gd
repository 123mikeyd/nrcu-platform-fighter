extends SceneTree
# Victory screen: winners stand ON the podium and the clapping back row stands on the floor.
# Measures evaluated skinned soles (not bones/bind-space bounds).
const PODIUM_TOP := 0.16
const TOL := 0.035
var failures := 0
var vs

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func sole_y(n: Node) -> float:
	var lo := INF
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if not mi.is_visible_in_tree() or mi.mesh == null: continue
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			var skinned: bool = sk != null and mi.skin != null and bones != null and bones.size() > 0
			var per: int = bones.size() / verts.size() if skinned else 0
			var mats := []
			if skinned:
				sk.force_update_all_bone_transforms()
				for i in mi.skin.get_bind_count():
					var bi := mi.skin.get_bind_bone(i)
					if bi < 0: bi = sk.find_bone(mi.skin.get_bind_name(i))
					mats.append(sk.get_bone_global_pose(bi) * mi.skin.get_bind_pose(i))
			for v in range(0, verts.size(), 3):
				var p: Vector3
				if skinned:
					var acc := Vector3.ZERO
					for k in per:
						var w: float = weights[v * per + k]
						if w > 0.0 and int(bones[v * per + k]) < mats.size(): acc += w * (mats[bones[v * per + k]] * verts[v])
					p = sk.global_transform * acc
				else:
					p = mi.global_transform * verts[v]
				lo = minf(lo, p.y)
	return lo

func run():
	vs = load("res://scripts/victory_screen.gd").new()
	root.add_child(vs)
	await process_frame
	var cases := [["teknium", ["doge_man", "turbofit", "witcheer"]], ["doge_man", ["teknium"]], ["turbofit", ["teknium"]], ["witcheer", ["teknium"]]]
	for dance in ["GangnamA", "GangnamB", "Robot", "Tut"]:
		vs.force_dance = dance
		vs.show_results([{"id": "teknium"}], [], "T")
		for f in 12: await process_frame
		var a = vs.actors[0]
		var d := sole_y(a.visual) - PODIUM_TOP
		check(absf(d) < TOL, "teknium %s starts on the podium (sole %+.3f)" % [dance, d])
	vs.force_dance = ""
	for c in cases:
		var losers := []
		for l in c[1]: losers.append({"id": l})
		vs.show_results([{"id": c[0]}], losers, "T")
		for f in 12: await process_frame
		for a in vs.actors:
			var surface := PODIUM_TOP if a.role == "winner" else 0.0
			var d := sole_y(a.visual) - surface
			check(absf(d) < TOL, "%s %s (%s) feet on its surface at start (sole %+.3f)" % [a.id, a.role, a.get("clip", ""), d])
		# freeze frame of the pose-in
		for i in 120:
			await process_frame
			if vs.winner_frozen(): break
		var w = vs.actors[0]
		var dw := sole_y(w.visual) - PODIUM_TOP
		if c[0] == "doge_man":
			check(dw > 0.15, "Doge's authored end hop is kept (sole %+.3f)" % dw)
		elif c[0] != "witcheer":   # Witcheer freezes mid-kick-hop
			check(absf(dw) < TOL, "%s freeze frame on the podium (sole %+.3f)" % [c[0], dw])
		else:
			check(dw > -TOL, "witcheer freeze is not below the podium (sole %+.3f)" % dw)
	vs.show_results([{"id": "ggb"}], [], "T")
	for f in 12: await process_frame
	check(sole_y(vs.actors[0].visual) - PODIUM_TOP > 0.3, "GGB keeps its hover")
	vs.clear()
	if failures == 0: print("PASS: victory screen grounding (podium winners, floor losers, Doge hop, GGB hover)")
	quit(failures)

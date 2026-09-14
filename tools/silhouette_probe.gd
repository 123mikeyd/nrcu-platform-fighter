extends SceneTree
# Silhouette probe (WP-3): posed silhouette bounds per subject (skinned GLB
# aware, via tests/posed_character_bounds.gd) in fighter local space — the
# measurement method behind FighterPresentationFactory.SILHOUETTE. Run it after
# any model/rig change and re-check the table:
#   godot --path <repo> --resolution 1280x720 --fixed-fps 60 \
#     --script res://tools/silhouette_probe.gd
const Bounds = preload("res://tests/posed_character_bounds.gd")

func _initialize() -> void:
	call_deferred("run")

func measure(actor: Node3D, tag: String) -> void:
	for sk in actor.find_children("*", "Skeleton3D", true, false):
		sk.force_update_all_bone_transforms()
	var b: Dictionary = Bounds.new().bounds(actor)
	if b.is_empty():
		print("BOUNDS|%s|EMPTY" % tag)
		return
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for entry in b.values():
		lo = lo.min(Vector3(entry.min[0], entry.min[1], entry.min[2]))
		hi = hi.max(Vector3(entry.max[0], entry.max[1], entry.max[2]))
	var origin := actor.global_position
	print("BOUNDS|%s|lo=(%.3f, %.3f, %.3f)|hi=(%.3f, %.3f, %.3f)|h=%.3f|w=%.3f|d=%.3f|meshes=%d" % [
		tag, lo.x - origin.x, lo.y - origin.y, lo.z - origin.z,
		hi.x - origin.x, hi.y - origin.y, hi.z - origin.z,
		hi.y - lo.y, hi.x - lo.x, hi.z - lo.z, b.size()])

func run() -> void:
	root.size = Vector2i(1280, 720)
	var Roster = load("res://scripts/roster.gd")
	for id in Roster.ids():
		var f = load("res://scripts/fighter.gd").new()
		f.character_id = str(id)
		root.add_child(f)
		f.global_position = Vector3.ZERO
		f.set_physics_process(false)
		for i in 3: await process_frame
		measure(f, "roster:" + str(id))
		f.queue_free()
		await process_frame
	var b = load("res://scripts/bobo_fighter.gd").new()
	root.add_child(b)
	b.global_position = Vector3.ZERO
	b.set_physics_process(false)
	for i in 3: await process_frame
	measure(b, "encounter:bobo")
	measure(b.find_child("BoboVisual", true, false), "bobo_visual_only")
	quit(0)

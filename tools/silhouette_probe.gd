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
	var Factory = load("res://scripts/frontend/fighter_presentation_factory.gd")
	var View = load("res://scripts/frontend/fighter_render_view.gd")
	for id in Factory.all_ids():
		var view = View.new()
		view.size = Vector2(267, 296)
		root.add_child(view)
		view.set_profile(Factory.PROFILE_PLAYER_BAY)
		view.set_subjects([id])
		# Use the exact paused t=0 UI lifecycle, never gameplay's advancing idle.
		var subject = view.subject_nodes()[0]
		subject.rotation_degrees = Vector3.ZERO
		for i in 3: await process_frame
		measure(subject, "presentation:" + str(id))
		view.queue_free()
		await process_frame
	quit(0)

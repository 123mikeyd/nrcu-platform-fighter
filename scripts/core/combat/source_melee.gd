extends RefCounted
## Source-pose attack authoring, never recipient inflation or renderer state.
## Windows are source seconds, inclusive. See docs/core-melee-contact-alignment.md.
const WINDOWS := {"SwingPunchV1":[.15,.20],"Punch":[36.0/60,48.0/60],"Kick":[42.0/60,60.0/60],
	"MeleeHorizontal":[52.0/60,59.0/60],"MeleeBackhand":[42.0/60,54.0/60],"GoalkeeperKick":[48.0/60,62.0/60]}
static func shapes(host, actor_transform: Transform3D) -> Array:
	if host == null: return []
	var record: Dictionary = host.telemetry().get("contact_snapshot",{})
	if not record.get("ok",false): return []
	var request: Dictionary = record.get("pose_request",{})
	var clip: String = request.get("clip","")
	if not WINDOWS.has(clip): return []
	var seconds: float = request.source_seconds
	var window: Array = WINDOWS[clip]
	if seconds < window[0] or seconds > window[1]: return []
	var pose: Dictionary = host.sampler.sample(clip,seconds,request.time_policy)
	var bone: String = {"SwingPunchV1":"LeftHand","Punch":"LeftHand","Kick":"RightFoot","MeleeHorizontal":"mixamorig_RightHand","MeleeBackhand":"mixamorig_LeftHand","GoalkeeperKick":"mixamorig_RightFoot"}[clip]
	var end: String = {"Kick":"RightToeBase","GoalkeeperKick":"mixamorig_RightToe_End"}.get(clip,bone)
	var hand: bool = "Hand" in bone
	if not pose.has(bone) or not pose.has(end): return []
	var transform: Transform3D = actor_transform * request.modelplacement
	return [{"a":transform*pose[bone].origin,"b":transform*pose[end].origin,
		"radius":.16 if hand else .14,"visual_radius":.14 if hand else .12,"visual_padding":.02,
		"bone":bone,"end_bone":end,"clip":clip,"source_seconds":seconds,"source_window":window,"pose_revision":record.pose_revision if record.has("pose_revision") else request.pose_revision}]
static func contact(target: Dictionary, shapes_to_test: Array) -> Dictionary:
	for shape in shapes_to_test:
		var hit: Dictionary = preload("res://scripts/core/collision/recipient_queries.gd").sphere(target,shape.a,shape.b,shape.radius)
		if not hit.is_empty():
			hit.attack_shape = shape.duplicate(true)
			return hit
	return {}

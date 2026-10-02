extends SkeletonModifier3D
# Runs after the AnimationPlayer: holds the crouch pose at the start of a down-basic launched from
# the crouch and fades it out (influence 1 -> 0), so the attack begins on the crouch pose.
var pose: Array[Transform3D] = []
var total := 0.12
var remaining := 0.0
func start(seconds: float) -> void:
	total = maxf(seconds, 0.001); remaining = total; influence = 1.0; active = true
func stop() -> void:
	remaining = 0.0; active = false
func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or remaining <= 0.0 or pose.size() != sk.get_bone_count():
		active = false; return
	influence = smoothstep(0.0, 1.0, remaining / total)
	for b in sk.get_bone_count():
		sk.set_bone_pose(b, pose[b])
	remaining -= maxf(delta, 0.0)
	if remaining <= 0.0: active = false

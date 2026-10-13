extends SkeletonModifier3D
# Uses the exact approved authored axes, amplitudes and resting drape.
# Movement selects authored sweep/lift; cascaded damped response delays tips.
var actor
var levels: Array[float] = [-1.0, -1.0, -1.0, -1.0]
var speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
var target_value := -1.0
var previous_speed := 0.0
var previous_position := Vector3.ZERO
var initialized := false
var axes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/turbofit/hair_axes.json"))
var modifications := 0
func _process_modification_with_delta(delta: float) -> void:
    var sk: Skeleton3D = get_skeleton()
    if sk == null or not is_instance_valid(actor):
        return
    var velocity: Vector3 = actor.velocity if actor is CharacterBody3D else Vector3.ZERO
    var grounded: bool = actor.is_grounded() if actor.has_method("is_grounded") else true
    var planar: float = Vector2(velocity.x, velocity.z).length()
    var dt: float = minf(delta, 0.0333333)
    var acceleration: float = (planar - previous_speed) / maxf(dt, 0.001)
    target_value = -1.0 + clampf(planar / 6.0 + maxf(acceleration, 0.0) * 0.008, 0.0, 1.0)
    if not grounded and velocity.y < -0.25:
        target_value = lerpf(target_value, 1.15, clampf(-velocity.y / 5.0, 0.0, 1.0))
    if not initialized or actor.global_position.distance_to(previous_position) > 3.0:
        levels.assign([-1.0, -1.0, -1.0, -1.0])
        speeds.assign([0.0, 0.0, 0.0, 0.0])
        initialized = true
    if dt > 0.0:
        for i in 4:
            var goal: float = target_value if i == 0 else levels[i - 1]
            var frequency: float = 15.0 - float(i) * 1.2
            speeds[i] += ((goal - levels[i]) * frequency * frequency - 1.55 * frequency * speeds[i]) * dt
            levels[i] = clampf(levels[i] + speeds[i] * dt, -1.15, 1.25)
    for name in axes:
        var bone: int = sk.find_bone(name)
        if bone < 0:
            continue
        var index: int = int(str(name).right(2)) - 1
        var xyz: Array = axes[name]
        var axis := Vector3(xyz[0], xyz[1], xyz[2]).normalized()
        var angle: float = deg_to_rad([17.0, 19.0, 16.0, 9.0][index]) * levels[index]
        sk.set_bone_pose_rotation(bone, sk.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(axis, angle))
    previous_speed = planar
    previous_position = actor.global_position
    modifications += 1

extends RefCounted
## Per-life resource policy. Call only on accepted commands; caller moves actor.
var jumps_used := 0
var float_remaining := 1.2
var recovery_spent := false
func _blocked(context: Dictionary) -> bool:
	for key in ["stopped","paused","frozen","caught","disabled","hitstun","drop_committed","recovery_spent"]:
		if context.get(key,false): return true
	return recovery_spent
func commit_jump(source: int, context: Dictionary) -> Dictionary:
	if _blocked(context) or jumps_used >= 5 or context.get("charging",false) or context.get("landing_lag",0.0) > 0: return {}
	var speed := 10.5*pow(.84,jumps_used)
	jumps_used += 1
	return {"kind":"motion_request","mode":"jump_launch","source":source,"vertical_speed":speed,"jumps_used":jumps_used}
func float_request(source: int, delta: float, context: Dictionary) -> Dictionary:
	var velocity: Vector3 = context.get("velocity",Vector3.ZERO)
	if delta <= 0 or _blocked(context) or context.get("grounded",false) or not context.get("jump_held",false) or velocity.y >= 0 or float_remaining <= 0: return {}
	float_remaining = maxf(0,float_remaining-delta)
	return {"kind":"motion_request","mode":"vertical_floor","source":source,"vertical_speed":maxf(velocity.y,-1.5)}
func commit_recovery() -> void:
	recovery_spent = true
	jumps_used = 2 # Original explicit assignment, not GGB maximum.
func landed(terrain_support: bool) -> void:
	if terrain_support: reset()
func reset() -> void:
	jumps_used = 0
	float_remaining = 1.2
	recovery_spent = false
func terrain_grounded(body: CharacterBody3D, fighter_bodies: Array) -> bool:
	if not body.is_on_floor() or body.velocity.y > 0: return false
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		for j in collision.get_collision_count():
			var collider = collision.get_collider(j)
			if is_instance_valid(collider) and collider not in fighter_bodies and not collider.is_in_group("fighters") and collision.get_normal(j).dot(body.up_direction) >= cos(body.floor_max_angle): return true
	return false
func snapshot() -> Dictionary:
	return {"jumps_used":jumps_used,"float_remaining":float_remaining,"recovery_spent":recovery_spent}

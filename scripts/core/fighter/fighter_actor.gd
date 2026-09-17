extends CharacterBody3D
## Foot-origin capsule; match calls simulate exactly once per 60Hz physics tick.
## No autonomous process callback, artwork, input sampler or input queue.
const Profile = preload("res://scripts/core/fighter/movement_profile.gd")
const Runtime = preload("res://scripts/core/fighter/fighter_runtime.gd")
@export var profile: Resource = Profile.new()
var runtime = Runtime.new()
const CollisionProfile = preload("res://scripts/core/collision/character_collision_profile.gd")
var _body_definition: Resource = null
var _body_configuration_locked := false
var _body_revision := 0
func validate_body_profile(definition: Resource) -> PackedStringArray:
	var errors := PackedStringArray()
	if not basis.is_equal_approx(Basis.IDENTITY) or (is_inside_tree() and not global_basis.is_equal_approx(Basis.IDENTITY)) or up_direction != Vector3.UP:
		errors.append("movement body requires upright unscaled actor")
	if definition == null: return errors
	if not definition is CollisionProfile:
		errors.append("unsupported collision profile resource")
		return errors
	errors.append_array(definition.validate())
	if definition.generator_version != 1: errors.append("unsupported generator version")
	if not is_equal_approx(definition.body_center.y, definition.body_height * 0.5):
		errors.append("movement capsule bottom must retain actor foot plane")
	if definition.source_asset != "" or definition.source_sha256 != "":
		if not FileAccess.file_exists(definition.source_asset) or definition.source_sha256.length() != 64 or FileAccess.get_sha256(definition.source_asset) != definition.source_sha256:
			errors.append("missing or stale collision source")
	return errors
func configure_body_profile(definition: Resource) -> bool:
	if _body_configuration_locked or not validate_body_profile(definition).is_empty(): return false
	_commit_body_profile(definition)
	return true
func _commit_body_profile(definition: Resource) -> void:
	# Internal match full-reset seam; validate the entire batch before cleanup.
	_body_definition = definition.duplicate(true) if definition != null else null
	_body_revision += 1
	if is_node_ready(): _install_body_geometry()
	clear_body_contacts()
func body_profile_snapshot() -> Dictionary:
	return {"character_id": _body_definition.character_id if _body_definition != null else "compatibility",
		"revision": _body_revision, "radius": _body_definition.body_radius if _body_definition != null else 0.4,
		"height": _body_definition.body_height if _body_definition != null else 1.8,
		"source_sha256": _body_definition.source_sha256 if _body_definition != null else ""}
func lock_body_configuration() -> void:
	_body_configuration_locked = true
func _install_body_geometry() -> void:
	var collider: CollisionShape3D = get_node("CoreCapsule")
	var capsule := CapsuleShape3D.new()
	capsule.radius = _body_definition.body_radius if _body_definition != null else 0.4
	capsule.height = _body_definition.body_height if _body_definition != null else 1.8
	collider.shape = capsule
	collider.position = _body_definition.body_center if _body_definition != null else Vector3(0, 0.9, 0)
var _last_physics_tick: int = -1
var _body_contacts := false
var _contacts_valid := false
var _head_slip_direction := 0.0
func set_body_contacts(enabled: bool) -> void:
	_body_contacts = enabled
	collision_mask = 3 if enabled else 1
	clear_body_contacts()
func clear_body_contacts() -> void:
	_contacts_valid = false
	_head_slip_direction = 0.0
func _above_body_support(body: Node3D) -> bool:
	var own: CollisionShape3D = get_node("CoreCapsule")
	var other: CollisionShape3D = body.get_node_or_null("CoreCapsule")
	if other == null or not other.shape is CapsuleShape3D: return false
	# Preserve the accepted 0.7 threshold for compatibility capsules. For other
	# bodies compare actual centers against 70% of the combined half-spines.
	var half_spines: float = (own.shape.height + other.shape.height) * 0.5 - own.shape.radius - other.shape.radius
	return own.global_position.y > other.global_position.y + 0.7 * half_spines
func _apply_head_slip() -> void:
	if not _body_contacts or not _contacts_valid or runtime.grounded or velocity.y > 0 or runtime.states.status in ["caught", "frozen", "disabled"]:
		_head_slip_direction = 0
		return
	var support: Node3D
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		for j in contact.get_collision_count():
			var body = contact.get_collider(j)
			if is_instance_valid(body) and body.is_in_group("core_fighters") and body.collision_layer != 0 and not body in get_collision_exceptions() and contact.get_normal(j).y > 0.1 and _above_body_support(body):
				support = body
	# On the narrower core capsule, a wall-only slide can hide the head
	# subcontact for one tick. Revalidate support with a nonmoving native probe.
	if not is_instance_valid(support) and _head_slip_direction != 0:
		var probe := KinematicCollision3D.new()
		if test_move(global_transform, Vector3(0, -0.08, 0), probe):
			for j in probe.get_collision_count():
				var body = probe.get_collider(j)
				if is_instance_valid(body) and body.is_in_group("core_fighters") and probe.get_normal(j).y > 0.1 and _above_body_support(body): support = body
	if not is_instance_valid(support):
		_head_slip_direction = 0
		return
	if _head_slip_direction == 0:
		var offset: float = get_node("CoreCapsule").global_position.x - support.get_node("CoreCapsule").global_position.x
		_head_slip_direction = signf(offset) if absf(offset) > 0.01 else 1.0
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		for j in contact.get_collision_count():
			if contact.get_normal(j).x * _head_slip_direction < -0.7:
				_head_slip_direction *= -1
				break
	if absf(velocity.x) < 1.5: velocity.x = _head_slip_direction * 1.5
var _support: CollisionObject3D
var _dropping: CollisionObject3D
func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("core_fighters")
	floor_snap_length = 0.08
	floor_stop_on_slope = true
	var collider := CollisionShape3D.new()
	collider.name = "CoreCapsule"
	add_child(collider)
	_install_body_geometry()
	runtime = Runtime.new(profile)
	runtime.reset(false)
func simulate(commands: Dictionary) -> void:
	lock_body_configuration()
	var physics_tick: int = Engine.get_physics_frames()
	if physics_tick == _last_physics_tick: return
	assert(Engine.physics_ticks_per_second == 60, "Core movement requires 60Hz physics")
	_last_physics_tick = physics_tick
	var intent := commands.duplicate()
	# Accepted jump wins over drop. Shield/landing locks reject platform drops.
	if commands.get("down", false) and runtime.grounded and runtime.states.movement_allowed() and not commands.get("shield", false) and not (commands.get("jump", false) and can_accept_jump()) and is_instance_valid(_support) and _support.is_in_group("core_pass_through"):
		_dropping = _support
		runtime.reconcile_contact(false, Vector3(runtime.velocity.x, -0.5, 0))
		intent["down"] = false
	runtime.step(intent)
	velocity = runtime.velocity
	if not commands.get("ledge_hold", false):
		_apply_head_slip()
		if commands.has("body_overlap_direction") and runtime.states.status == "normal" and not commands.has("defense_velocity") and not runtime.recovery_motion and absf(velocity.x) < 1.5:
			velocity.x = float(commands.body_overlap_direction) * 1.5
	_update_platform_exceptions()
	# A small downward probe preserves contact when policy requests zero vertical speed.
	if runtime.grounded and velocity.y <= 0 and runtime.states.status != "caught": velocity.y = -0.5
	velocity.z = 0
	move_and_slide()
	_contacts_valid = true
	position.z = 0
	var terrain_floor := false
	_support = null
	if is_on_floor():
		for i in range(get_slide_collision_count()):
			var contact := get_slide_collision(i)
			for j in contact.get_collision_count():
				var body = contact.get_collider(j)
				if body is CollisionObject3D and not body.is_in_group("core_fighters") and (body.collision_layer & 1) != 0 and contact.get_normal(j).dot(Vector3.UP) >= cos(floor_max_angle):
					_support = body
					terrain_floor = true
	runtime.reconcile_contact(terrain_floor, velocity)
func has_terrain_support() -> bool:
	if not runtime.grounded or not is_instance_valid(_support): return false
	var probe := KinematicCollision3D.new()
	if not test_move(global_transform,Vector3(0,-0.08,0),probe): return false
	for j in probe.get_collision_count():
		var body = probe.get_collider(j)
		if body is CollisionObject3D and not body.is_in_group("core_fighters") and (body.collision_layer & 1) != 0 and probe.get_normal(j).dot(Vector3.UP) >= cos(floor_max_angle): return true
	return false
func apply_ground_jostle(amount: float) -> float:
	# Horizontal native sweep only. Never slide along a wall/capsule or change vx.
	if not is_finite(amount) or runtime.states.status != "normal" or not has_terrain_support(): return 0.0
	var motion := Vector3(clampf(amount,-0.25,0.25),0,0)
	var collision := KinematicCollision3D.new()
	if test_move(global_transform,motion,collision): motion.x = collision.get_travel().x
	var before := global_position.x
	global_position.x += motion.x
	if not has_terrain_support():
		_support = null
		runtime.reconcile_contact(false,velocity)
	return global_position.x-before
func apply_fighter_top_support(plane: float, direction: float) -> bool:
	# Correction is authorized only by match relative crossing. Actual core sweeps
	# terrain, not a newly added full solid head. Never manufacture floor contact.
	if runtime.states.status != "normal" or runtime.grounded: return false
	var motion := Vector3(0, plane - global_position.y, 0)
	var old_mask := collision_mask
	collision_mask = 1
	var blocked := test_move(global_transform, motion) if not motion.is_zero_approx() else false
	if not blocked and not motion.is_zero_approx(): move_and_collide(motion)
	collision_mask = old_mask
	if blocked: return false
	velocity.y = 0
	if absf(velocity.x) < 1.5: velocity.x = direction * 1.5
	runtime.reconcile_contact(false, velocity)
	return true
func retract_blocked_fighter_lift(previous_y: float) -> void:
	# A rejected rider lift must not leave the carrier's exempted upward step
	# inside the rider. Retract only this tick's upward travel, with terrain
	# collision still authoritative; never change horizontal position or warp.
	var motion := Vector3(0, minf(0, previous_y-global_position.y), 0)
	var old_mask := collision_mask
	collision_mask = 1
	if not motion.is_zero_approx(): move_and_collide(motion)
	collision_mask = old_mask
	velocity.y = minf(velocity.y,0)
	runtime.reconcile_contact(runtime.grounded,velocity)
func _update_platform_exceptions() -> void:
	for node in get_tree().get_nodes_in_group("core_pass_through"):
		if not node is CollisionObject3D or not node.has_meta("top_y"): continue
		var top: float = float(node.get_meta("top_y"))
		# Foot-origin comparison is essential: capsule center would snag undersides.
		var ignore: bool = velocity.y > 0 or global_position.y < top - 0.04 or node == _dropping
		if ignore: add_collision_exception_with(node)
		else: remove_collision_exception_with(node)
		if node == _dropping and global_position.y < top - 0.1: _dropping = null
func apply_ledge_path(points: Array) -> void:
	# Match validated every complete capsule segment against unchanged terrain.
	# Apply each waypoint, never replace the elbow route with a diagonal warp.
	for point in points:
		var motion: Vector3 = point - global_position
		if motion.length_squared() > 0.00000001:
			move_and_collide(motion)
			assert(global_position.distance_to(point) < 0.005, "Validated ledge path changed during atomic commit")
	velocity = Vector3.ZERO
	runtime.velocity = Vector3.ZERO
	runtime.reconcile_contact(false, Vector3.ZERO)
func cancel_for_grab() -> void:
	clear_body_contacts()
	_dropping = null
	runtime.cancel_for_grab()
	velocity = runtime.velocity
func apply_combat_launch(launch: Vector3, stun_ticks: int) -> void:
	runtime.apply_combat_launch(launch, stun_ticks)
	velocity = runtime.velocity
func can_accept_jump() -> bool:
	return runtime.can_accept_jump()
func reset_at(at: Vector3) -> void:
	clear_body_contacts()
	for body in get_collision_exceptions():
		if is_instance_valid(body): remove_collision_exception_with(body)
	_support = null
	_dropping = null
	global_position = Vector3(at.x, at.y, 0)
	velocity = Vector3.ZERO
	runtime = Runtime.new(profile)
	runtime.reset(false)
	_last_physics_tick = -1
func telemetry() -> Dictionary:
	return {"locomotion": runtime.states.locomotion, "action": runtime.states.action,
		"status": runtime.states.status, "velocity": velocity, "grounded": runtime.grounded,
		"air_jumps_left": runtime.air_jumps_left, "transition_reason": runtime.states.transition_reason,
		"tick": runtime.tick, "trace": runtime.states.trace.duplicate(true)}

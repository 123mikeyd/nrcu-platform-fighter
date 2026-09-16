extends "res://scripts/fighter.gd"
# Encounter-only health fighter. Ordinary roster fighters retain stocks/percent.
const MAX_HEALTH := 400.0 # Provisional first-encounter tuning.
var health := MAX_HEALTH
var reaction_serial := 0
var thrust_active := false
var thrust_elapsed := 0.0
var thrust_facing := 1.0
var thrust_targets: Array = [[], []]
var thrust_serial := 0
var diagnostic_control := false
var _thrust_key_down := false
var thrust_rest := 0.8
func begin_thrust_slash(direction: float) -> bool:
    if thrust_active or thrust_rest > 0 or not controls_enabled or health <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return false
    thrust_active = true
    thrust_elapsed = 0
    thrust_facing = signf(direction) if direction != 0 else facing
    facing = thrust_facing
    thrust_targets = [[], []]
    thrust_serial += 1
    _visual_root.get_node("BoboVisual").react("ThrustSlash")
    return true
# Deliberate slow anticipation only: first .6 native seconds take 1.2s.
# All later source motion runs at authored speed. Hold final pose .8s.
const THRUST_DURATION := 4.4
func thrust_source_time() -> float:
    return clampf(thrust_elapsed * 0.5 if thrust_elapsed <= 1.2 else thrust_elapsed - 0.6, 0, 3)
func cancel_thrust_slash() -> void:
    thrust_active = false
    thrust_elapsed = 0
    thrust_targets = [[], []]
    thrust_rest = 1.0
    _thrust_key_down = Input.is_key_pressed(KEY_F)
    if _visual_root:
        var v = _visual_root.get_node_or_null("BoboVisual")
        if v and v.current_clip == "ThrustSlash": v.react("Idle")
func cancel_magic() -> void:
    cancel_thrust_slash()
    super.cancel_magic()
func cancel_for_grab() -> void:
    cancel_thrust_slash()
    super.cancel_for_grab()
func tick_thrust_slash(delta: float) -> void:
    if not thrust_active: return
    if not controls_enabled or health <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked():
        cancel_thrust_slash()
        return
    thrust_elapsed += delta
    var v = _visual_root.get_node("BoboVisual")
    v.seek_thrust(thrust_source_time())
    if thrust_elapsed >= THRUST_DURATION: cancel_thrust_slash()
func _ready() -> void:
    character_id = "bobo"
    fighter_name = "Bobo"
    super._ready()
func _build_visuals() -> void:
    super._build_visuals()
    for child in _visual_root.get_children():
        _visual_root.remove_child(child)
        child.queue_free()
    var visual = load("res://scripts/bobo_visual.gd").new()
    visual.name = "BoboVisual"
    _visual_root.add_child(visual)
    get_node("PlayerLabel").text = "BOBO"
    get_node("PlayerLabel").position.y = 3.2
func _input(event: InputEvent) -> void:
    # Observe (never consume) diagnostic key edges even while menu physics stops.
    if diagnostic_control and event is InputEventKey and event.keycode == KEY_F and not controls_enabled:
        _thrust_key_down = event.pressed
func read_controls(_delta: float) -> Dictionary:
    return {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false, "shield": false}
var thrust_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bobo/thrust_slash.json"))
func can_hit(target: Node) -> bool:
    return controls_enabled and health > 0 and super.can_hit(target)
func thrust_bone_transform(hit: int) -> Transform3D:
    var v = _visual_root.get_node("BoboVisual")
    v.model.rotation.y = thrust_facing * PI / 2
    v.seek_thrust(thrust_source_time())
    var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
    return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(str(thrust_manifest.hits[hit].bone)))
func thrust_claw_center(hit: int) -> Vector3:
    var p: Array = thrust_manifest.hits[hit].centroid
    return thrust_bone_transform(hit) * Vector3(p[0], p[1], p[2])
func query_thrust_contacts() -> void:
    if not thrust_active or not controls_enabled or health <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return
    for hit in 2:
        var event: Dictionary = thrust_manifest.hits[hit]
        if thrust_elapsed + 0.000001 < float(event.active_start) or thrust_elapsed > float(event.active_end) + 0.000001: continue
        var transform := thrust_bone_transform(hit)
        var points := PackedVector3Array()
        # Bake the .01 rig and 1.75 presentation scale into hull vertices;
        # physics receives an unscaled transform, not an unsupported scaled hull.
        for p in event.hull_points:
            points.append(transform * Vector3(p[0], p[1], p[2]) - global_position)
        var shape := ConvexPolygonShape3D.new()
        shape.points = points
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape = shape
        query.transform = Transform3D(Basis.IDENTITY, global_position)
        query.collision_mask = 1 | 4
        query.exclude = [get_rid()]
        query.margin = 0
        preload("res://scripts/body_hurtboxes.gd").prepare(self, query)
        var space = get_world_3d().direct_space_state
        var hits = space.intersect_shape(query, 32)
        for result in hits:
            var target = preload("res://scripts/body_hurtboxes.gd").resolve(result.collider)
            if not can_hit(target) or target in thrust_targets[hit]: continue
            if (target.global_position.x - global_position.x) * thrust_facing <= 0: continue
            thrust_targets[hit].append(target)
            var contact = preload("res://scripts/body_hurtboxes.gd").shape_contact(space,query,result,hits)
            preload("res://scripts/body_hurtboxes.gd").deliver(target,float(event.damage), Vector3(thrust_facing,0,0), float(event.knockback),contact)
            # Light setup contact: retains damage, shield and hitstun, avoids
            # shared percent-derived launch defeating the second slow swipe.
            if hit == 0: target.velocity = target.velocity.limit_length(0.15)
func basic_attack(aim: Vector2, airborne: bool) -> void:
    if airborne or absf(aim.x) < 0.5 or absf(aim.y) > 0.5: return
    begin_thrust_slash(aim.x)
func start_special(_aim: Vector2) -> void: pass
func release_special() -> void: pass
func try_jump() -> bool: return false
func receive_hit(amount: float, direction: Vector3, base_knockback: float) -> void:
    if health <= 0 or not controls_enabled or amount < 0: return
    var blocked := shielding
    super.receive_hit(amount, direction, base_knockback)
    health = clampf(health - amount * (0.35 if blocked else 1.0), 0, MAX_HEALTH)
    damage_percent = 0
    velocity = Vector3.ZERO
    hitstun = 0.25 if amount > 0 else 0.0
    if amount > 0:
        reaction_serial += 1
        _visual_root.get_node("BoboVisual").react("Block" if blocked else ("Hit" if reaction_serial % 2 else "HitWaist"))
    _finish_health_change()
func apply_status_damage(amount: float) -> void:
    if health <= 0 or not controls_enabled: return
    health = clampf(health - maxf(0,amount),0,MAX_HEALTH)
    _finish_health_change()
func _finish_health_change() -> void:
    if health <= 0:
        stocks = 0
        controls_enabled = false
        _visual_root.get_node("BoboVisual").react("Defeat")
        eliminated.emit(self)
    state_changed.emit()
func _physics_process(delta: float) -> void:
    # Stationary encounter: shared statuses/gravity, isolated attack decisions.
    velocity.x = 0
    super._physics_process(delta)
    global_position.x = spawn_position.x
    global_position.z = 0
    velocity.x = 0
    thrust_rest = maxf(0, thrust_rest - delta)
    var down := Input.is_key_pressed(KEY_F) if diagnostic_control else false
    var fresh := down and not _thrust_key_down
    _thrust_key_down = down
    if not controls_enabled or health <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return
    if thrust_active:
        tick_thrust_slash(delta)
        query_thrust_contacts()
    elif thrust_rest <= 0 and is_grounded():
        if diagnostic_control:
            var direction := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
            if fresh and direction != 0: basic_attack(Vector2(direction,0),false)
        else:
            var nearest: Node3D
            var distance := 3.0
            for target in get_tree().get_nodes_in_group("fighters"):
                if can_hit(target) and global_position.distance_to(target.global_position) < distance:
                    nearest = target
                    distance = global_position.distance_to(target.global_position)
            if nearest: begin_thrust_slash(nearest.global_position.x - global_position.x)
func _handle_blast_zone() -> void:
    global_position = spawn_position
    velocity = Vector3.ZERO
func lose_stock() -> void: pass
func reset_fighter(new_spawn: Vector3, reset_stocks := false) -> void:
    cancel_thrust_slash()
    health = MAX_HEALTH
    reaction_serial = 0
    super.reset_fighter(new_spawn, reset_stocks)
    _visual_root.get_node("BoboVisual").react("Idle")
func _update_move_visuals(delta := 0.0, interrupted := false) -> void:
    super._update_move_visuals(delta, interrupted)
    if not _visual_root: return
    var visual = _visual_root.get_node_or_null("BoboVisual")
    if not visual: return
    _visual_root.scale = Vector3.ONE
    visual.model.rotation.y = (thrust_facing if thrust_active else facing) * PI / 2
    if freeze_remaining > 0 or is_instance_valid(caught_by): return
    if thrust_active:
        visual.seek_thrust(thrust_source_time())
        return
    if interrupted and health > 0: visual.react("Idle")
    visual.tick(delta)

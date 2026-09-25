extends "res://scripts/fighter.gd"
# Freeplay foundation, deliberately NOT a subclass of stationary health Bobo.
# Approved Orc Walk and normal jump phases use a separate player-only visual.
var motion_origin := Vector3.ZERO
func ground_speed_multiplier() -> float:
    var inherited := super.ground_speed_multiplier()
    if not is_grounded(): return inherited
    if is_instance_valid(_visual_root):
        var v = _visual_root.get_node_or_null("BoboVisual")
        if v and (v.landing >= 0 or v.airborne): return 0.0
    # Median sole stance regression from approved 5.5s gait, scaled by 1.75.
    return inherited * 0.4925375339290258 / MOVE_SPEED
func _ready() -> void:
    character_id = "bobo"
    fighter_name = "BOBO (PROTOTYPE)"
    super._ready()
func _build_visuals() -> void:
    super._build_visuals()
    for child in _visual_root.get_children():
        _visual_root.remove_child(child)
        child.queue_free()
    var visual = load("res://scripts/bobo_player_visual.gd").new()
    visual.name = "BoboVisual"
    _visual_root.add_child(visual)
    get_node("PlayerLabel").position.y = 3.2
func _update_move_visuals(delta := 0.0, interrupted := false) -> void:
    super._update_move_visuals(delta, interrupted)
    if not _visual_root: return
    var visual = _visual_root.get_node_or_null("BoboVisual")
    if not visual: return
    _visual_root.scale = Vector3.ONE
    if freeze_remaining <= 0:
        visual.model.rotation.y = (thrust_facing if thrust_active else facing) * PI / 2
    if interrupted or not controls_enabled or stocks <= 0:
        visual.cancel_locomotion()
        visual.react("Idle")
        return
    if freeze_remaining > 0 or is_instance_valid(caught_by) or hitstun > 0 or (tumble and tumble.active):
        visual.cancel_locomotion()
        return
    if fitted_reaction and fitted_reaction.active:
        visual.cancel_locomotion()
        return
    if not special_move.is_empty():
        present_bobo_special()
        return
    if down_a_active:
        present_down_a()
        return
    if thrust_active:
        visual.cancel_locomotion()
        visual.seek_thrust(thrust_source_time())
        return
    if visual.present_crouch(self,delta): return
    visual.locomotion(self, delta)
# Player-only prototype specials: a single native source clock owns presentation.
var special_move := ""
var special_time := 0.0
var special_facing := 1.0
var special_power := 0.0
var special_fired := false
var special_serial := 0
var special_shots: Array = []
var special_effect
var special_targets: Array = []
var special_nozzles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/bobo/special_nozzles.json"))
func reset_air_resources() -> void:
    if special_move == "up": return
    super.reset_air_resources()
func special_allowed() -> bool:
    return controls_enabled and stocks > 0 and hitstun <= 0 and freeze_remaining <= 0 and not magic_locked() and not (tumble and tumble.active) and (not revival or revival.phase == "idle")
func start_special(aim: Vector2) -> void:
    if not special_allowed() or not special_move.is_empty() or thrust_active or down_a_active or attack_cooldown > 0 or landing_lag > 0 or counter_hitstop > 0: return
    if aim.y > 0.1: return # No invented Down-B.
    if aim.y < -0.1:
        if recovery_spent: return
        recovery_spent = true
        jumps_used = 2
        special_move = "up"
    elif absf(aim.x) > 0.1:
        special_move = "side"
        facing = signf(aim.x)
    else: special_move = "neutral_charge"
    special_time = 0
    special_facing = facing
    special_fired = false
    special_serial += 1
    charging = special_move == "neutral_charge"
    charge_time = 0
    velocity.x = 0
    special_targets.clear()
    if not special_effect:
        special_effect = load("res://scripts/bobo_thruster_effect.gd").new()
        add_child(special_effect)
    _cancel_locomotion_episode()
    last_move = "CLAW BLAST — HOLD / RELEASE"
func release_special() -> void:
    if special_move != "neutral_charge": return
    special_power = clampf(charge_time / MAX_CHARGE_TIME,0,1)
    charging = false
    charge_time = 0
    special_move = "neutral_release"
    # Queue release without skipping native anticipation on a short tap.
    # Full holds pause at frame49; both paths continue through frame59 discharge.
func cancel_bobo_special(clear_shots := true) -> void:
    if not special_move.is_empty(): attack_cooldown = 0
    special_move = ""
    special_time = 0
    charging = false
    charge_time = 0
    if clear_shots:
        for shot in special_shots:
            if is_instance_valid(shot) and shot.source == self: shot.queue_free()
        special_shots.clear()
    if special_effect: special_effect.hide()
func _tick_character_move(delta: float) -> void:
    super._tick_character_move(delta)
    if special_move.is_empty(): return
    if not special_allowed():
        cancel_bobo_special()
        return
    special_time += delta
    facing = special_facing
    velocity.x = 0
    attack_cooldown = 0.05
    if special_move == "up" and special_time >= 17.0/30.0 and special_time < 63.0/30.0:
        velocity.y = 3.7
    if special_move == "side" and special_time >= 18.0/30.0 and special_time < 41.0/30.0:
        velocity.x = special_facing * 7.0
    if special_move == "neutral_charge": special_time = minf(special_time,48.0/30.0)
    if special_move == "neutral_release" and special_time >= 58.0/30.0 and not special_fired:
        present_bobo_special()
        special_fired = true
        var shot = load("res://scripts/bobo_charge_shot.gd").new()
        shot.source = self
        shot.direction = special_facing
        shot.power = special_power
        get_parent().add_child(shot)
        shot.global_position = special_hand_world("LeftHand")
        special_shots.append(shot)
    if special_time >= (77.0/30.0 if special_move == "side" else 95.0/30.0): cancel_bobo_special(false)
func special_hand_world(bone: String) -> Vector3:
    var v = _visual_root.get_node("BoboVisual")
    var sk: Skeleton3D = v.model.find_children("*","Skeleton3D",true,false)[0]
    var mode:String=special_move if special_move in ["up","side"] else "neutral"
    var point:Array=special_nozzles[mode][bone]
    return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)) * Vector3(point[0],point[1],point[2])
func present_bobo_special() -> void:
    var v = _visual_root.get_node("BoboVisual")
    v.model.rotation.y = special_facing * PI/2
    if special_move == "up":
        v.model.rotation.y += TAU * clampf((special_time-17.0/30.0)/(46.0/30.0),0,1)
    v.pose_at("ThrusterUp" if special_move == "up" else "RocketSide" if special_move == "side" else "ChargeBlast",special_time)
    if special_effect: special_effect.present(self)

# v003 player-only low leading-claw attack; source timing and native painted rig.
const DOWN_A_DURATION := 89.0/30.0
var down_a_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bobo/down_a_v003.json"))
var down_a_active := false
var down_a_elapsed := 0.0
var down_a_facing := 1.0
var down_a_serial := 0
var down_a_targets: Array = []
func down_a_allowed() -> bool:
    return controls_enabled and stocks > 0 and is_grounded() and hitstun <= 0 and freeze_remaining <= 0 and not magic_locked() and not (tumble and tumble.active) and (not revival or revival.phase == "idle")
func begin_down_a() -> bool:
    if not down_a_allowed() or down_a_active or thrust_active or attack_cooldown > 0 or counter_hitstop > 0 or landing_lag > 0: return false
    var v = _visual_root.get_node("BoboVisual")
    # If pressed directly from standing, finish the approved crouch entry first.
    var entry: float = maxf(0,37.0/30.0-v.crouch_time)
    v.cancel_locomotion()
    down_a_elapsed = -entry
    down_a_active = true
    down_a_facing = facing
    down_a_serial += 1
    down_a_targets.clear()
    velocity.x = 0
    attack_cooldown = DOWN_A_DURATION + entry
    last_move = "LOW CLAW"
    present_down_a()
    return true
func present_down_a() -> void:
    var v = _visual_root.get_node("BoboVisual")
    facing = down_a_facing
    v.model.rotation.y = facing*PI/2
    if down_a_elapsed < 0:
        v.pose_at("TuckedCrouch",37.0/30.0+down_a_elapsed)
    else:
        v.pose_at("DownA",minf(down_a_elapsed,DOWN_A_DURATION))
func cancel_down_a() -> void:
    if not down_a_active: return
    down_a_active = false
    down_a_elapsed = 0.0
    down_a_targets.clear()
    attack_cooldown = 0.0
func tick_down_a(delta: float) -> void:
    if not down_a_active: return
    if not down_a_allowed():
        cancel_down_a()
        return
    if counter_hitstop > 0: return
    var start := down_a_elapsed
    var end := start+delta
    var lo := maxf(start,float(down_a_manifest.active_start))
    var hi := minf(end,float(down_a_manifest.active_end))
    if hi >= lo:
        var steps := maxi(1,ceili((hi-lo)*240.0))
        for step in range(steps+1):
            down_a_elapsed = lerpf(lo,hi,float(step)/steps)
            present_down_a()
            query_down_a_contact()
            if not down_a_active: return
    down_a_elapsed = end
    present_down_a()
    if end >= DOWN_A_DURATION:
        cancel_down_a()
        var v = _visual_root.get_node("BoboVisual")
        v.crouch_time = 37.0/30.0
        v.crouch_exit = -1.0
        v.present_crouch(self,0)
func query_down_a_contact() -> void:
    if not down_a_active or not down_a_allowed() or counter_hitstop > 0: return
    if down_a_elapsed < float(down_a_manifest.active_start)-0.000001 or down_a_elapsed > float(down_a_manifest.active_end)+0.000001: return
    var v = _visual_root.get_node("BoboVisual")
    var sk: Skeleton3D = v.model.find_children("*","Skeleton3D",true,false)[0]
    var transform: Transform3D = sk.global_transform*sk.get_bone_global_pose(sk.find_bone(str(down_a_manifest.bone)))
    var points := PackedVector3Array()
    for p in down_a_manifest.hull_points: points.append(transform*Vector3(p[0],p[1],p[2])-global_position)
    var shape := ConvexPolygonShape3D.new()
    shape.points = points
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    query.transform = Transform3D(Basis.IDENTITY,global_position)
    query.collision_mask = 1 | 4
    query.exclude = [get_rid()]
    query.margin = 0
    var hurt = preload("res://scripts/body_hurtboxes.gd")
    hurt.prepare(self,query)
    var space = get_world_3d().direct_space_state
    var hits = space.intersect_shape(query,32)
    for result in hits:
        var target = hurt.resolve(result.collider)
        if not can_hit(target) or target in down_a_targets: continue
        if (target.global_position.x-global_position.x)*down_a_facing <= 0: continue
        down_a_targets.append(target)
        var contact = hurt.shape_contact(space,query,result,hits)
        hurt.deliver(target,float(down_a_manifest.damage),Vector3(down_a_facing,0,0),float(down_a_manifest.knockback),contact,self)

# Original timing map and hand-weighted hulls come from the approved Story implementation.
# Keep separate from encounter policy: health, AI, stationarity and no-jump never migrate.
var thrust_active := false
var thrust_elapsed := 0.0
var thrust_sample_elapsed := 0.0
var thrust_facing := 1.0
var thrust_targets: Array = [[], []]
var thrust_serial := 0
var thrust_rest := 0.0
func begin_thrust_slash(direction: float) -> bool:
    if thrust_active or thrust_rest > 0 or not controls_enabled or stocks <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return false
    if attack_cooldown > 0 or not is_grounded() or (tumble and tumble.active): return false
    if revival and not revival.permit_attack(): return false
    thrust_active = true
    thrust_elapsed = 0
    thrust_sample_elapsed = 0.0
    thrust_facing = signf(direction) if direction != 0 else facing
    facing = thrust_facing
    thrust_targets = [[], []]
    thrust_serial += 1
    velocity.x = 0
    attack_cooldown = THRUST_DURATION
    last_move = "TWO-HIT CLAWS"
    _visual_root.get_node("BoboVisual").react("ThrustSlash")
    return true
# Approved player-only 2x: uniformly compress anticipation, both strikes and recovery.
# Map once into the original 4.4s clock for both source poses and manifest contacts.
const THRUST_SPEED := 2.0
const THRUST_DURATION := 4.4 / THRUST_SPEED
func thrust_timing_time() -> float:
    return thrust_elapsed * THRUST_SPEED
func thrust_source_time() -> float:
    var time := thrust_timing_time()
    return clampf(time * 0.5 if time <= 1.2 else time - 0.6, 0, 3)
func cancel_thrust_slash() -> void:
    thrust_active = false
    thrust_elapsed = 0
    thrust_sample_elapsed = 0.0
    thrust_targets = [[], []]
    thrust_rest = 1.0
    attack_cooldown = 0
    if _visual_root:
        var v = _visual_root.get_node_or_null("BoboVisual")
        if v and v.current_clip == "ThrustSlash": v.react("Idle")
func _cancel_locomotion_episode() -> void:
    if is_instance_valid(_visual_root):
        var v = _visual_root.get_node_or_null("BoboVisual")
        if v: v.cancel_locomotion()
func cancel_magic() -> void:
    cancel_bobo_special()
    cancel_down_a()
    _cancel_locomotion_episode()
    cancel_thrust_slash()
    super.cancel_magic()
func cancel_for_grab() -> void:
    cancel_bobo_special()
    cancel_down_a()
    _cancel_locomotion_episode()
    cancel_thrust_slash()
    super.cancel_for_grab()
func tick_thrust_slash(delta: float) -> void:
    if not thrust_active: return
    if not controls_enabled or stocks <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked() or not is_grounded():
        cancel_thrust_slash()
        return
    thrust_elapsed += delta
    var v = _visual_root.get_node("BoboVisual")
    v.seek_thrust(thrust_source_time())
    if thrust_elapsed >= THRUST_DURATION:
        cancel_thrust_slash()
        # The complete native recovery and endpoint hold have already played.
        # Do not append the Story-style invisible rest to a completed player move.
        thrust_rest = 0.0
var thrust_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bobo/thrust_slash.json"))
func can_hit(target: Node) -> bool:
    return controls_enabled and stocks > 0 and super.can_hit(target)
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
    if not thrust_active or not controls_enabled or stocks <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return
    var end := thrust_elapsed
    var start := minf(thrust_sample_elapsed, end)
    thrust_sample_elapsed = end
    var overlaps_window := false
    for event in thrust_manifest.hits:
        if end * THRUST_SPEED >= float(event.active_start) and start * THRUST_SPEED <= float(event.active_end):
            overlaps_window = true
    if not overlaps_window: return
    # Sample the unchanged native claw hull along the actual pose path. At 2x,
    # 60Hz endpoints can jump over a receiver between the two source poses.
    # Bound the original-clock spacing to 1/240s (eight samples at 60Hz/2x).
    var steps := maxi(1, ceili((end - start) * THRUST_SPEED * 240.0 - 0.00001))
    for step in range(steps + 1):
        thrust_elapsed = lerpf(start, end, float(step) / steps)
        _query_thrust_pose_contacts()
        if not thrust_active: return
    thrust_elapsed = end
    # Queries must never leave the renderer on an intermediate collision pose.
    _visual_root.get_node("BoboVisual").seek_thrust(thrust_source_time())
func _query_thrust_pose_contacts() -> void:
    if not thrust_active or not controls_enabled or stocks <= 0 or hitstun > 0 or freeze_remaining > 0 or magic_locked(): return
    var time := thrust_timing_time()
    for hit in 2:
        var event: Dictionary = thrust_manifest.hits[hit]
        if time + 0.000001 < float(event.active_start) or time > float(event.active_end) + 0.000001: continue
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
            preload("res://scripts/body_hurtboxes.gd").deliver(target,float(event.damage), Vector3(thrust_facing,0,0), float(event.knockback),contact, self)
            # Light setup contact: retains damage, shield and hitstun, avoids
            # shared percent-derived launch defeating the second slow swipe.
            if hit == 0:
                target.velocity = target.velocity.limit_length(0.15)
                # Keep this deliberately light setup swipe out of strong flight.
                if target.tumble: target.tumble.clear()
func basic_attack(aim: Vector2, airborne: bool) -> void:
    if not special_move.is_empty(): return
    if not airborne and aim.y > 0.5:
        begin_down_a()
        return
    if down_a_active: return
    if airborne or absf(aim.x) < 0.5 or absf(aim.y) > 0.5: return
    begin_thrust_slash(aim.x)

func read_controls(delta: float) -> Dictionary:
    var input = super.read_controls(delta)
    if thrust_active or down_a_active or not special_move.is_empty():
        # Preserve attack/special edges while rejecting movement during commitment.
        for action in ["left", "right", "up", "down", "jump"]:
            input[action] = false
    return input
func try_jump() -> bool:
    if thrust_active or down_a_active or not special_move.is_empty(): return false
    var accepted := super.try_jump()
    if accepted: _visual_root.get_node("BoboVisual").begin_jump()
    return accepted
func _physics_process(delta: float) -> void:
    if not special_allowed(): cancel_bobo_special()
    var paused_down_a := counter_hitstop > 0
    if down_a_active and not down_a_allowed(): cancel_down_a()
    motion_origin=global_position
    if is_grounded() and not thrust_active and hitstun<=0 and freeze_remaining<=0:
        var v = _visual_root.get_node_or_null("BoboVisual") if _visual_root else null
        if v and (v.landing>=0 or v.airborne):velocity.x=0.0
    if not controls_enabled:
        var raw = _read_raw_controls(0)
        _attack_was_down = raw.attack
        _special_was_down = raw.special
        _jump_was_down = raw.jump or raw.up
    if thrust_active or down_a_active: velocity.x = 0
    super._physics_process(delta)
    if not special_move.is_empty() and special_effect and not paused_down_a:
        special_effect.contact(self)
    if down_a_active and not paused_down_a:
        tick_down_a(delta)
    thrust_rest = maxf(0, thrust_rest - delta)
    if thrust_active:
        facing = thrust_facing
        tick_thrust_slash(delta)
        query_thrust_contacts()

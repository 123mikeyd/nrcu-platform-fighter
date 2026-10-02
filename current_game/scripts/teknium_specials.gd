extends Node
# Tek-only kit. Fighter retains input edges and all controller displacement.
var actor
var grenade
var stored_charge := 0.0
var phase := "idle"
var elapsed := 0.0
var burst_direction := Vector3.UP
var previous := Vector3.ZERO
var targets: Array = []
var ghosts: Array = []
var ghost_clock := 0.0
const HURT = preload("res://scripts/body_hurtboxes.gd")
var cue: Node3D
func _ready():
    actor = get_parent()
    cue = Node3D.new(); cue.name="HolyTechCue"; add_child(cue)
    for i in 2:
        var mesh := MeshInstance3D.new(); var ring := TorusMesh.new()
        ring.inner_radius=0.55; ring.outer_radius=0.62; mesh.mesh=ring
        mesh.rotation.x=PI/2; mesh.rotation.z=i*PI/2
        var mat := StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color=Color(0.2,1,0.35) if i==0 else Color(1,0.75,0.18)
        mesh.material_override=mat; cue.add_child(mesh)
    cue.hide()
func start(aim: Vector2) -> void:
    if phase != "idle": return
    if aim.y < -0.1:
        if actor.recovery_spent: return
        actor.recovery_spent = true
        actor.jumps_used = 2
        phase = "rise_charge"
        elapsed = 0
        targets.clear()
        burst_direction = Vector3(aim.x,-aim.y,0).normalized()
        actor.velocity = Vector3.ZERO
        actor.attack_cooldown = 0.95
        actor.last_move = "HOLY IGNITION"
    elif aim.y > 0.1:
        if is_instance_valid(grenade):
            grenade.detonate()
            grenade = null
            actor.last_move = "REMOTE DETONATION"
        else:
            grenade = preload("res://scripts/teknium_holy_grenade.gd").new()
            grenade.source = actor
            actor.get_parent().add_child(grenade)
            grenade.global_position = actor.global_position + Vector3(actor.facing * 0.8,1.4,0)
            grenade.velocity = Vector3(actor.facing * 6.0,5.0,0)
            actor.last_move = "HOLY HAND GRENADE"
        actor.attack_cooldown = 0.35
    elif absf(aim.x) > 0.1:
        phase = "shadow_start"
        elapsed = 0
        targets.clear()
        actor.facing = signf(aim.x)
        burst_direction = Vector3(actor.facing,0,0)
        actor.attack_cooldown = 0.55
        actor.last_move = "SHADOW KICK"
    elif aim == Vector2.ZERO:
        start_laser()
# ---------------- LASER BLAST (neutral special, replaces Charge Shot 2026-09-28) ----------------
# Clip: laser/LaserBlast (24 fps source, 56 frames). Fixed-length telegraph, jump cancels before the
# white flash, hitstop on fire, recoil pushback owned here (ledge-safe on ground, bigger in air).
const LF := 1.0 / 24.0
const L_TELE := 10 * LF
const L_FLASH := 28 * LF
const L_FIRE := 29 * LF
const L_RECOIL := 34 * LF
const L_ACTIVE_END := 35 * LF
const L_END := 48 * LF
const L_CLIP_LEN := 56 * LF
const L_MAX_LEN := 14.0
const L_DAMAGE := 22.0
const L_PUSH := 8.0
const L_GROUND_RECOIL := Vector2(2.4, 0.2)   # speed, seconds -> ~0.48 slide
const L_AIR_RECOIL := Vector2(4.5, 0.28)     # speed, seconds -> ~1.26 shove
const L_LINE_STEPS := [[10, 0.012], [16, 0.02], [21, 0.03], [25, 0.045], [27, 0.06], [28, 0.08]]
const L_PULSES := [10.0, 15.0, 19.0, 22.0, 24.0, 25.5, 26.5, 27.3]
const TEAL := Color(0.05, 0.95, 0.85)
var laser_facing := 1.0
var laser_jump_held := true
var laser_special_held := true
var laser_origin := Vector3.ZERO
var laser_len := L_MAX_LEN
var gun_fade := 0.0
var fx: Dictionary = {}
func _fx_mat(color: Color, alpha := 1.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_color = Color(color, alpha)
    m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.no_depth_test = false
    return m
func _fx_node(name: String, mesh: Mesh, color: Color, alpha := 1.0) -> MeshInstance3D:
    var n := MeshInstance3D.new(); n.name = name; n.mesh = mesh
    n.material_override = _fx_mat(color, alpha); n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    n.top_level = true; add_child(n); n.hide(); return n
func _build_laser_fx() -> void:
    var cyl := CylinderMesh.new(); cyl.top_radius = 0.5; cyl.bottom_radius = 0.5; cyl.height = 1.0; cyl.radial_segments = 16
    fx.line = _fx_node("LaserTelegraph", cyl, TEAL, 0.85)
    fx.core = _fx_node("LaserBeamCore", cyl, Color(0.92, 1, 1), 1.0)
    fx.sheath = _fx_node("LaserBeamSheath", cyl, TEAL, 0.55)
    var ball := SphereMesh.new(); ball.radius = 0.5; ball.height = 1.0
    fx.flash = _fx_node("LaserMuzzleFlash", ball, Color(0.95, 1, 1), 0.95)
    var torus := TorusMesh.new(); torus.inner_radius = 0.9; torus.outer_radius = 1.0
    fx.ring = _fx_node("LaserShockwave", torus, TEAL, 0.9)
func laser_active() -> bool: return phase == "laser"
func start_laser() -> void:
    if fx.is_empty(): _build_laser_fx()
    phase = "laser"
    elapsed = 0.0
    targets.clear()
    laser_facing = actor.facing if absf(actor.facing) > 0.1 else 1.0
    laser_jump_held = true   # a held jump never cancels; it needs a fresh press
    laser_special_held = true   # the press that started the move never cancels it
    gun_fade = 0.0
    laser_len = L_MAX_LEN
    actor.charging = false
    actor.charge_time = 0.0
    actor.last_move = "LASER BLAST"
func _laser_view():
    return actor._visual_root.get_node_or_null("TekniumVisual") if actor._visual_root else null
func _muzzle() -> Vector3:
    var view = _laser_view()
    if view and view.has_method("laser_muzzle"): return view.laser_muzzle()
    return actor.global_position + Vector3(laser_facing * 0.9, 1.55, 0)
func _terrain_len(from: Vector3) -> float:
    var start := Vector3(from.x, from.y, 0)
    var ray := PhysicsRayQueryParameters3D.create(start, start + Vector3(laser_facing * L_MAX_LEN, 0, 0), 1)
    var ex: Array[RID] = []
    for other in actor.get_tree().get_nodes_in_group("fighters"): ex.append(other.get_rid())
    ray.exclude = ex
    var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(ray)
    return L_MAX_LEN if hit.is_empty() else absf(hit.position.x - start.x)
func _ground_ahead(vx: float, delta: float) -> bool:
    # Ledge safety: only slide if there is still floor under the leading foot.
    var ahead: Vector3 = actor.global_position + Vector3(signf(vx) * (absf(vx) * delta + 0.3), 0.4, 0)
    var ray := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3(0, -1.2, 0), 3)
    var ex: Array[RID] = []
    for other in actor.get_tree().get_nodes_in_group("fighters"): ex.append(other.get_rid())
    ray.exclude = ex
    return not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
func _laser_move(delta: float, input: Dictionary) -> void:
    elapsed += delta
    # The fighter suppresses combat taps while a special owns input, so also read the raw key-down ledger.
    var jump_now: bool = input.get("jump", false) or input.get("up", false) or actor._short_down.has("jump") or actor._short_down.has("up")
    var special_now: bool = input.get("special", false) or actor._short_down.has("special")
    if elapsed < L_FLASH and special_now and not laser_special_held:
        # Second out: a fresh special press bails in place (no jump).
        abort_laser()
        actor.attack_cooldown = maxf(actor.attack_cooldown, 0.25)
        return
    laser_special_held = special_now
    if elapsed < L_FLASH and jump_now and not laser_jump_held:
        # The out: bail before the flash. Gun holo-fades, no blast, short recovery.
        abort_laser()
        actor.attack_cooldown = maxf(actor.attack_cooldown, 0.2)
        actor.try_jump()
        return
    laser_jump_held = jump_now
    var grounded: bool = actor.is_grounded()
    if elapsed < L_FIRE:
        if grounded: actor.velocity.x = 0.0
        else:
            actor.velocity.x = move_toward(actor.velocity.x, 0.0, 20.0 * delta)
            actor.velocity.y = move_toward(actor.velocity.y, -1.2, 60.0 * delta)   # slow fall while charging
        if elapsed >= L_TELE: laser_len = _terrain_len(_muzzle())
    elif elapsed < L_RECOIL:
        if laser_origin == Vector3.ZERO or actor.last_move != "LASER FIRE":
            laser_origin = _muzzle(); laser_len = _terrain_len(laser_origin)
            actor.last_move = "LASER FIRE"
        actor.velocity = Vector3.ZERO   # hitstop hold
    else:
        var recoil: Vector2 = L_GROUND_RECOIL if grounded else L_AIR_RECOIL
        if elapsed < L_RECOIL + recoil.y:
            var vx := -laser_facing * recoil.x
            if grounded and not _ground_ahead(vx, delta): vx = 0.0
            actor.velocity.x = vx
        elif grounded:
            actor.velocity.x = 0.0
        else:
            actor.velocity.x = move_toward(actor.velocity.x, 0.0, 8.0 * delta)
        if grounded and actor.velocity.x != 0.0 and not _ground_ahead(actor.velocity.x, delta):
            actor.velocity.x = 0.0
    if elapsed >= L_END:
        _end_laser()
        actor.attack_cooldown = maxf(actor.attack_cooldown, 0.1)
func _laser_hits() -> void:
    if elapsed < L_FIRE or elapsed >= L_ACTIVE_END: return
    var box: BoxShape3D = BoxShape3D.new(); box.size = Vector3(laser_len, 0.8, 2.0)
    var q := PhysicsShapeQueryParameters3D.new(); q.shape = box; q.collision_mask = 7
    q.transform.origin = Vector3(laser_origin.x + laser_facing * laser_len * 0.5, laser_origin.y, 0)
    HURT.prepare(actor, q)
    var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
    for hit in space.intersect_shape(q, 64):
        var target = HURT.resolve(hit.collider)
        if not actor.can_hit(target) or target in targets: continue
        targets.append(target)
        var contact: Dictionary = HURT.shape_contact(space, q, hit, [hit])
        HURT.deliver(target, L_DAMAGE, Vector3(laser_facing, 0.35, 0), L_PUSH, contact if not contact.is_empty() else {}, actor)
func _end_laser() -> void:
    phase = "idle"
    elapsed = 0.0
    laser_origin = Vector3.ZERO
    targets.clear()
    _hide_laser_fx()
    var view = _laser_view()
    if view and view.has_method("laser_gun_state"): view.laser_gun_state(0.0, 0.0, false)
    if actor.last_move in ["LASER BLAST", "LASER FIRE"]: actor.last_move = ""
func abort_laser() -> void:
    _end_laser()
    gun_fade = 0.25
func _hide_laser_fx() -> void:
    for n in fx.values():
        if is_instance_valid(n): n.hide()
func _place_cyl(n: MeshInstance3D, origin: Vector3, length: float, radius: float) -> void:
    n.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0) * Basis.from_scale(Vector3(radius * 2.0, length, radius * 2.0)), origin + Vector3(laser_facing * length * 0.5, 0, 0))
    n.show()
func _present_laser(view) -> void:
    var t := minf(elapsed, L_CLIP_LEN)
    var f := t / LF
    view.magic_pose("laser/LaserBlast", t, laser_facing)
    view.position.y = view.IDLE_FLOOR_OFFSET   # clip is built on the Idle root
    # Holo gun: materialize 0-7, solid, then flicker/fade out 36-46 while sliding.
    var amount := 1.0; var holo := 0.0; var off := false
    if f < 2.0: amount = lerpf(0.02, 0.3, f / 2.0); holo = 1.0
    elif f < 5.0: amount = lerpf(0.3, 1.08, (f - 2.0) / 3.0); holo = lerpf(0.9, 0.4, (f - 2.0) / 3.0); off = f >= 3.0 and f < 4.0
    elif f < 7.0: amount = lerpf(1.08, 1.0, (f - 5.0) / 2.0); holo = lerpf(0.4, 0.0, (f - 5.0) / 2.0)
    elif f >= 36.0 and f < 46.0:
        amount = lerpf(1.0, 0.3, (f - 36.0) / 10.0); holo = clampf((f - 36.0) / 6.0, 0.0, 1.0)
        off = (f >= 38.0 and f < 39.0) or (f >= 40.0 and f < 41.0) or (f >= 42.0 and f < 43.0)
    elif f >= 46.0: amount = 0.0
    view.laser_gun_state(amount, holo, off)
    var muzzle: Vector3 = view.laser_muzzle()
    _hide_laser_fx()
    if f >= 10.0 and f < 29.0:
        var r := 0.0
        for step in L_LINE_STEPS:
            if f >= step[0]: r = step[1]
        var glow := 0.35
        for p in L_PULSES:
            if f >= p: glow = maxf(glow, 1.0 - (f - p) * 0.9)
        var white := f >= 28.0
        fx.line.material_override.albedo_color = Color(Color(0.95, 1, 1) if white else TEAL.lerp(Color.WHITE, glow * 0.45), 0.35 + 0.6 * glow if not white else 1.0)
        _place_cyl(fx.line, muzzle, laser_len, r)
    if f >= 29.0 and f < 37.0:
        var s := 1.0; var fwd := 0.0
        if f >= 34.0: s = clampf(1.0 - (f - 34.0) / 3.0, 0.0, 1.0) * 0.75; fwd = lerpf(0.6, 3.0, clampf((f - 34.0) / 3.0, 0.0, 1.0))
        if s > 0.01:
            var o := laser_origin + Vector3(laser_facing * fwd, 0, 0)
            var ln := maxf(laser_len - fwd, 0.1)
            _place_cyl(fx.core, o, ln, 0.16 * s)
            _place_cyl(fx.sheath, o, ln, 0.34 * s)
    if f >= 29.0 and f < 35.0:
        var fs := 0.65 if f < 34.0 else 0.25
        fx.flash.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * fs), laser_origin)
        fx.flash.show()
    if f >= 34.0 and f < 40.0:
        var k := (f - 34.0) / 5.0
        var chest: Vector3 = actor.global_position + Vector3(0, 1.4, 0)
        var p: Vector3 = laser_origin.lerp(chest, clampf(k * 2.5, 0.0, 1.0)) if k < 0.4 else chest.lerp(chest + Vector3(-laser_facing * 1.0, 0, 0), (k - 0.4) / 0.6)
        var rs := lerpf(0.12, 0.7, clampf(k, 0.0, 1.0))
        fx.ring.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0) * Basis.from_scale(Vector3(rs, rs * 1.3, rs * 1.3)), p)
        fx.ring.material_override.albedo_color.a = 0.9 * (1.0 - clampf(k, 0.0, 1.0))
        fx.ring.show()
func store() -> void:
    if not actor.charging: return
    stored_charge = actor.charge_time
    actor.charging = false
    actor.charge_time = 0
    actor.last_move = "CHARGE STORED"
func release() -> void:
    if not actor.charging: return
    var shot = preload("res://scripts/teknium_charge_shot.gd").new()
    shot.source = actor
    shot.direction = actor.facing
    shot.power = clampf(actor.charge_time / actor.MAX_CHARGE_TIME,0,1)
    actor.get_parent().add_child(shot)
    shot.global_position = actor.global_position + Vector3(actor.facing*0.85,1.25,0)
    actor.charging = false
    actor.charge_time = 0
    stored_charge = 0
    actor.attack_cooldown = 0.28
    actor.last_move = "CHARGE RELEASE"
func before_move(delta: float, input: Dictionary) -> void:
    previous = actor.global_position
    if phase == "idle": return
    if actor.hitstun>0 or actor.freeze_remaining>0 or not actor.controls_enabled:
        cancel()
        return
    if phase == "laser":
        _laser_move(delta, input)
        return
    elapsed += delta
    if phase == "shadow_start":
        actor.velocity.x = 0
        if elapsed >= 0.06:
            phase = "shadow_dash"
            elapsed = 0
            ghost_clock = 0
    if phase == "shadow_dash":
        actor.velocity = burst_direction * 23.0
        actor.facing = burst_direction.x
        if elapsed >= 0.23:
            phase = "idle"
            actor.velocity *= 0.12
    if phase == "rise_charge":
        var aim := Vector3(float(input.right)-float(input.left),float(input.up)-float(input.down),0)
        if aim.length_squared() > 0.1: burst_direction = aim.normalized()
        actor.velocity = Vector3.ZERO
        if elapsed >= 0.45:
            phase = "rise_burst"
            elapsed = 0
            actor.last_move = "HOLY BURST"
    if phase == "rise_burst":
        actor.velocity = burst_direction * 20.0
        if absf(burst_direction.x)>0.1: actor.facing = signf(burst_direction.x)
        if elapsed >= 0.28:
            phase = "idle"
            actor.velocity *= 0.15
func cancel() -> void:
    if phase == "laser": gun_fade = 0.25
    laser_origin = Vector3.ZERO
    _hide_laser_fx()
    phase = "idle"
    elapsed = 0
    actor.charging = false
    actor.charge_time = 0
    targets.clear()
    for ghost in ghosts:
        if is_instance_valid(ghost): ghost.queue_free()
    ghosts.clear()
    if cue: cue.hide()
func after_move(delta: float) -> void:
    if gun_fade > 0.0: gun_fade = maxf(0.0, gun_fade - delta)
    if phase == "laser":
        _laser_hits()
        return
    if phase not in ["shadow_dash","rise_burst"]: return
    present()
    # Sweep the leading foot across actual controller travel, never past a wall.
    var view = actor._visual_root.get_node("TekniumVisual")
    var skeleton: Skeleton3D = view.model.find_children("*","Skeleton3D",true,false)[0]
    var foot: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
    if phase=="rise_burst": foot=actor.global_position+Vector3.UP+burst_direction*0.65
    var start: Vector3 = foot + previous - actor.global_position
    var steps := maxi(1,ceili(start.distance_to(foot)/0.12))
    for i in range(steps+1):
        var point: Vector3 = start.lerp(foot,float(i)/steps)
        var sphere := SphereShape3D.new(); sphere.radius=0.32 if phase=="shadow_dash" else 0.6
        var q := PhysicsShapeQueryParameters3D.new(); q.shape=sphere; q.transform.origin=point; q.collision_mask=7
        HURT.prepare(actor,q)
        for hit in actor.get_world_3d().direct_space_state.intersect_shape(q,64):
            var target = HURT.resolve(hit.collider)
            if not actor.can_hit(target) or target in targets: continue
            var ray := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP,point,1)
            ray.exclude=[actor.get_rid(),target.get_rid()]
            if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
            targets.append(target)
            hit.position=point
            HURT.deliver(target,13.0 if phase=="shadow_dash" else 12.0,Vector3(actor.facing,0.2,0) if phase=="shadow_dash" else burst_direction,5.0,hit,actor)
    ghost_clock -= delta
    if ghost_clock <= 0:
        ghost_clock = 0.045
        afterimage(view)
func present() -> void:
    var lview = _laser_view()
    if lview and lview.has_method("laser_gun_state"):
        if phase == "laser":
            _present_laser(lview)
        elif gun_fade > 0.0:
            lview.laser_gun_state(gun_fade / 0.25, 1.0, fmod(gun_fade, 0.08) < 0.03)
        else:
            lview.laser_gun_state(0.0, 0.0, false)
    cue.visible = actor.charging or phase in ["rise_charge","rise_burst"]
    cue.global_position = actor.global_position + (Vector3(actor.facing*0.85,1.25,0) if actor.charging else Vector3.UP)
    cue.scale = Vector3.ONE*(lerpf(0.3,0.9,actor.charge_time/actor.MAX_CHARGE_TIME) if actor.charging else (0.75 if phase=="rise_charge" else 1.1))
    cue.rotation.z = elapsed*8
    if phase in ["rise_charge","rise_burst"]:
        var view = actor._visual_root.get_node("TekniumVisual")
        view.magic_pose("Block" if phase=="rise_charge" else "Jump",0.2,actor.facing)
    if phase in ["shadow_start","shadow_dash"]:
        var view = actor._visual_root.get_node("TekniumVisual")
        view.magic_pose("humanoid_air_neutral/Neutral",0.18,actor.facing)
func afterimage(view) -> void:
    var ghost = view.model.duplicate()
    actor.get_parent().add_child(ghost)
    ghost.global_transform = view.model.global_transform
    ghost.add_to_group("teknium_afterimages")
    ghost.process_mode = Node.PROCESS_MODE_DISABLED
    for player in ghost.find_children("*","AnimationPlayer",true,false): player.stop(true)
    var source_skeleton: Skeleton3D = view.model.find_children("*","Skeleton3D",true,false)[0]
    var skeleton: Skeleton3D = ghost.find_children("*","Skeleton3D",true,false)[0]
    for bone in source_skeleton.get_bone_count(): skeleton.set_bone_pose(bone,source_skeleton.get_bone_pose(bone))
    var mat := StandardMaterial3D.new()
    mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color=Color(0.1,1.0,0.3,0.30)
    for mesh in ghost.find_children("*","MeshInstance3D",true,false): mesh.material_override=mat
    ghosts = ghosts.filter(func(g): return is_instance_valid(g))
    ghosts.append(ghost)
    var tween = create_tween()
    tween.tween_property(mat,"albedo_color:a",0.0,0.2)
    tween.tween_callback(ghost.queue_free)
func clear() -> void:
    cancel()
    stored_charge = 0
    actor.charging = false
    actor.charge_time = 0
    if is_instance_valid(grenade): grenade.queue_free()
    grenade = null

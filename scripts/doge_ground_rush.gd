extends Node
# Doge-only grounded down-special. No root motion, armor or airborne resource use.
const MAX_CHARGE := 2.25 # Power caps, animation continues; never auto-release.
const RECOVERY_TIME := 0.28
var actor
var phase := "idle"
var elapsed := 0.0
var power := 0.0
var rush_facing := 1.0
var targets: Array = []
var previous := Vector3.ZERO
var brake_after_move := false
var brake_speed := 0.0
var rush_duration := 0.3
var brake_overflow := 0.0
var active_distance := 0.0
func _ready() -> void: actor = get_parent()
func start() -> void:
    if not actor.is_grounded() or actor.velocity.y > 0: return
    phase = "charge"
    elapsed = 0
    targets.clear()
    brake_after_move = false
    actor.charging = true
    actor.charge_time = 0
    actor.velocity.x = 0
    actor.shielding = false
    actor.last_move = "CHARGING OF THE BULL"
func release() -> void:
    if phase != "charge": return
    if not actor.controls_enabled or actor.hitstun > 0 or actor.freeze_remaining > 0 or actor.magic_locked() or not actor.is_grounded():
        cancel()
        return
    power = clampf(actor.charge_time / MAX_CHARGE,0,1)
    rush_duration = lerpf(0.3,0.75,power)
    rush_facing = actor.facing
    actor.charging = false
    actor.charge_time = 0
    phase = "rush"
    elapsed = 0
    brake_overflow = 0
    actor.last_move = "CHARGING OF THE BULL"
func cancel() -> void:
    if phase == "idle": return
    phase = "idle"
    elapsed = 0
    power = 0
    targets.clear()
    actor.charging = false
    actor.charge_time = 0
    brake_after_move = false
    brake_speed = 0
func tick(delta: float) -> void:
    if phase == "idle": return
    if not actor.controls_enabled or actor.hitstun > 0 or actor.freeze_remaining > 0 or actor.magic_locked() or not actor.is_grounded() or actor.velocity.y > 0:
        cancel()
        return
    previous = actor.global_position
    if phase == "charge":
        elapsed += delta # Independent animation clock keeps moving after 100%.
        actor.velocity.x = 0
    elif phase == "rush":
        actor.facing = rush_facing
        var speed := lerpf(7,18,power)
        var remaining := maxf(0,rush_duration-elapsed)
        active_distance=speed*minf(delta,remaining)
        brake_overflow=maxf(0,delta-remaining)
        # Integrate the fractional boundary into easing; a short final rush
        # slice must not halve velocity for one frame before the brake.
        var t:=minf(brake_overflow,RECOVERY_TIME)
        var brake_integral:=t-pow(t,3)/pow(RECOVERY_TIME,2)+0.5*pow(t,4)/pow(RECOVERY_TIME,3)
        var distance := speed * (minf(delta,remaining)+brake_integral)
        var stopping_distance := speed*RECOVERY_TIME*0.5
        var available := safe_distance(distance+stopping_distance)
        var wall := terrain_ray(actor.global_position+Vector3.UP*0.9,actor.global_position+Vector3.UP*0.9+Vector3.RIGHT*rush_facing*(distance+stopping_distance+0.57))
        if not wall.is_empty(): available=minf(available,maxf(0,absf(wall.position.x-actor.global_position.x)-0.57))
        if available < distance+stopping_distance-0.0001:
            begin_brake()
            brake_speed=minf(speed,available*2/RECOVERY_TIME)
            tick_brake(delta)
            return
        var safe := safe_distance(distance)
        actor.velocity.x = rush_facing * safe / maxf(delta,0.000001)
        brake_after_move = safe < distance - 0.00001 or elapsed + delta >= rush_duration - 0.00001
        elapsed += delta
    else:
        tick_brake(delta)
func begin_brake(hard := false) -> void:
    phase="recovery"
    elapsed=0
    brake_speed=0 if hard else absf(actor.velocity.x)
    brake_after_move=false
    if hard: actor.velocity.x=0
func tick_brake(delta: float) -> void:
    actor.facing=rush_facing
    elapsed=minf(RECOVERY_TIME,elapsed+delta)
    var speed:=brake_speed*(1-smoothstep(0,RECOVERY_TIME,elapsed))
    var distance:=speed*delta
    var safe:=safe_distance(distance)
    actor.velocity.x=rush_facing*safe/maxf(delta,0.000001)
    if safe < distance-0.00001:
        brake_speed=0 # Edge safety overrides easing if support disappears.
        actor.velocity.x=0
    if elapsed >= RECOVERY_TIME:
        actor.velocity.x=0
        cancel()
func terrain_ray(a: Vector3, b: Vector3) -> Dictionary:
    var ray := PhysicsRayQueryParameters3D.create(a,b,actor.collision_mask)
    var excluded: Array[RID] = []
    for fighter in get_tree().get_nodes_in_group("fighters"):
        if fighter is CollisionObject3D: excluded.append(fighter.get_rid())
    for platform in actor._ignored_platforms:
        if is_instance_valid(platform): excluded.append(platform.get_rid())
    ray.exclude = excluded
    return actor.get_world_3d().direct_space_state.intersect_ray(ray)
func capsule(body) -> CollisionShape3D:
    for child in body.get_children():
        if child is CollisionShape3D and not child.disabled and child.shape is CapsuleShape3D: return child
    return null
func supported(center: Vector3) -> bool:
    var shape := capsule(actor)
    if not shape: return false
    var radius: float = shape.shape.radius * shape.global_basis.get_scale().x + 0.02
    # Check the complete bottom footprint conservatively, not just the center.
    # Short rays deliberately brake at steps/gaps instead of hopping them.
    for offset in [Vector3.ZERO,Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
        var foot: Vector3 = center + offset
        var hit := terrain_ray(foot+Vector3.UP*0.10,foot-Vector3.UP*0.12)
        if hit.is_empty() or hit.normal.dot(Vector3.UP)<cos(actor.floor_max_angle): return false
    return true
func safe_distance(distance: float) -> float:
    if not supported(actor.global_position): return 0
    var good := 0.0
    # Every intervening .08m is checked; low FPS cannot skip a thin ledge/gap.
    var count := maxi(1,ceili(distance/0.08))
    for i in range(1,count+1):
        var next := distance * i/count
        if not supported(actor.global_position+Vector3.RIGHT*rush_facing*next):
            var bad := next
            for j in 10:
                var mid := (good+bad)*0.5
                if supported(actor.global_position+Vector3.RIGHT*rush_facing*mid): good = mid
                else: bad = mid
            return good
        good = next
    return distance
func after_move() -> void:
    if phase != "rush": return
    if not actor.is_grounded():
        cancel() # External displacement never pins an airborne body.
        return
    var own := capsule(actor)
    if not own: return
    var own_radius: float = own.shape.radius * own.global_basis.get_scale().x
    var own_half: float = maxf(0,own.shape.height*0.5-own.shape.radius)
    var motion: Vector3 = actor.global_position-previous
    var active_motion:=motion.limit_length(active_distance)
    var brake_shift:=motion-active_motion
    var active_transform:Transform3D=own.global_transform
    active_transform.origin-=brake_shift
    motion=active_motion
    for target in get_tree().get_nodes_in_group("fighters"):
        if not actor.can_hit(target) or target in targets: continue
        var other := capsule(target)
        if not other: continue
        if (other.global_position.x-active_transform.origin.x)*rush_facing < -0.02: continue
        var half: float = maxf(0,other.shape.height*0.5-other.shape.radius)
        var a := other.global_transform*Vector3(0,-half,0)
        var b := other.global_transform*Vector3(0,half,0)
        var radius: float = own_radius + other.shape.radius * other.global_basis.get_scale().x + 0.01
        var contact := false
        var count := maxi(1,ceili(motion.length()/0.02))
        for i in range(count+1):
            var offset := motion * (1-float(i)/count)
            var near := Geometry3D.get_closest_points_between_segments(active_transform*Vector3(0,-own_half,0)-offset,active_transform*Vector3(0,own_half,0)-offset,a,b)
            if near[0].distance_to(near[1]) <= radius and terrain_ray(active_transform.origin-offset,other.global_position).is_empty():
                contact = true
                break
        if contact:
            targets.append(target) # Latch before receive_hit can re-enter combat.
            target.receive_hit(14,Vector3(rush_facing*0.2,1,0),lerpf(5,8,power))
    for i in actor.get_slide_collision_count():
        var collision: KinematicCollision3D = actor.get_slide_collision(i)
        for j in collision.get_collision_count():
            var body = collision.get_collider(j)
            if is_instance_valid(body) and not body.is_in_group("fighters") and collision.get_normal(j).x*rush_facing < -0.5:
                brake_after_move = true
    if brake_after_move:
        var hard:bool=actor.is_on_wall()
        begin_brake(hard)
        if not hard:
            brake_speed=lerpf(7,18,power)
            elapsed=brake_overflow
func present(view, delta := 0.0) -> void:
    if phase == "idle": return
    view.model.rotation.y = actor.facing * PI/2
    view.jump_elapsed = -1
    var clip := "GroundCharge" if phase == "charge" else ("GroundRush" if phase == "rush" else "Idle")
    if phase == "charge":
        if view.current_clip != clip: view.animation_player.play(clip,0)
        view.animation_player.speed_scale=0
        # Source-preserving smooth ping-pong: every authored pose retained,
        # zero velocity at both turnarounds; 4.5s continuous charge cycle.
        var source_time:=MAX_CHARGE*0.5*(1-cos(TAU*elapsed/(2*MAX_CHARGE)))
        view.animation_player.seek(source_time,true)
    else:
        if view.current_clip != clip:
            view.animation_player.play(clip,0.08 if phase=="rush" else 0.18,view.animation_player.get_animation(clip).length/rush_duration if phase=="rush" else 1)
        # Advance the real crossfade on the physics clock, not the render clock.
        view.animation_player.speed_scale=1
        view.animation_player.advance(delta)
        view.animation_player.speed_scale=0
    view.current_clip = clip

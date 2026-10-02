extends Node3D
# Presentation only. Fighter retains all movement, collision and combat timing.
const MODEL = preload("res://assets/ice_mage/ice_mage_combat.glb")
# Hand-keyed Ice Mage kit: jump/double/fall/land,
# Frost Rise up special, helpless fall, hurt flinch and launch tumble.
const KIT = preload("res://assets/ice_mage/ice_mage_kit.tres")
const K := "ice_kit/"
const TAKEOFF_SECONDS := 0.125
const DOUBLE_SECONDS := 0.3333
const LAND_SECONDS := 0.2917
const HURT_HOLD := 5.0 / 24.0
const TUMBLE_LAUNCH := 0.25
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := ""
var fallback_label := ""
var air_state := ""
var land_clock := 0.0
var hurt_clock := 0.0
var tumble_face := 1.0
var last_jumps := 0
var was_grounded := true
func _ready() -> void:
    scale = Vector3.ONE * 1.15
    position.y = 0.035
    model = MODEL.instantiate()
    add_child(model)
    animation_player = model.find_children("*","AnimationPlayer",true,false)[0]
    for name in animation_player.get_animation_library_list():
        var source = animation_player.get_animation_library(name)
        var library = AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation = source.get_animation(clip).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle","Walk","Run"] else Animation.LOOP_NONE
            library.add_animation(clip,animation)
        animation_player.remove_animation_library(name)
        animation_player.add_animation_library(name,library)
    animation_player.add_animation_library("ice_kit", KIT)
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        for surface in mesh.mesh.get_surface_count():
            var material: StandardMaterial3D = mesh.get_active_material(surface).duplicate()
            material.emission_enabled = false
            mesh.set_surface_override_material(surface,material)
    sync_pose(true,Vector3.ZERO,false,false,"",1.0,0.0)
func _actor():
    # Only a real fighter drives the airborne kit; victory/stage props keep plain locomotion.
    var root = get_parent()
    if root == null: return null
    var a = root.get_parent()
    if a != null and a.get("jumps_used") != null and a.get("JUMP_SPEED") != null: return a
    return null
func choose_clip(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String) -> String:
    if not grounded or interrupted or shielding or not active_move.is_empty(): return "Idle"
    if absf(motion.x)>0.2: return "Run" if absf(motion.x)>=4.0 else "Walk"
    return "Idle"
func pose_at(clip: String, t: float) -> void:
    animation_player.speed_scale = 1.0
    if animation_player.assigned_animation != clip: animation_player.play(clip, 0.0)
    animation_player.seek(clampf(t, 0.0, animation_player.get_animation(clip).length), true)
    animation_player.pause()
    current_clip = clip
func loop_clip(clip: String, blend: float) -> void:
    animation_player.speed_scale = 1.0
    if current_clip == clip and animation_player.is_playing(): return
    current_clip = clip
    animation_player.play(clip, blend)
func sync_pose(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String, facing: float, delta: float, attack_clip: String = "", attack_elapsed: float = 0.0) -> void:
    if animation_player==null: return
    var a = _actor()
    var dt := maxf(delta, 0.0)
    if not attack_clip.is_empty() and not interrupted:
        fallback_label = ""
        model.rotation.y = facing * PI / 2.0
        var clip_name := attack_clip
        if attack_clip == "IceCast" and active_move == "FROST RISE":
            clip_name = K + "FrostRise"
            air_state = "frost_rise"
        current_clip = clip_name
        animation_player.speed_scale = 1.0
        animation_player.play(clip_name)
        animation_player.seek(attack_elapsed, true)
        animation_player.pause()
        _remember(a, grounded)
        return
    model.rotation.y = facing * PI / 2.0
    fallback_label = ""
    if a != null and _present_kit(a, grounded, motion, interrupted, active_move, dt):
        _remember(a, grounded)
        return
    if a == null and not grounded: fallback_label = "Airborne: Idle fallback"
    elif interrupted or shielding or not active_move.is_empty(): fallback_label = "Combat: Idle fallback (baseline mechanics)"
    var clip = choose_clip(grounded,motion,interrupted,shielding,active_move)
    animation_player.speed_scale = 1.0
    _remember(a, grounded)
    if current_clip==clip and animation_player.is_playing(): return
    current_clip=clip
    animation_player.play(clip,0.1)
    animation_player.advance(dt)
func _remember(a, grounded: bool) -> void:
    if a != null: last_jumps = a.jumps_used
    was_grounded = grounded
# Returns true when the kit owns the pose this tick.
func _present_kit(a, grounded: bool, motion: Vector3, interrupted: bool, active_move: String, dt: float) -> bool:
    var tumble = a.get("tumble")
    if tumble != null and tumble.active:
        if air_state != "tumble":
            air_state = "tumble"
            tumble_face = -signf(a.velocity.x) if absf(a.velocity.x) > 0.5 else (1.0 if model.rotation.y >= 0.0 else -1.0)
        var tumble_fitted = a.get("fitted_reaction")
        if tumble_fitted != null and tumble_fitted.active: tumble_fitted.clear()
        # Back leads the flight: face against the launch, limbs trail toward the hit.
        model.rotation.y = tumble_face * PI / 2.0
        if tumble.clock < TUMBLE_LAUNCH: pose_at(K + "TumbleLaunch", tumble.clock)
        else: loop_clip(K + "TumbleLoop", 0.08)
        return true
    if interrupted:
        if a.freeze_remaining > 0: return false
        var fitted = a.get("fitted_reaction")
        if fitted != null and fitted.active: return true   # approved contact reaction owns the skeleton
        if air_state != "hurt":
            air_state = "hurt"
            hurt_clock = 0.0
        hurt_clock += dt
        pose_at(K + "Hurt", minf(hurt_clock, HURT_HOLD))
        return true
    var vy: float = a.velocity.y
    if not grounded:
        if was_grounded and air_state != "frost_rise":
            # Leaving the floor: a real ground jump takes off; ledges and knock-ups fall.
            air_state = "takeoff" if a.jumps_used > 0 and vy > a.JUMP_SPEED * 0.6 else "fall"
        elif not was_grounded and a.jumps_used > last_jumps and vy > 0.0:
            air_state = "double"
        if air_state in ["", "land", "hurt"]: air_state = "fall"
        if a.recovery_spent and air_state != "frost_rise": air_state = "helpless"
        if air_state == "frost_rise":
            # Frost Rise clip ran on the attack clock; after it, a spent recovery is helpless.
            if a.recovery_spent: air_state = "helpless"
            else: air_state = "fall"
        var since_jump: float = (a.JUMP_SPEED - vy) / a.GRAVITY
        match air_state:
            "takeoff":
                if since_jump < TAKEOFF_SECONDS and vy > 0.0:
                    pose_at(K + "JumpTakeoff", since_jump)
                    return true
                air_state = "rise"
            "double":
                if since_jump < DOUBLE_SECONDS and vy > 0.0:
                    pose_at(K + "JumpDouble", since_jump)
                    return true
                if vy > 0.0:
                    pose_at(K + "JumpRise", 10.0 / 24.0)
                    return true
                air_state = "fall"
            "helpless":
                loop_clip(K + "HelplessFall", 0.15)
                return true
        if air_state == "rise":
            if vy > 0.0:
                var remaining: float = a.JUMP_SPEED - a.GRAVITY * TAKEOFF_SECONDS
                pose_at(K + "JumpRise", clampf(1.0 - vy / remaining, 0.0, 1.0) * (10.0 / 24.0))
                return true
            air_state = "fall"
        loop_clip(K + "FallLoop", 0.1)
        return true
    # Grounded
    if air_state in ["takeoff", "rise", "double", "fall", "helpless", "tumble", "frost_rise", "hurt"] and not was_grounded:
        air_state = "land"
        land_clock = 0.0
    if air_state == "land":
        land_clock += dt
        if land_clock < LAND_SECONDS and absf(motion.x) < 4.0 and active_move.is_empty():
            pose_at(K + "JumpLand", land_clock)
            return true
    air_state = ""
    return false

extends Node3D

# Presentation only. Fighter owns translation, collision, hit timing, and damage.
const MODEL = preload("res://assets/turbofit/turbofit_animations.glb")
# Approved full v004 body + travel baked into native bones only. No actor motion.
const MOSH_IDLE = preload("res://assets/turbofit/mosh_idle_v004.tres")

var model: Node3D
var animation_player: AnimationPlayer
var current_clip := ""
var palette := Color.WHITE
var falling := false
var landing_remaining := 0.0
var _kick_skeleton: Skeleton3D
var _kick_foot := -1
var _kick_toe := -1

# Approved Power Chord presentation: uncapped anticipation, immediate contact.
# The combat controller retains the original charge, damage and cooldown clocks.
var power_hold_clock := 0.0
var power_released := false
var power_release_facing := 1.0
var power_source_frame := 1.0
var power_returning := false
var power_charging := false
var power_cooldown := 0.0

func begin_power_chord() -> void:
    cancel_power_chord()
    power_source_frame = 1.0

func power_chord_contact(direction: float) -> void:
    power_released = true
    power_returning = false
    power_release_facing = direction
    power_chord_pose_frame(20.0, direction)

func cancel_power_chord() -> void:
    power_released = false
    power_hold_clock = 0.0
    power_returning = false

func power_chord_pose_frame(frame: float, direction: float) -> void:
    falling = false
    landing_remaining = 0.0
    power_source_frame = frame
    current_clip = "TwoHandCombo"
    model.rotation.y = direction * PI / 2.0
    animation_player.play("TwoHandCombo", 0, 1)
    animation_player.speed_scale = 0
    animation_player.seek((frame - 1.0) / 30.0, true)
    _kick_skeleton.force_update_all_bone_transforms()

func present_power_chord(charging: bool, cooldown: float, active_move: String, facing: float, delta: float) -> bool:
    if active_move == "CHARGING" and charging:
        power_released = false
        power_returning = false
        power_hold_clock += delta
        var frame := lerpf(1, 16, sin(minf(power_hold_clock / 0.25, 1) * PI / 2))
        if power_hold_clock > 0.25: frame = 15.0 + cos((power_hold_clock - 0.25) * TAU / 0.9)
        power_chord_pose_frame(frame, facing)
        return true
    if power_released and active_move == "POWER CHORD":
        var elapsed: float = maxf(0, 0.7 - cooldown)
        if elapsed <= 0.3333334:
            power_chord_pose_frame(20.0 + elapsed * 30.0, power_release_facing)
        elif not power_returning:
            power_returning = true
            current_clip = "Idle"
            animation_player.speed_scale = 1
            animation_player.play("Idle", 0.20)
        return true
    cancel_power_chord()
    return false

func _ready() -> void:
    scale = Vector3.ONE * 1.25
    model = MODEL.instantiate()
    add_child(model)
    model.rotation.y = PI / 2.0
    for skeleton in model.find_children("*", "Skeleton3D", true, false):
        var foot: int = skeleton.find_bone("mixamorig_RightFoot")
        var toe: int = skeleton.find_bone("mixamorig_RightToe_End")
        if foot >= 0 and toe >= 0:
            _kick_skeleton = skeleton
            _kick_foot = foot
            _kick_toe = toe
            break
    for node in model.find_children("*", "AnimationPlayer", true, false):
        animation_player = node
        break
    if animation_player == null:
        push_error("TurboFit AnimationPlayer missing")
        return
    # Imported libraries are shared; loop and material edits must stay local.
    for library_name in animation_player.get_animation_library_list():
        var source_library = animation_player.get_animation_library(library_name)
        var library := AnimationLibrary.new()
        for name in source_library.get_animation_list():
            var animation: Animation = source_library.get_animation(name).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if name in ["Idle", "BlockIdle", "Walk", "Run", "FallLoop"] else Animation.LOOP_NONE
            library.add_animation(name, animation)
        animation_player.remove_animation_library(library_name)
        animation_player.add_animation_library(library_name, library)
    animation_player.get_animation_library("").add_animation("MoshIdleV004", MOSH_IDLE.get_animation("MoshIdleV004").duplicate(true))
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var source = mesh.get_active_material(surface)
            if source is StandardMaterial3D:
                var material: StandardMaterial3D = source.duplicate()
                material.albedo_color *= Color.WHITE.lerp(palette, 0.10)
                material.metallic = minf(material.metallic, 0.08)
                material.roughness = maxf(material.roughness, 0.68)
                # TurboFit's black clothing disappears against the dark arena.
                # Reuse the static albedo as a restrained, non-flashing lift.
                material.emission_enabled = true
                material.emission = Color.WHITE
                material.emission_texture = material.albedo_texture
                material.emission_energy_multiplier = 0.25
                mesh.set_surface_override_material(surface, material)
    sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, 1.0, 0.0)

func air_side_kick_volume(elapsed: float, duration: float, facing: float) -> Dictionary:
    if not _kick_skeleton or not animation_player:
        return {}
    # Seek the SAME visible model from the combat clock. Force bone evaluation
    # so offscreen/headless physics never depends on rendering or an idle tick.
    sync_pose(false, Vector3.ZERO, false, false, "AIR SIDE KICK", Vector3.RIGHT, facing, 0, "AirSideKick", elapsed, duration)
    _kick_skeleton.force_update_all_bone_transforms()
    var foot := _kick_skeleton.global_transform * _kick_skeleton.get_bone_global_pose(_kick_foot).origin
    var toe := _kick_skeleton.global_transform * _kick_skeleton.get_bone_global_pose(_kick_toe).origin
    return {"center": (foot + toe) * 0.5, "scale_factor": global_transform.basis.x.length() / 1.25}

func air_down_kick_volume(elapsed: float, duration: float, facing: float) -> Dictionary:
    if not _kick_skeleton or not animation_player:
        return {}
    var foot := _kick_skeleton.find_bone("mixamorig_LeftFoot")
    var toe := _kick_skeleton.find_bone("mixamorig_LeftToe_End")
    if foot < 0 or toe < 0:
        return {}
    sync_pose(false, Vector3.ZERO, false, false, "AIR DOWN KICK", Vector3.DOWN, facing, 0, "AirDownKick", elapsed, duration)
    _kick_skeleton.force_update_all_bone_transforms()
    var a := _kick_skeleton.global_transform * _kick_skeleton.get_bone_global_pose(foot).origin
    var b := _kick_skeleton.global_transform * _kick_skeleton.get_bone_global_pose(toe).origin
    return {"center": (a + b) * 0.5, "scale_factor": global_transform.basis.x.length() / 1.25}

func choose_clip(grounded: bool, interrupted: bool, shielding: bool, active_move: String, attack_direction: Vector3) -> String:
    if interrupted:
        return "HitReactRight"
    if shielding:
        return "BlockIdle"
    if active_move == "SOUND ORB":
        return "BlockIdle"
    if active_move == "GUITAR SWING":
        return "MeleeBackhand" if absf(attack_direction.y) > 0.1 else "MeleeHorizontal"
    if active_move in ["POWER CHORD", "SOUND WAVE"]:
        return "TwoHandCombo"
    if active_move == "RISING CHORD" or not grounded:
        return "Jump"
    return "Idle"

func sync_pose(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String, attack_direction: Vector3, facing: float, delta: float, attack_clip := "", attack_elapsed := 0.0, attack_duration := 1.0) -> void:
    if animation_player == null:
        return
    if interrupted or shielding:
        cancel_power_chord()
    elif present_power_chord(power_charging, power_cooldown, active_move, facing, delta):
        return
    # Keep the visible horizontal strike aimed at its committed damage side.
    # Movement may turn freely; ordinary/interrupted poses use current facing.
    var pose_facing := facing
    if not interrupted and not shielding and active_move == "GUITAR SWING" and absf(attack_direction.x) > 0.1 and absf(attack_direction.y) <= 0.1:
        pose_facing = signf(attack_direction.x)
    model.rotation.y = pose_facing * PI / 2.0
    if not interrupted and not attack_clip.is_empty():
        # Preserve the landing episode when the airborne kick meets the floor.
        falling = attack_clip in ["AirSideKick", "AirDownKick"] and not grounded
        landing_remaining = 0.0
        if current_clip != attack_clip:
            animation_player.play(attack_clip, 0, 1)
        current_clip = attack_clip
        animation_player.speed_scale = 0
        animation_player.seek(clampf(attack_elapsed / attack_duration, 0, 1) * animation_player.get_animation(attack_clip).length, true)
        return
    var clip := choose_clip(grounded, interrupted, shielding, active_move, attack_direction)
    if interrupted or shielding or not active_move.is_empty():
        falling = false
        landing_remaining = 0.0
    else:
        landing_remaining = maxf(0, landing_remaining - delta)
        if not grounded:
            landing_remaining = 0.0
            falling = motion.y <= 0
            clip = "FallLoop" if falling else "Jump"
        else:
            if falling:
                landing_remaining = animation_player.get_animation("Landing").length
                falling = false
            clip = "Landing" if landing_remaining > 0 else ("Run" if absf(motion.x) > 4 else ("Walk" if absf(motion.x) > 0.15 else "Idle"))
    # Idle is intentionally not replaced in the native library: Power Chord's
    # approved recovery and setup retain that pose. Only passive play uses v004.
    if clip == "Idle" and grounded and motion.length() <= 0.15 and not interrupted and not shielding and active_move.is_empty():
        var fighter = get_parent().get_parent()
        var passive_allowed := true
        if fighter != null and fighter.has_method("is_grounded"):
            passive_allowed = fighter.controls_enabled and fighter.stocks > 0 and fighter.attack_cooldown <= 0 and fighter.recovery_active <= 0 and not fighter.charging and not fighter.magic_locked() and fighter.freeze_remaining <= 0
        if passive_allowed:
            clip = "MoshIdleV004"
    var target_duration: float = {
        "MeleeHorizontal": 0.8,
        "MeleeBackhand": 0.8,
        "TwoHandCombo": 0.7,
    }.get(clip, animation_player.get_animation(clip).length)
    animation_player.speed_scale = animation_player.get_animation(clip).length / target_duration
    if clip in ["Run", "Walk"]:
        animation_player.speed_scale = clampf(absf(motion.x) / (7.5 if clip == "Run" else 2.5), 0.55, 1.6)
    if clip == current_clip and (clip != "MoshIdleV004" or (animation_player.assigned_animation == clip and animation_player.is_playing())):
        return
    if not animation_player.has_animation(clip):
        push_error("TurboFit animation missing: " + clip)
        return
    current_clip = clip
    animation_player.play(clip, 0.06)
    animation_player.advance(maxf(0.0, delta))

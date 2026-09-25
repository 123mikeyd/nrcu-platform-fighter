extends Node3D
# Presentation only: never apply animation root motion to Fighter.
# Approved Moves2 body motion; controller owns all travel and interruptions.
const MODEL = preload("res://assets/doge_man/doge_attacks.glb")
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := ""
var palette := Color.WHITE

# Source frames 1..19 at 24 FPS span 18 frame intervals.
const FALL_START_TIME := 18.0 / 24.0
var fall_elapsed := -1.0
var jump_elapsed := -1.0
var hit_elapsed := 0.0
var air_uppercut := false
var tyson_followup := true

func begin_air_uppercut() -> void:
    cancel_up_special()
    jump_elapsed = -1.0
    air_uppercut = true

func present_air_uppercut(grounded: bool, motion: Vector3, facing: float, cooldown: float, timing: Dictionary) -> bool:
    if not air_uppercut:
        return false
    if cooldown <= 0 or (grounded and motion.y <= 0):
        air_uppercut = false
        return false
    # Existing aerial damage is immediate: contact -> followthrough at the
    # ground clip's approved speed, not full windup compressed into 0.32s.
    var speed := float(timing.playback_speed)
    var source_time := float(timing.impact_time) * speed + (0.32 - cooldown) * speed
    model.rotation.y = facing * PI / 2
    flight_root.rotation = Vector3.ZERO
    if current_clip != "Uppercut": animation_player.play("Uppercut", 0)
    current_clip = "Uppercut"
    animation_player.speed_scale = 0
    animation_player.seek(clampf(source_time, 0, animation_player.get_animation("Uppercut").length), true)
    return true
# Approved Blender parent maps -Y to +Z. In Godot this is +Z to +Y,
# conjugated by the existing model yaw: world roll = facing * PI/2.
# Only the independent visual parent rotates; meshes, bones and Fighter do not.
var flight_root: Node3D
var up_elapsed := -1.0
var up_restore := 0.0
const UP_RESTORE_TIME := 0.12

func begin_up_special(facing: float) -> void:
    jump_elapsed = -1.0
    up_elapsed = 0.0
    up_restore = 0.0
    flight_root.rotation.z = facing * PI / 2
    model.rotation.y = facing * PI / 2
    current_clip = "Dive"
    animation_player.play("Dive", 0)
    animation_player.speed_scale = 0
    animation_player.seek(0, true)

func cancel_up_special(preserve_pose := false) -> void:
    up_elapsed = -1.0
    up_restore = 0.0
    if flight_root and not preserve_pose:
        flight_root.rotation = Vector3.ZERO

func present_up_special(motion: Vector3, facing: float, delta: float) -> bool:
    # Play the unchanged Dive at source speed, holding its last pose until
    # actual apex. The separate 0.38-second damage clock is never extended.
    if up_elapsed >= 0:
        if motion.y > 0:
            up_elapsed += delta
            model.rotation.y = facing * PI / 2
            flight_root.rotation.z = facing * PI / 2
            current_clip = "Dive"
            animation_player.speed_scale = 0
            animation_player.seek(minf(up_elapsed, animation_player.get_animation("Dive").length), true)
            return true
        up_elapsed = -1
        up_restore = UP_RESTORE_TIME
        current_clip = "MidairMoves2"
        animation_player.speed_scale = 1
        animation_player.play(current_clip, UP_RESTORE_TIME)
    if up_restore > 0:
        up_restore = maxf(0, up_restore - delta)
        flight_root.rotation.z = facing * PI / 2 * smoothstep(0, UP_RESTORE_TIME, up_restore)
        return true
    flight_root.rotation = Vector3.ZERO
    return false

func begin_jump() -> void:
    jump_elapsed = 0.0
    current_clip = ""

func begin_hit() -> void:
    jump_elapsed = -1.0
    hit_elapsed = 0.0
    current_clip = ""

func locomotion_clip(grounded: bool, motion: Vector3, interrupted: bool, delta: float) -> String:
    fall_elapsed = -1.0
    if interrupted or (grounded and motion.y <= 0):
        jump_elapsed = -1.0
    if interrupted:
        return "Idle"
    if not grounded or motion.y > 0:
        if jump_elapsed >= 0:
            jump_elapsed += delta
            if jump_elapsed < 8.0 / 24.0:
                return "JumpMoves2"
            jump_elapsed = -1.0
        return "MidairMoves2"
    if absf(motion.x) > 4.0:
        return "Run"
    return "Walk" if absf(motion.x) > 0.15 else "Idle"

func _ready() -> void:
    scale = Vector3.ONE * 1.25
    model = MODEL.instantiate()
    flight_root = Node3D.new()
    flight_root.name = "UpFlightOrientation"
    add_child(flight_root)
    flight_root.add_child(model)
    model.rotation.y = PI / 2
    for node in model.find_children("*", "AnimationPlayer", true, false):
        animation_player = node
        break
    # Imported libraries are shared resources; loop edits must stay local.
    for library_name in animation_player.get_animation_library_list():
        var source_library = animation_player.get_animation_library(library_name)
        var library := AnimationLibrary.new()
        for name in source_library.get_animation_list():
            var animation: Animation = source_library.get_animation(name).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if name in ["Idle", "Run", "Walk", "FallLoop", "MidairMoves2"] else Animation.LOOP_NONE
            library.add_animation(name, animation)
        animation_player.remove_animation_library(library_name)
        animation_player.add_animation_library(library_name, library)
    var ground_library = load("res://assets/doge_man/ground_basic_20260915.tres")
    for clip in ground_library.get_animation_list():
        animation_player.get_animation_library("").add_animation(clip, ground_library.get_animation(clip).duplicate(true))
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for shape_index in mesh.mesh.get_blend_shape_count():
            if "Fist_STUDY" in str(mesh.mesh.get_blend_shape_name(shape_index)):
                mesh.set_blend_shape_value(shape_index, 1.0)
        for surface in mesh.mesh.get_surface_count():
            var source = mesh.get_active_material(surface)
            if source is StandardMaterial3D:
                var material: StandardMaterial3D = source.duplicate()
                material.albedo_color *= Color.WHITE.lerp(palette, 0.25)
                material.metallic = 0
                material.roughness = 0.8
                material.emission_enabled = false
                mesh.set_surface_override_material(surface, material)
    animation_player.set_blend_time("FallStart", "FallLoop", 4.0 / 24.0)
    sync_pose("idle", 1, 0.4, 0.42, 0.18, 0.6)

func sync_pose(phase: String, facing: float, launch_time: float, dive_time: float, brake_time: float, landing_time: float, grounded := true, motion := Vector3.ZERO, interrupted := false, delta := 0.0, attack_clip := "", attack_elapsed := 0.0, attack_duration := 1.0, hit_active := false) -> void:
    model.rotation.y = facing * PI / 2
    if hit_active:
        jump_elapsed = -1.0
        hit_elapsed += delta
        if current_clip != "HitMoves2": animation_player.play("HitMoves2", 0)
        current_clip = "HitMoves2"
        animation_player.speed_scale = 0
        animation_player.seek(minf(hit_elapsed, animation_player.get_animation("HitMoves2").length), true)
        return
    if phase == "idle" and not interrupted and not attack_clip.is_empty():
        fall_elapsed = -1
        jump_elapsed = -1
        if not animation_player.has_animation(attack_clip):
            push_error("Doge animation missing: " + attack_clip)
            return
        var animation := animation_player.get_animation(attack_clip)
        # The controller owns this clock. Zero blend and zero autonomous speed
        # keep the evaluated fist pose on the same timeline as its hit event.
        if current_clip != attack_clip:
            animation_player.play(attack_clip, 0, 1)
        current_clip = attack_clip
        animation_player.speed_scale = 0
        var source_time := clampf(attack_elapsed / attack_duration, 0, 1) * animation.length
        if attack_clip == "TysonTwoPiece" and attack_elapsed > 0.35 and not tyson_followup:
            # Uncommitted jab reverses its own anticipation to guard; no right.
            source_time = maxf(0, 0.35 - (attack_elapsed - 0.35))
        animation_player.seek(source_time, true)
        return
    var locomotion := locomotion_clip(grounded, motion, interrupted or phase != "idle", delta)
    var clip: String = {"launch":"Launch", "tackle":"Dive", "fall":"Brake", "landing":"Landing"}.get(phase, locomotion)
    # Update speed without replaying the clip or resetting its timeline.
    animation_player.speed_scale = clampf(absf(motion.x) / (7.5 if clip == "Run" else 2.5), 0.55, 1.6) if clip in ["Run", "Walk"] else 1.0
    if clip == current_clip:
        return
    current_clip = clip
    if not animation_player or not animation_player.has_animation(clip):
        push_error("Doge animation missing: " + clip)
        return
    var duration: float = {"Launch":launch_time, "Dive":dive_time, "Brake":brake_time, "Landing":landing_time, "FallStart":FALL_START_TIME}.get(clip, animation_player.get_animation(clip).length)
    # Non-looping Brake holds upright in flight until real floor collision.
    animation_player.play(clip, -1 if clip == "FallLoop" else 0.04, animation_player.get_animation(clip).length / duration)
    animation_player.advance(0)

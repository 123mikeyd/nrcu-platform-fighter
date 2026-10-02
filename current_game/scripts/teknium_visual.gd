extends Node3D

# Presentation only: existing Fighter remains the sole gameplay clock/physics owner.
const MODEL = preload("res://assets/teknium/teknium_animations.glb")
# Evaluated skinned Idle soles are 0.225–0.228 above the fighter origin.
# Correct placement, not bones/root motion. Magic and Jump retain source space.
const IDLE_FLOOR_OFFSET := -0.224
# Constant clip baselines from 61 evaluated skin samples each. Keep the Run
# flight phase and every authored joint/bob; never clamp feet to a live floor.
const GROUNDED_OFFSETS := {"Idle": IDLE_FLOOR_OFFSET, "Walk": 0.066,
    "Run": 0.086, "Block": -0.061, "Punch": -0.106, "Kick": -0.038, "Hit": -0.112}
var placement_from := 0.0
var placement_target := 0.0
var placement_elapsed := 0.06
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := ""
# Identity node for ledge_grab.gd, which reads view.flight_root (Doge's up-flight pivot).
# Tek has no flight pivot: the model is NOT parented to it, it stays at identity.
var flight_root: Node3D
var jump_elapsed := 0.0
var jump_active := false

# Called only after Fighter accepts a jump, including a second jump in air.
func begin_jump() -> void:
    jump_elapsed = 0.0
    jump_active = true

func magic_pose(clip: String, seconds: float, facing: float) -> void:
    position.y = 0.0 # Preserve approved source-clock hands and attack geometry.
    placement_target = 0.0
    placement_elapsed = 0.06
    model.rotation.y = facing * PI/2.0
    animation_player.speed_scale = 1.0
    if current_clip != clip:
        current_clip = clip
        animation_player.play(clip, 0.0)
    animation_player.seek(seconds, true)
    animation_player.pause()
    var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    skeleton.force_update_all_bone_transforms()

func hand_tip(hand: String = "RightHand") -> Vector3:
    var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    skeleton.force_update_all_bone_transforms()
    var length := 19.50612449645996 if hand == "RightHand" else 18.405174255371094
    return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(hand)) * Vector3(0,length,0)

func _ready() -> void:
    scale = Vector3.ONE * 1.25
    model = MODEL.instantiate()
    add_child(model)
    flight_root = Node3D.new()
    flight_root.name = "LedgeFlightRoot"
    add_child(flight_root)
    animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
    for library_name in animation_player.get_animation_library_list():
        var source = animation_player.get_animation_library(library_name)
        var library := AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation = source.get_animation(clip).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Walk", "Run", "Block"] else Animation.LOOP_NONE
            library.add_animation(clip, animation)
        animation_player.remove_animation_library(library_name)
        animation_player.add_animation_library(library_name, library)
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var material: StandardMaterial3D = mesh.get_active_material(surface).duplicate()
            # Preserve the authored green skin/leafage and connected orange glasses.
            material.metallic = 0.0
            material.roughness = 0.75
            material.emission_enabled = false
            mesh.set_surface_override_material(surface, material)
    sync_pose(true, Vector3.ZERO, false, false, "", 1.0, 0.0)
    _setup_laser()

# ---- Laser Blast: clip library + bone-mounted holo gun (hidden unless the move shows it) ----
const LASER_LIB := preload("res://assets/teknium/laser/laser_blast_20260928.tres")
const LASER_GUN := preload("res://assets/teknium/laser/laser_gun.tscn")
var laser_gun: Node3D
var laser_holo: ShaderMaterial
# Holo glow: additive teal fresnel edge so the dark gun reads at gameplay camera distance;
# `fill` adds a full teal wash during materialize/dematerialize.
const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(0.05, 0.95, 0.85, 1.0);
uniform float rim = 0.9;
uniform float fill = 0.0;
void fragment() {
    float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
    ALBEDO = tint.rgb * (edge * rim * 1.6 + fill * 0.85);
}
"""
func _setup_laser() -> void:
    if not animation_player.has_animation_library("laser"):
        animation_player.add_animation_library("laser", LASER_LIB.duplicate(true))
    var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    var mount := BoneAttachment3D.new(); mount.name = "LaserGunMount"; mount.bone_name = "RightHand"
    skeleton.add_child(mount)
    laser_gun = LASER_GUN.instantiate(); mount.add_child(laser_gun)
    var shader := Shader.new(); shader.code = HOLO_SHADER
    laser_holo = ShaderMaterial.new(); laser_holo.shader = shader
    var gun_mesh: MeshInstance3D = laser_gun.get_node("GunMesh")
    gun_mesh.material_overlay = laser_holo
    gun_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    laser_gun.visible = false
func laser_gun_state(amount: float, holo: float, flicker_off: bool) -> void:
    if laser_gun == null: return
    laser_gun.visible = amount > 0.01 and not flicker_off
    laser_gun.scale = Vector3.ONE * maxf(amount, 0.001)
    # Baseline teal wash: the gun is only ~22x7 px at gameplay zoom, so a rim alone is invisible.
    laser_holo.set_shader_parameter("fill", maxf(clampf(holo, 0.0, 1.0), 0.45))
    laser_holo.set_shader_parameter("rim", 1.2)
func laser_muzzle() -> Vector3:
    if laser_gun == null: return global_position + Vector3(0, 1.5, 0)
    var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    skeleton.force_update_all_bone_transforms()
    var bone_xf: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
    # Muzzle at full gun size (scale only animates the holo pop), independent of the attachment's update timing.
    return bone_xf * laser_gun.get_node("Muzzle").position

func choose_clip(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String) -> String:
    if interrupted: return "Hit"
    if shielding or active_move == "CHARGING": return "Block"
    match active_move:
        "PROJECTILE": return "Projectile"
        "CHARGE RELEASE": return "MageSpell"
        "RISING STRIKE": return "RaiseWall"
        "LOW SWEEP", "DOWN STRIKE": return "Kick"
        "SIDE STRIKE", "AIR STRIKE", "UPPERCUT", "UP AIR": return "Punch"
    if not grounded: return "Jump"
    if grounded and absf(motion.x) > 0.2:
        return "Run" if absf(motion.x) >= 4.0 else "Walk"
    return "Idle"

func sync_pose(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String, facing: float, delta: float) -> void:
    if animation_player == null: return
    model.rotation.y = facing * PI / 2.0
    if grounded:
        jump_active = false
        jump_elapsed = 0.0
    elif jump_active:
        jump_elapsed = minf(jump_elapsed + maxf(delta, 0.0), animation_player.get_animation("Jump").length)
    var clip := choose_clip(grounded, motion, interrupted, shielding, active_move)
    var offset: float = GROUNDED_OFFSETS.get(clip, 0.0) if grounded else 0.0
    if offset != placement_target:
        placement_from = position.y
        placement_target = offset
        placement_elapsed = 0.0
    placement_elapsed = minf(placement_elapsed + maxf(delta, 0.0), 0.06)
    # Match the existing 0.06s animation crossfade. Jump uses a hard source cut;
    # zero-delta frozen poses are exact, including setup and numerical reviews.
    if delta <= 0.0 or clip == "Jump":
        placement_from = offset
        placement_elapsed = 0.06
        position.y = offset
    else:
        position.y = lerpf(placement_from, offset, placement_elapsed / 0.06)
    var animation := animation_player.get_animation(clip)
    if clip == "Jump":
        # No animation root travel; physics owns height. Walking off a ledge
        # holds the final approved pose rather than inventing a fall clip.
        if current_clip != clip: animation_player.play(clip, 0.0)
        current_clip = clip
        animation_player.speed_scale = 1.0
        animation_player.seek(jump_elapsed if jump_active else animation.length, true)
        animation_player.pause()
        return
    var duration: float = {"Projectile": 0.55, "MageSpell": 0.7, "RaiseWall": 0.65, "Punch": 0.32, "Kick": 0.32}.get(clip, animation.length)
    animation_player.speed_scale = animation.length / maxf(duration, 0.001)
    if current_clip == clip:
        if not animation_player.is_playing(): animation_player.play(clip)
        return
    current_clip = clip
    animation_player.play(clip, 0.06)
    animation_player.advance(maxf(delta, 0.0))

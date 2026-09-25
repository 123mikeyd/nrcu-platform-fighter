extends Node3D
# Presentation only. Fighter retains all movement, collision and combat timing.
const MODEL = preload("res://assets/ice_mage/ice_mage_combat.glb")
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := ""
var fallback_label := ""
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
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        for surface in mesh.mesh.get_surface_count():
            var material: StandardMaterial3D = mesh.get_active_material(surface).duplicate()
            material.emission_enabled = false
            mesh.set_surface_override_material(surface,material)
    sync_pose(true,Vector3.ZERO,false,false,"",1.0,0.0)
func choose_clip(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String) -> String:
    if not grounded or interrupted or shielding or not active_move.is_empty(): return "Idle"
    if absf(motion.x)>0.2: return "Run" if absf(motion.x)>=4.0 else "Walk"
    return "Idle"
func sync_pose(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, active_move: String, facing: float, delta: float, attack_clip: String = "", attack_elapsed: float = 0.0) -> void:
    if animation_player==null: return
    if not attack_clip.is_empty() and not interrupted:
        fallback_label = ""
        model.rotation.y = facing * PI / 2.0
        current_clip = attack_clip
        animation_player.play(attack_clip)
        animation_player.seek(attack_elapsed, true)
        animation_player.pause()
        return
    model.rotation.y = facing * PI / 2.0
    fallback_label = ""
    if not grounded: fallback_label = "Airborne: Idle fallback"
    elif interrupted or shielding or not active_move.is_empty(): fallback_label = "Combat: Idle fallback (baseline mechanics)"
    var clip = choose_clip(grounded,motion,interrupted,shielding,active_move)
    animation_player.speed_scale = 1.0
    if current_clip==clip and animation_player.is_playing(): return
    current_clip=clip
    animation_player.play(clip,0.1)
    animation_player.advance(maxf(delta,0.0))

extends Node3D
# First-pass girl only. Combat remains the shared prototype kit, not demon powers.
const MODEL = preload("res://assets/mephisto/mephisto_girl.glb")
const VISUAL_SCALE := 1.25
const FLOOR_OFFSET := 0.04
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := "Idle"
var fallback_label := ""
func _ready() -> void:
    scale = Vector3.ONE * VISUAL_SCALE
    position.y = FLOOR_OFFSET
    model = MODEL.instantiate()
    add_child(model)
    animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
    for library_name in animation_player.get_animation_library_list():
        var source = animation_player.get_animation_library(library_name)
        var library = AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation = source.get_animation(clip).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Run"] else Animation.LOOP_NONE
            library.add_animation(clip, animation)
        animation_player.remove_animation_library(library_name)
        animation_player.add_animation_library(library_name, library)
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var source = mesh.get_active_material(surface)
            if source is StandardMaterial3D:
                var material: StandardMaterial3D = source.duplicate()
                material.metallic = 0.0
                material.roughness = 0.75
                material.emission_enabled = false
                mesh.set_surface_override_material(surface, material)
    sync_pose(true, Vector3.ZERO, false, false, false, 1.0)
func sync_pose(grounded: bool, motion: Vector3, hurt: bool, busy: bool, disabled: bool, facing: float) -> void:
    if not animation_player: return
    model.rotation.y = facing * PI / 2.0
    var clip := "Hit" if hurt and not disabled else ("Run" if grounded and absf(motion.x) > 0.2 and not busy and not disabled else "Idle")
    var held := clip == "Idle" and (not grounded or busy or disabled)
    fallback_label = "Held Idle: no jump/fall/attack animation assigned" if held else ("Provisional Block8 reaction" if clip == "Hit" else "")
    if current_clip != clip or animation_player.assigned_animation != clip:
        animation_player.play(clip, 0.10)
    elif not animation_player.is_playing() and (clip != "Hit" or animation_player.current_animation_position < animation_player.get_animation(clip).length):
        animation_player.play(clip)
    current_clip = clip
    if held:
        animation_player.play("Idle")
        animation_player.seek(0, true)
        animation_player.pause()

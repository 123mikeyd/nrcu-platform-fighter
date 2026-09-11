extends Node3D
const VISUAL_SCALE := 1.75
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := "Idle"
var elapsed := 0.0
func _ready() -> void:
    scale = Vector3.ONE * VISUAL_SCALE
    position.y = -0.108
    model = load("res://assets/bobo/bobo.glb").instantiate()
    add_child(model)
    animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
    for name in animation_player.get_animation_library_list():
        var source = animation_player.get_animation_library(name)
        var library := AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation = source.get_animation(clip).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if clip == "Idle" else Animation.LOOP_NONE
            library.add_animation(clip,animation)
        animation_player.remove_animation_library(name)
        animation_player.add_animation_library(name,library)
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var source = mesh.get_active_material(surface)
            if source is StandardMaterial3D:
                var material: StandardMaterial3D = source.duplicate()
                material.metallic = 0
                material.roughness = 0.8
                material.emission_enabled = false
                mesh.set_surface_override_material(surface,material)
    react("Idle")
func react(clip: String) -> void:
    current_clip = clip
    elapsed = 0
    animation_player.play(clip,0.08)
    animation_player.seek(0,true)
func tick(delta: float) -> void:
    elapsed += delta
    if current_clip not in ["Idle","Defeat"] and elapsed >= animation_player.get_animation(current_clip).length:
        react("Idle")
    elif not animation_player.is_playing() and current_clip == "Idle":
        animation_player.play("Idle")

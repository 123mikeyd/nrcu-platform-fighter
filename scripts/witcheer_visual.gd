extends Node3D
# Source-backed provisional move cuts; existing Run remains untouched.
const MODEL = preload("res://assets/witcheer/witcheer_run.glb")
const VISUAL_SCALE := 1.2
const FLOOR_OFFSET := 0.13
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := "Run"
var fallback_label := ""
var accent: MeshInstance3D
var accent_material: StandardMaterial3D
var timings: Dictionary
func _ready() -> void:
    timings=JSON.parse_string(FileAccess.get_file_as_string("res://assets/witcheer/move_manifest.json")).moves
    accent=MeshInstance3D.new()
    accent.name="ContactAccent"
    var ring=TorusMesh.new()
    ring.inner_radius=0.43
    ring.outer_radius=0.48
    ring.rings=24
    ring.ring_segments=6
    accent.mesh=ring
    accent.rotation.x=PI/2
    accent_material=StandardMaterial3D.new()
    accent_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
    accent_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    accent_material.albedo_color=Color(0.82,0.7,0.3,0.32)
    accent.material_override=accent_material
    accent.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(accent)
    accent.visible=false
    scale=Vector3.ONE*VISUAL_SCALE
    position.y=FLOOR_OFFSET
    model=MODEL.instantiate()
    add_child(model)
    animation_player=model.find_children("*","AnimationPlayer",true,false)[0]
    for name in animation_player.get_animation_library_list():
        var source=animation_player.get_animation_library(name)
        var library=AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation=source.get_animation(clip).duplicate(true)
            animation.loop_mode=Animation.LOOP_LINEAR if clip=="Run" else Animation.LOOP_NONE
            library.add_animation(clip,animation)
        animation_player.remove_animation_library(name)
        animation_player.add_animation_library(name,library)
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        for surface in mesh.mesh.get_surface_count():
            var material: StandardMaterial3D=mesh.get_active_material(surface).duplicate()
            material.metallic=0
            material.roughness=0.75
            material.emission_enabled=false
            mesh.set_surface_override_material(surface,material)
    sync_pose(true,Vector3.ZERO,false,false,1.0)
func show_move(clip: String, elapsed: float, facing: float) -> void:
    if not animation_player or not animation_player.has_animation(clip): return
    model.rotation.y = facing * PI / 2.0
    current_clip = clip
    fallback_label = "Provisional source cut"
    var age: float=elapsed-float(timings[clip].contact_time)
    accent.visible=clip!="Celebration" and age>=-0.00001 and age<0.22
    accent.position=Vector3(facing*0.7,1.0,0.12)
    accent.scale=Vector3.ONE*(1.6 if clip=="CaneSweep" else 1.0)
    accent_material.albedo_color.a=0.32*clampf(1.0-age/0.22,0,1)
    animation_player.play(clip)
    animation_player.seek(minf(elapsed, animation_player.get_animation(clip).length), true)
    animation_player.pause()

func hand_world() -> Vector3:
    var skeleton: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
    skeleton.force_update_all_bone_transforms()
    return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin

func sync_pose(grounded: bool, motion: Vector3, interrupted: bool, shielding: bool, facing: float) -> void:
    current_clip = "Run"
    if accent: accent.visible=false
    if not animation_player: return
    model.rotation.y=facing*PI/2.0
    var running=grounded and absf(motion.x)>0.2 and not interrupted and not shielding
    fallback_label="" if running else "Held Run pose (no dedicated Idle/fall)"
    if running:
        if animation_player.assigned_animation != "Run" or not animation_player.is_playing(): animation_player.play("Run")
    else:
        animation_player.play("Run")
        animation_player.seek(0,true)
        animation_player.pause()

extends Node3D
var canonical = preload("res://scripts/core/presentation/canonical_collision_presenter.gd").new()
func present_canonical(record: Dictionary) -> void:
    canonical.present(self, record)
## Teknium-only render adapter. No gameplay callbacks, collisions or contacts.
const State = preload("res://scripts/core/presentation/presentation_state.gd")
const MODEL = preload("res://assets/teknium/teknium_animations.glb")
# Preserve P2's approved legacy placement constants; no new floor fitting.
const OFFSETS := {"Idle": -0.224, "Walk": 0.066, "Run": 0.086, "Block": -0.061, "Hit": -0.112}
var state = State.new()
var model: Node3D
var animation_player: AnimationPlayer
var play_count := 0
var facing := 1.0
# Keep overrides alive until all child meshes finish teardown.
var _materials: Array[Material] = []
var skeleton: Skeleton3D
var from_poses: Array[Transform3D] = []
var from_offset := 0.0
var last_transition := -1
var committed_identity: Array = []
func _ready() -> void:
    scale = Vector3.ONE * 1.25
    model = MODEL.instantiate()
    add_child(model)
    animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
    skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
    animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    canonical.configure(self)
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var material: StandardMaterial3D = mesh.get_active_material(surface).duplicate()
            material.metallic = 0.0
            material.roughness = 0.75
            material.emission_enabled = false
            _materials.append(material)
            mesh.set_surface_override_material(surface, material)
func reset() -> void:
    canonical.reset(self)
    state.reset()
    animation_player.stop()
    from_poses.clear()
    last_transition = -1
    facing = 1.0
    committed_identity.clear()

# Optional match-owned grab request. No local clock, relation or gameplay writer.
var grab_pose_active := false
var grab_clips_prepared := false
func _prepare_grab_clips() -> void:
    if grab_clips_prepared: return
    grab_clips_prepared = true
    # Private playback resources: source keys/durations and imported library stay
    # untouched. GrabLoop must sample its inclusive endpoint, not wrap to zero.
    for library_name in animation_player.get_animation_library_list():
        var source := animation_player.get_animation_library(library_name)
        var library := AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation = source.get_animation(clip)
            if clip in ["GrabStart", "GrabLoop", "GrabEnd", "Electrocution"]:
                animation = animation.duplicate(true)
                animation.loop_mode = Animation.LOOP_NONE
            library.add_animation(clip, animation)
        animation_player.remove_animation_library(library_name)
        animation_player.add_animation_library(library_name, library)

func present(snapshot: Dictionary, tick: int) -> void:
    # Optional lab lifecycle revision: actor-local time may stay fixed while an
    # external disable/cancel/hit retires the committed episode. Reconcile that
    # change without inventing an animation tick; old callers stay unchanged.
    var identity: Array = snapshot.get("committed_identity", [])
    if not identity.is_empty():
        if tick == state.last_tick and identity != committed_identity: reset()
        committed_identity = identity.duplicate()
    var request: Dictionary = snapshot.get("grab_pose", {})
    if not request.is_empty():
        _prepare_grab_clips()
        grab_pose_active = true
        facing = float(snapshot.get("facing", facing))
        model.rotation.y = facing * PI / 2.0
        position = Vector3.ZERO # No source magic floor placement or physics jitter.
        var clip: String = request.clip
        if animation_player.assigned_animation != clip:
            animation_player.play(clip, 0.0)
            play_count += 1
        animation_player.seek(minf(request.seconds, animation_player.get_animation(clip).length), true)
        skeleton.force_update_all_bone_transforms()
        return
    if grab_pose_active:
        # Relations may disappear at the same tick during pause/freeze/cancel.
        # Discard the override before applying ordinary locomotion/Hit priority.
        reset()
        committed_identity = identity.duplicate()
        grab_pose_active = false
        position = Vector3.ZERO
    if tick == state.last_tick: return
    if tick < state.last_tick: reset()
    var frozen: bool = snapshot.get("frozen", false) or snapshot.get("hitstop", false) or snapshot.get("status", "") == "frozen"
    var initialized: bool = not state.output.is_empty()
    var pose: Dictionary = state.sample(snapshot, tick)
    if frozen and initialized: return
    if last_transition != pose.transition:
        from_poses.clear()
        for bone in range(skeleton.get_bone_count()):
            from_poses.append(skeleton.get_bone_pose(bone))
        from_offset = position.y
        last_transition = pose.transition
    facing = float(snapshot.get("facing", facing))
    model.rotation.y = facing * PI / 2.0
    position.y = float(OFFSETS.get(pose.clip, pose.get("strike_offset", 0.0))) if snapshot.get("grounded", false) else 0.0
    if animation_player.assigned_animation != pose.clip:
        animation_player.play(pose.clip, 0.0)
        play_count += 1
    var animation := animation_player.get_animation(pose.clip)
    var source_time: float = fmod(pose.seconds, animation.length) if pose.loop else minf(pose.seconds, animation.length * pose.cap)
    if pose.fraction >= 0: source_time = animation.length * pose.fraction
    animation_player.seek(source_time, true)
    if pose.blend < 1.0:
        for bone in range(skeleton.get_bone_count()):
            skeleton.set_bone_pose(bone, from_poses[bone].interpolate_with(skeleton.get_bone_pose(bone), pose.blend))
        if pose.clip != "Jump": position.y = lerpf(from_offset, position.y, pose.blend)
    skeleton.force_update_all_bone_transforms()

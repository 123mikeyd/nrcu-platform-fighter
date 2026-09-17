extends RefCounted
## Render-only sink: no policy, source clock, simulation or geometry queries.
var active := false
var output: Dictionary = {}
var _source_transform := Transform3D.IDENTITY
var _legacy_transform := Transform3D.IDENTITY
var _libraries: Dictionary = {}
var _legacy_animation: StringName = &""

func configure(view: Node3D) -> void:
    _source_transform = view.model.transform
    _legacy_transform = view.transform

func reset(view: Node3D) -> void:
    if not active: return
    view.animation_player.stop()
    # stop() retains assigned_animation. Retire the private clip binding while
    # its library still exists, before callers reset/seek the restored source.
    if not _legacy_animation.is_empty():
        view.animation_player.assigned_animation = _legacy_animation
    for name in _libraries:
        view.animation_player.remove_animation_library(name)
        view.animation_player.add_animation_library(name, _libraries[name])
    _libraries.clear()
    view.transform = _legacy_transform
    view.model.transform = _source_transform
    view.model.visible = true
    view.skeleton.reset_bone_poses()
    output.clear()
    active = false

func present(view: Node3D, record: Dictionary) -> void:
    if not active:
        active = true
        _legacy_animation = view.animation_player.assigned_animation
        if _legacy_animation.is_empty():
            var clips: PackedStringArray = view.animation_player.get_animation_list()
            if not clips.is_empty(): _legacy_animation = clips[0]
        view.animation_player.stop()
        for name in view.animation_player.get_animation_library_list():
            var source: AnimationLibrary = view.animation_player.get_animation_library(name)
            _libraries[name] = source
            var library := AnimationLibrary.new()
            for clip in source.get_animation_list():
                var animation: Animation = source.get_animation(clip).duplicate(true)
                animation.loop_mode = Animation.LOOP_NONE
                library.add_animation(clip, animation)
            view.animation_player.remove_animation_library(name)
            view.animation_player.add_animation_library(name, library)
    var request: Dictionary = record.get("pose_request", {}).get("rendering_request", {})
    if request.get("clip", "") == "SwingPunchV1" and not view.animation_player.has_animation("SwingPunchV1"):
        var derived = preload("res://scripts/core/presentation/teknium_swing_source.gd")
        var library: AnimationLibrary = derived.validated_library(view.skeleton)
        if library != null and request.get("derived_source",{}) == derived.identity():
            view.animation_player.get_animation_library("").add_animation("SwingPunchV1",library.get_animation("SwingPunchV1").duplicate(true))
    var valid: bool = record.get("ok", false) and request.get("blend_policy", "") == "discrete_committed_no_blend" and view.animation_player.has_animation(request.get("clip", ""))
    if request.get("clip", "") == "SwingPunchV1": valid = valid and request.get("derived_source",{}) == preload("res://scripts/core/presentation/teknium_swing_source.gd").identity()
    view.model.visible = valid
    if not valid:
        output.clear()
        return # Invalid lifecycle samples are not a legacy or stale-pose fallback.
    if request == output: return
    view.transform = request.modelplacement
    view.model.transform = _source_transform
    view.skeleton.reset_bone_poses()
    view.animation_player.play(request.clip, 0.0)
    view.animation_player.seek(request.source_seconds, true)
    view.skeleton.force_update_all_bone_transforms()
    output = request.duplicate(true)

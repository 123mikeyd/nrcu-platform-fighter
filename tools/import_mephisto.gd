@tool
extends EditorScenePostImport
# Keep source 30 Hz poses: the default animation optimizer moves limbs by ~6 mm.
func _post_import(scene: Node) -> Object:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    if document.append_from_file(get_source_file(), state) != OK:
        push_error("Mephisto source animation import failed")
        return scene
    var raw := document.generate_scene(state, 30.0, false, true)
    var source: AnimationPlayer = raw.find_children("*", "AnimationPlayer", true, false)[0]
    var target: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
    var library := target.get_animation_library("")
    for clip in ["Idle", "Run", "Hit"]:
        if library.has_animation(clip): library.remove_animation(clip)
        library.add_animation(clip, source.get_animation(clip).duplicate(true))
    raw.free()
    return scene

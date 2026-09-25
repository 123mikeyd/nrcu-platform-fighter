@tool
extends EditorScenePostImport
static func replace_reaction(scene: Node, path: String) -> Node:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    if document.append_from_file(path, state) != OK:
        push_error("Electrocution import failed")
        return scene
    var exact := document.generate_scene(state, 96.0, false, true)
    var source: AnimationPlayer = exact.find_children("*", "AnimationPlayer", true, false)[0]
    var target: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
    if source.has_animation("Electrocution"):
        var library := target.get_animation_library("")
        if library.has_animation("Electrocution"): library.remove_animation("Electrocution")
        library.add_animation("Electrocution", source.get_animation("Electrocution").duplicate(true))
    exact.free()
    return scene
func _post_import(scene: Node) -> Object:
    return replace_reaction(scene, get_source_file())

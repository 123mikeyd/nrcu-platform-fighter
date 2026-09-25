@tool
extends EditorScenePostImport
# Replace only the new attack; retain all existing imported reaction resources.
func _post_import(scene: Node) -> Object:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    if document.append_from_file(get_source_file(), state) != OK:
        push_error("Bobo ThrustSlash raw source import failed")
        return scene
    var raw := document.generate_scene(state,30.0,false,true)
    var source: AnimationPlayer = raw.find_children("*","AnimationPlayer",true,false)[0]
    var target: AnimationPlayer = scene.find_children("*","AnimationPlayer",true,false)[0]
    var library := target.get_animation_library("")
    if library.has_animation("ThrustSlash"): library.remove_animation("ThrustSlash")
    library.add_animation("ThrustSlash",source.get_animation("ThrustSlash").duplicate(true))
    raw.free()
    return scene

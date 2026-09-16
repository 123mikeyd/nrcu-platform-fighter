@tool
extends EditorScenePostImport
# The native 0.8-frame/24 FPS grid is exactly 30 Hz. Keep authored poses,
# not the editor's millimeter-tolerance animation reduction.
func _post_import(scene: Node) -> Object:
    var document=GLTFDocument.new()
    var state=GLTFState.new()
    if document.append_from_file(get_source_file(),state)!=OK:
        push_error("Mephisto companion raw source import failed")
        return scene
    var raw=document.generate_scene(state,30.0,false,true)
    var source: AnimationPlayer=raw.find_children("*","AnimationPlayer",true,false)[0]
    var target: AnimationPlayer=scene.find_children("*","AnimationPlayer",true,false)[0]
    for library_name in source.get_animation_library_list():
        if target.has_animation_library(library_name):target.remove_animation_library(library_name)
        target.add_animation_library(library_name,source.get_animation_library(library_name).duplicate(true))
    raw.free()
    return scene

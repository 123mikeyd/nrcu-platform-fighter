@tool
extends EditorScenePostImport
# Preserve the ten established 30Hz imported clips. Only the four approved
# magic cuts need 24Hz baking so source events do not land between re-baked keys.
func _post_import(scene: Node) -> Object:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_file(get_source_file(), state)
    if error != OK:
        push_error("Teknium exact magic import failed: " + str(error))
        return scene
    var exact := document.generate_scene(state, 24.0, false, true)
    var source_player: AnimationPlayer = exact.find_children("*", "AnimationPlayer", true, false)[0]
    var target_player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
    var library := target_player.get_animation_library("")
    for clip in ["ForcePush", "GrabStart", "GrabLoop", "GrabEnd"]:
        if library.has_animation(clip): library.remove_animation(clip)
        library.add_animation(clip, source_player.get_animation(clip).duplicate(true))
    exact.free()
    # Keep the approved jump's every 30Hz source sample; the default scene
    # optimizer otherwise removes keys and shifts the head/limb poses.
    var jump_state := GLTFState.new()
    var jump_error := document.append_from_file(get_source_file(), jump_state)
    if jump_error != OK:
        push_error("Teknium exact jump import failed: " + str(jump_error))
        return scene
    var jump_exact := document.generate_scene(jump_state, 30.0, false, true)
    var jump_player: AnimationPlayer = jump_exact.find_children("*", "AnimationPlayer", true, false)[0]
    if jump_player.has_animation("Jump"):
        if library.has_animation("Jump"): library.remove_animation("Jump")
        library.add_animation("Jump", jump_player.get_animation("Jump").duplicate(true))
    jump_exact.free()
    return preload("res://tools/import_electrocution.gd").replace_reaction(scene, get_source_file())

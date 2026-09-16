@tool
extends EditorScenePostImport
# Only approved Moves2 clips use dense source sampling; old import stays intact.
func _post_import(scene: Node) -> Object:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_file(get_source_file(), state)
    if error != OK:
        push_error("Doge Moves2 import failed: " + str(error))
        return scene
    var exact := document.generate_scene(state, 96.0, false, true)
    var source: AnimationPlayer = exact.find_children("*", "AnimationPlayer", true, false)[0]
    var target: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
    var library := target.get_animation_library("")
    for clip in ["JumpMoves2", "MidairMoves2", "SupermanMoves2", "HitMoves2", "GroundCharge", "GroundRush", "Electrocution"]:
        if library.has_animation(clip): library.remove_animation(clip)
        library.add_animation(clip, source.get_animation(clip).duplicate(true))
    exact.free()
    # Approved saved v003: dense 480-Hz bake preserves manual subframe curves.
    # Authored timing remains frames 0..60 at 60 FPS (one second).
    var punch_state := GLTFState.new()
    if document.append_from_file(get_source_file(), punch_state) != OK:
        push_error("Doge two-piece source import failed")
        return scene
    var punch_scene := document.generate_scene(punch_state, 480.0, false, true)
    var punch_player: AnimationPlayer = punch_scene.find_children("*", "AnimationPlayer", true, false)[0]
    if punch_player.has_animation("TysonTwoPiece"):
        if library.has_animation("TysonTwoPiece"): library.remove_animation("TysonTwoPiece")
        library.add_animation("TysonTwoPiece", punch_player.get_animation("TysonTwoPiece").duplicate(true))
    punch_scene.free()
    var kick_state := GLTFState.new()
    if document.append_from_file(get_source_file(), kick_state) == OK:
        var kick_scene := document.generate_scene(kick_state, 120.0, false, true)
        var kick_player: AnimationPlayer = kick_scene.find_children("*", "AnimationPlayer", true, false)[0]
        if kick_player.has_animation("GoalkeeperKick"):
            if library.has_animation("GoalkeeperKick"): library.remove_animation("GoalkeeperKick")
            library.add_animation("GoalkeeperKick", kick_player.get_animation("GoalkeeperKick").duplicate(true))
        kick_scene.free()
    return scene

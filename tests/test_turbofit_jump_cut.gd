extends SceneTree

func _initialize() -> void:
    var scene = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
    root.add_child(scene)
    var players = scene.find_children("*", "AnimationPlayer", true, false)
    var failed := false
    if players.is_empty():
        print("FAIL: missing imported AnimationPlayer")
        quit(1)
        return
    var player: AnimationPlayer = players[0]
    var jump: Animation = player.get_animation("Jump")
    if not is_equal_approx(jump.length, 43.0 / 30.0):
        print("FAIL: Jump must retain source15-58 inclusive at 30fps, not game frame15")
        failed = true
    var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/turbofit/animation_manifest.json"))
    if int(manifest.clips.Jump.source_frames[0]) != 15 or int(manifest.clips.Jump.source_frames[1]) != 58 or int(manifest.clips.Jump.output_frames) != 44:
        print("FAIL: exact source cut metadata")
        failed = true
    for clip in {"Landing": 24.0 / 30.0, "FallLoop": 24.0 / 30.0, "GoalkeeperKick": 59.0 / 30.0, "AirSideKick": 15.0 / 30.0}:
        var expected: float = {"Landing": 24.0 / 30.0, "FallLoop": 24.0 / 30.0, "GoalkeeperKick": 59.0 / 30.0, "AirSideKick": 15.0 / 30.0}[clip]
        if not is_equal_approx(player.get_animation(clip).length, expected):
            print("FAIL: preserved clip duration " + clip)
            failed = true
    scene.free()
    if not failed:
        print("PASS: Jump source15-58, 44 authored samples / 43 intervals at 30fps; other approved durations preserved")
    quit(1 if failed else 0)

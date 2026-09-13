extends SceneTree
# Arena scene contract: a fresh main.tscn can start a two-player match.
#
# Scenes are loaded inside run() (deferred by one frame), never at _init —
# autoload identifiers only compile once the main loop registered them.

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    if packed == null:
        push_error("RED: main arena scene is missing")
        quit(1)
        return
    var arena := packed.instantiate()
    root.add_child(arena)
    await process_frame
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[1].kind = "human"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    if not arena.setup.visible or not arena.start_match(slots, false):
        push_error("Setup must open and allow starting a two-player match")
        quit(1)
        return
    var fighters := get_nodes_in_group("fighters")
    if fighters.size() != 2:
        push_error("Expected 2 playable fighters, found %d" % fighters.size())
        arena.queue_free()
        quit(1)
        return
    print("PASS: main arena creates two fighters")
    arena.queue_free()
    quit(0)

extends SceneTree

func _init() -> void:
    var path := "res://scripts/match_config.gd"
    if not FileAccess.file_exists(path):
        push_error("RED: match configuration missing")
        quit(1)
        return
    var config = load(path)
    var slots: Array = config.default_slots()
    var failures := 0
    if slots.size() != 4 or config.validate(slots, false) != "":
        failures += 1
    slots[1].character = slots[0].character
    if config.validate(slots, false) != "":
        failures += 1
    for slot in slots:
        slot.team = 0
    if config.validate(slots, true) == "":
        failures += 1
    slots[2].team = 1
    if config.validate(slots, true) != "":
        failures += 1
    slots[0].kind = "empty"
    slots[1].kind = "empty"
    slots[2].kind = "empty"
    if config.validate(slots, false) == "":
        failures += 1
    if failures:
        push_error("FAIL: match config assertions: %d" % failures)
    else:
        print("PASS: four slots, duplicates, team and participant validation")
    quit(1 if failures else 0)

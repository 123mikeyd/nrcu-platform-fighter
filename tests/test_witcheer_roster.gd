extends SceneTree
func _initialize(): call_deferred("run")
func run():
    var roster = load("res://scripts/roster.gd")
    var config = load("res://scripts/match_config.gd")
    if not ("witcheer" in roster.ids() and "witcheer" in config.CHARACTERS and roster.display_name("witcheer") == "Witcheer"):
        printerr("FAIL: Witcheer must be selectable by his own identity"); quit(1); return
    if roster.ids()!=config.CHARACTERS or config.NAMES[config.CHARACTERS.find("witcheer")]!="Witcheer":
        printerr("FAIL: exact roster/config order and unambiguous combat-enabled name");quit(1);return
    var slots = config.default_slots()
    slots[0].character = "witcheer"
    if config.validate(slots, false) != "":
        printerr("FAIL: Witcheer match validation"); quit(1); return
    if config.default_slots()[0].character != "teknium":
        printerr("FAIL: preserve launch default"); quit(1); return
    print("PASS: selectable Witcheer identity and unchanged default")
    quit()

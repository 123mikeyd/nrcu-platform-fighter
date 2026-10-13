extends SceneTree
# Isolate persistence before the main scene is instantiated.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func run() -> void:
	var unlocks = load("res://scripts/unlocks.gd")
	unlocks.path_override = "user://costume_integration_unlocks.json"
	FileAccess.open(unlocks.path_override, FileAccess.WRITE).store_string("{}")
	var config = load("res://scripts/match_config.gd")
	check(config.costume_ids("ggb") == ["01", "02", "03", "05", "06", "07"], "GGB exposes approved stable IDs including Amber Honey")
	check(config.costume_ids("witcheer") == ["01", "02", "03", "04"], "Witcheer exposes approved clothing set")
	check(config.costume_ids("bobo") == ["01", "02", "03", "04"], "Bobo exposes four approved metallic stable IDs")
	check(config.costume_ids("doge_man") == ["01", "02", "04", "07"], "Doge exposes four reviewed atlas stable IDs")
	var slots: Array = config.default_slots()
	check(slots.all(func(slot): return slot.has("costume") and config.valid_costume(slot.character, slot.costume)), "every default slot has a valid stable costume")
	slots[0].costume = "invalid"
	check(not config.validate(slots, false).is_empty(), "invalid costume is rejected before match launch")
	print("COSTUME_INTEGRATION_COMPLETE checks=%d failures=%d" % [checks, failures])
	print("COSTUME_INTEGRATION_COMPLETE");quit(1 if failures else 0)

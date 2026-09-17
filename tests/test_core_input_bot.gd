extends SceneTree
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var path := "res://scripts/core/input/bot_input_source.gd"
	if not ResourceLoader.exists(path):
		push_error("bot source missing")
		quit(1)
		return
	var bot = load(path).new()
	var actor := Vector3.ZERO
	var target := Vector3(4, 0, 0)
	var frame = bot.sample(1, actor, target)
	check(frame.tick == 1 and frame.axis.x == 1 and frame.source_id == "bot", "bot approaches target through intent")
	check(actor == Vector3.ZERO and target == Vector3(4, 0, 0), "positions untouched")
	frame = bot.sample(2, actor, Vector3(-4, 0, 0))
	check(frame.axis.x == -1, "mirrored approach")
	frame = bot.sample(3, actor, actor)
	check(frame.axis == Vector2.ZERO and frame.pressed.attack, "in-range attack intent")
	check(not bot.sample(4, actor, actor).pressed.has("attack"), "held attack no repeated edge")
	frame = bot.sample(5, actor, Vector3(0, 3, 0))
	check(frame.pressed.jump, "target above jump intent")
	frame = bot.sample(6, actor, Vector3(4, 0, 0))
	check(frame.released.jump and frame.released.attack, "bot releases intents")
	bot.reset()
	check(bot.sample(7, actor, actor).pressed.attack, "bot reset clears history")
	if failures == 0: print("PASS core input bot")
	quit(failures)

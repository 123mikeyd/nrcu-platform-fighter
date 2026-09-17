extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)
func tick(lab) -> void:
    await physics_frame
    lab._physics_process(1.0 / 60.0)
func run() -> void:
    if not ResourceLoader.exists("res://scenes/combat_lab.tscn"):
        check(false, "playable combat scene exists")
        quit(1)
        return
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for i in range(40): await tick(lab)
    check(lab.sources[0].bindings.attack == KEY_F and lab.sources[1].bindings.attack == KEY_K, "stable physical strike keys")
    key(KEY_F, true)
    await tick(lab)
    check(lab.simulation.fighters[2].percent == 8.0, "physical queued F damages P2")
    check(lab.actors[1].velocity.x > 0 and lab.actors[1].runtime.states.status == "hitstun", "physical F launches real actor")
    check(lab.simulation.fighters[1].move_id == "SIDE STRIKE", "settled arena selects side strike")
    check(lab.imported_visuals.size() == 2, "two Teknium presenters")
    key(KEY_F, false)
    lab.free()
    if failures == 0: print("PASS: combat lab physical strike tracer")
    quit(1 if failures else 0)

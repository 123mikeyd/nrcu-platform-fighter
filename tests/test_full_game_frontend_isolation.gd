extends "res://tests/test_full_game_flow.gd"
## The preview owns native Controls, not v0.3's semantic frontend service.
var failures := 0
var semantic_events := 0
func check(ok: bool, message: String):
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1
func run():
	var service = root.get_node("FrontendInput")
	service.set_scope(service.SCOPE_FRONTEND)
	var previous_mouse_mode = Input.mouse_mode
	service.confirm_pressed.connect(func(): semantic_events += 1)
	service.nav_action.connect(func(_action): semantic_events += 1)
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	check(service.scope() == service.SCOPE_GAMEPLAY, "preview suspends upstream semantic focus")
	check(not root.get_node("Cursor").hand.visible, "upstream hand hidden in preview")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "native preview pointer remains visible")
	await click("ExperimentalPlay")
	check(app.state == "select", "native preview menu remains interactive")
	# Release GUI focus so this tests unhandled navigation as well as _input.
	root.gui_release_focus()
	for code in [KEY_SPACE, KEY_ENTER, KEY_LEFT, KEY_RIGHT]:
		key(code, true)
		await frames(1)
		key(code, false)
		await frames(1)
	check(semantic_events == 0, "preview keys do not emit upstream confirm or navigation")
	app.free()
	await frames(2)
	check(service.scope() == service.SCOPE_FRONTEND, "preview exit restores upstream scope")
	check(root.get_node("Cursor").hand.visible, "preview exit restores upstream hand")
	check(Input.mouse_mode == previous_mouse_mode, "preview exit restores prior pointer policy")
	if failures == 0: print("PASS: experimental frontend input isolation")
	quit(1 if failures else 0)

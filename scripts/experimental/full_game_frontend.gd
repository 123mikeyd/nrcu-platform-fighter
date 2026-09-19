extends Node
## Opt in by launching this scene, not by changing the default game route.
const Roster = preload("res://scripts/roster.gd")
var state := "menu"
var session
var page: Control
var ui: CanvasLayer
var column: VBoxContainer
var choices: Array = []
var selected_fighters: Array = ["teknium","turbofit"]
var input_owner := "sparring_easy"
var selected_devices: Array = [-1,-1]
var device_choices: Array = []
var hud: Label
var ready_ticks := 0
var paused_from := "match"
var _upstream_input: Node
var _previous_scope := "frontend"
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
func _ready():
	# Native Controls and the existing match sampler own this entire preview.
	# Do not let v0.3's persistent semantic frontend interpret gameplay keys.
	_upstream_input = get_node_or_null("/root/FrontendInput")
	_previous_mouse_mode = Input.mouse_mode
	if _upstream_input != null:
		_previous_scope = _upstream_input.scope()
		_upstream_input.set_scope(_upstream_input.SCOPE_GAMEPLAY)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().title = "NRCU — Experimental Freeplay"
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	Input.joy_connection_changed.connect(_on_device_connection)
	show_menu()
func _exit_tree():
	if is_instance_valid(_upstream_input):
		_upstream_input.set_scope(_previous_scope)
	Input.mouse_mode = _previous_mouse_mode
func clear_page(title: String):
	if is_instance_valid(page):
		ui.remove_child(page)
		page.queue_free()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.theme = preload("res://scripts/demo_style.gd").make()
	ui.add_child(page)
	var shade := ColorRect.new()
	shade.color = Color(0.04,0.09,0.1,0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	page.add_child(margin)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	margin.add_child(column)
	label(title,30)
func label(text: String, font_size: int = 18):
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",font_size)
	column.add_child(item)
	return item
func button(id: String,text: String, action: Callable):
	var item := Button.new()
	item.name = id
	item.text = text
	item.custom_minimum_size.y = 46
	column.add_child(item)
	item.pressed.connect(action)
	return item
func show_menu():
	dispose_session()
	state = "menu"
	clear_page("NRCU / EXPERIMENTAL FREEPLAY")
	label("A separate two-fighter preview. The original game, all seven fighters and Story Mode remain available unchanged.")
	label("Teknium & Turbofit · anatomical contacts · grounded jostle · three stocks\nToy Shelf · Sparring / Easy or original bot decisions\nNot a complete roster migration. Native controllers supported; FX/art parity remains incomplete.")
	button("ExperimentalPlay","Play experimental Freeplay",show_select).grab_focus()
	button("OriginalGame","Original Game — full roster / Story / other stages",func(): get_tree().change_scene_to_file("res://scenes/home.tscn"))
func show_select():
	dispose_session()
	state = "select"
	clear_page("CHOOSE YOUR MATCH")
	choices.clear()
	device_choices.clear()
	for slot in 2:
		label("P%d / %s" % [slot+1,"Human" if slot == 0 else "Opponent"])
		var row := HBoxContainer.new()
		column.add_child(row)
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.name = "Fighter%d" % (slot+1)
		choice.custom_minimum_size.y = 42
		for id in Roster.ids():
			var unsupported: bool = id not in ["teknium","turbofit"]
			choice.add_item(Roster.display_name(id) + (" — Original Game only" if unsupported else ""))
			var index := choice.item_count-1
			choice.set_item_metadata(index,id)
			choice.set_item_disabled(index,unsupported)
		choice.select(Roster.ids().find(selected_fighters[slot]))
		row.add_child(choice)
		choice.item_selected.connect(func(i): selected_fighters[slot] = choice.get_item_metadata(i))
		choices.append(choice)
		var device := OptionButton.new()
		device.name = "Device%d" % (slot+1)
		device.custom_minimum_size = Vector2(235,42)
		device.add_item("Keyboard P%d" % (slot+1))
		device.set_item_metadata(0,-1)
		for pad_id in Input.get_connected_joypads():
			device.add_item("Controller %d" % (pad_id+1))
			device.set_item_metadata(device.item_count-1,pad_id)
			if selected_devices[slot] == pad_id: device.select(device.item_count-1)
		if selected_devices[slot] >= 0 and not Input.get_connected_joypads().has(selected_devices[slot]):
			device.add_item("Controller %d (disconnected)" % (selected_devices[slot]+1))
			device.set_item_metadata(device.item_count-1,selected_devices[slot])
			device.select(device.item_count-1)
		device.disabled = slot == 1 and input_owner != "human"
		device.item_selected.connect(func(i): selected_devices[slot] = device.get_item_metadata(i))
		row.add_child(device)
		device_choices.append(device)
	label("Toy Shelf / Bedroom · authored wide combat shelf. Other stages: Original Game.")
	var opponents := OptionButton.new()
	opponents.name = "OpponentOwner"
	opponents.custom_minimum_size.y = 42
	var ids = preload("res://scripts/experimental/full_game_config.gd").OWNERS
	var names = ["Sparring / Easy (ours)","P2 Human keyboard","Mikey bot / Easy (adapted)","Mikey bot / Normal (adapted)","Mikey bot / Hard (adapted)"]
	for i in ids.size():
		opponents.add_item(names[i])
		opponents.set_item_metadata(i,ids[i])
	opponents.select(ids.find(input_owner))
	column.add_child(opponents)
	opponents.item_selected.connect(func(i): input_owner = ids[i]; device_choices[1].disabled = input_owner != "human")
	label("P1: A/D move · Space jump · WASD aim · F basic · G special · E shield\nP2: arrows move/aim · Enter jump · K basic · L special · O shield\nPad: left stick move/aim · A jump · X basic · B special · LB shield · Start pause\nUp + special: recovery · Teknium neutral special: grab · shield + move: dodge\nToy Shelf is solid (no drop-through platforms) · Esc pauses · B backs out of selection",14)
	button("StartMatch","START 3-STOCK MATCH",start_match)
	button("BackMenu","Back to menu",show_menu)
func start_match():
	for slot in 2: selected_fighters[slot] = choices[slot].get_selected_metadata()
	var error = preload("res://scripts/experimental/full_game_config.gd").new().validate(selected_fighters,"toy_room",input_owner)
	if not error.is_empty(): label(error); return
	for slot in 2:
		if slot == 1 and input_owner != "human": continue
		if selected_devices[slot] >= 0 and not Input.get_connected_joypads().has(selected_devices[slot]):
			label("P%d controller disconnected. Reconnect or select Keyboard." % (slot+1),16)
			return
	session = preload("res://scripts/experimental/full_game_session.gd").new()
	session.selected_fighters = selected_fighters.duplicate()
	session.input_owner = input_owner
	session.selected_devices = selected_devices.duplicate()
	session.finished.connect(show_results)
	add_child(session)
	if not session.error.is_empty():
		label("Unable to start: " + session.error)
		dispose_session()
		return
	begin_ready()
func begin_ready(reset_clock: bool = true):
	# Reuse the original game's 1.35s gate at the core's required 60Hz.
	if reset_clock: ready_ticks = 81
	session.set_paused(true)
	show_match()
	state = "ready"
	var ready := Label.new()
	ready.name = "Ready"
	ready.text = "READY"
	ready.add_theme_font_size_override("font_size",44)
	page.add_child(ready)
	ready.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
func _physics_process(_delta):
	if state != "ready": return
	ready_ticks -= 1
	if ready_ticks <= 0:
		session.set_paused(false)
		show_match()
func show_match():
	state = "match"
	if is_instance_valid(page):
		ui.remove_child(page)
		page.queue_free()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page)
	hud = Label.new()
	hud.position = Vector2(32,18)
	hud.add_theme_font_size_override("font_size",23)
	page.add_child(hud)
	var hint := Label.new()
	hint.text = "EXPERIMENTAL FREEPLAY  /  Toy Shelf  /  %s  /  Esc: pause" % input_owner.replace("_"," ")
	page.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20,page.size.y - 32)
	get_viewport().gui_release_focus()
func _process(_delta):
	if state in ["match","ready"] and is_instance_valid(session):
		var a: Dictionary = session.simulation.fighters[1]
		var b: Dictionary = session.simulation.fighters[2]
		hud.text = "P1 %s  %.0f%%  /  %d stocks      P2 %s  %.0f%%  /  %d stocks" % [Roster.display_name(a.kit_id),a.percent,a.stocks,Roster.display_name(b.kit_id),b.percent,b.stocks]
func show_results(result: Dictionary):
	state = "results"
	clear_page("DRAW" if result.kind == "DRAW" else "P%d WINS" % result.winner_id)
	label("%s vs %s · Toy Shelf · 3 stocks" % [Roster.display_name(selected_fighters[0]),Roster.display_name(selected_fighters[1])])
	button("Rematch","Rematch",rematch).grab_focus()
	button("ChangeFighters","Change fighters",show_select)
	button("BackMenu","Back to menu",show_menu)
func rematch():
	var error: String = session.device_error()
	if not error.is_empty(): label(error); return
	session.rematch()
	begin_ready()
func pause_match():
	if state not in ["match","ready"]: return
	paused_from = state
	state = "paused"
	session.set_paused(true)
	clear_page("PAUSED")
	button("Resume","Resume",resume_match).grab_focus()
	button("ChangeFighters","Change fighters / input devices",show_select)
	button("BackMenu","Back to menu",show_menu)
func resume_match():
	var error: String = session.device_error()
	if not error.is_empty(): label(error); return
	if paused_from == "ready":
		begin_ready(false)
	else:
		session.set_paused(false)
		show_match()
func _on_device_connection(device: int, connected: bool):
	if state == "select":
		show_select()
	elif state in ["match","ready"] and not connected:
		for slot in session.sources.size():
			if slot == 1 and session.input_owner != "human": continue
			if session.sources[slot].device == device: pause_match()
func _unhandled_input(event):
	var back: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_B and state == "select": back = true
		if event.button_index == JOY_BUTTON_START and is_instance_valid(session):
			for slot in session.sources.size():
				if slot == 1 and session.input_owner != "human": continue
				if session.sources[slot].device == event.device: back = true
	if back:
		if state in ["match","ready"]: pause_match()
		elif state == "paused": resume_match()
		elif state == "select": show_menu()
		get_viewport().set_input_as_handled()
func _notification(what):
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT and state in ["match","ready"]: pause_match()
func dispose_session():
	if is_instance_valid(session):
		remove_child(session)
		session.queue_free()
	session = null

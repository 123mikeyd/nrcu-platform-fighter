extends Control
## Mid-match pause menu: Resume / Options / Match Setup / Quit to Home.
## Options holds the saved Dev Mode switch and its individual overlay layers.

signal resume_requested
signal setup_requested
signal home_requested

const DemoStyle = preload("res://scripts/demo_style.gd")

var main_box: VBoxContainer
var options_box: VBoxContainer
var dev_toggle: CheckButton
var layer_checks := {}
var layer_box: VBoxContainer

func _ready() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = DemoStyle.make()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := Panel.new()
	panel.name = "PausePanel"
	panel.position = Vector2(420, 110)
	panel.size = Vector2(440, 500)
	panel.add_theme_stylebox_override("panel", DemoStyle.box(Color("273a37"), Color("aa784c"), 2))
	add_child(panel)
	main_box = _column(panel, "PAUSED")
	for entry in [["Resume", "ResumeButton", func(): resume_requested.emit()],
			["Options", "OptionsButton", open_options],
			["Match Setup", "SetupButton", func(): setup_requested.emit()],
			["Quit to Home", "HomeButton", func(): home_requested.emit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.name = entry[1]
		b.custom_minimum_size = Vector2(360, 54)
		b.pressed.connect(entry[2])
		main_box.add_child(b)
	options_box = _column(panel, "OPTIONS")
	dev_toggle = CheckButton.new()
	dev_toggle.name = "DevModeToggle"
	dev_toggle.text = "Dev Mode"
	dev_toggle.toggled.connect(func(on): DevMode.set_enabled(on); _sync())
	options_box.add_child(dev_toggle)
	layer_box = VBoxContainer.new()
	layer_box.add_theme_constant_override("separation", 0)
	options_box.add_child(layer_box)
	for key in DevMode.LAYERS:
		var c := CheckBox.new()
		c.name = "Layer_" + key
		c.text = DevMode.LAYERS[key]
		c.add_theme_font_size_override("font_size", 15)
		c.toggled.connect(func(on): DevMode.set_layer(key, on))
		layer_box.add_child(c)
		layer_checks[key] = c
	var back := Button.new()
	back.name = "OptionsBack"
	back.text = "Back"
	back.custom_minimum_size = Vector2(360, 46)
	back.pressed.connect(close_options)
	options_box.add_child(back)
	hide()

func _column(panel: Panel, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = Vector2(40, 24)
	box.size = Vector2(360, 452)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34)
	box.add_child(t)
	return box

func open() -> void:
	close_options()
	show()

func open_options() -> void:
	main_box.hide()
	options_box.show()
	_sync()
	dev_toggle.grab_focus()

func close_options() -> void:
	options_box.hide()
	main_box.show()
	main_box.get_node("ResumeButton").grab_focus()

func _sync() -> void:
	dev_toggle.set_pressed_no_signal(DevMode.enabled)
	dev_toggle.text = "Dev Mode:  ON" if DevMode.enabled else "Dev Mode:  OFF"
	dev_toggle.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65) if DevMode.enabled else Color(0.9, 0.85, 0.78))
	layer_box.visible = DevMode.enabled
	for key in layer_checks: layer_checks[key].set_pressed_no_signal(DevMode.layers[key])

## Esc inside the menu: leave Options first, otherwise resume.
func back() -> void:
	if options_box.visible: close_options()
	else: resume_requested.emit()

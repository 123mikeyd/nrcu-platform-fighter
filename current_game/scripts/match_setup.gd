extends Control

const Config = preload("res://scripts/match_config.gd")
signal start_requested(slots: Array, teams: bool)
signal story_requested
signal back_requested
const Style = preload("res://scripts/demo_style.gd")
var help_page: Control
var rows: Array = []
var mode: OptionButton
var level: OptionButton
const LEVEL_IDS = ["debug", "toy_room", "sky", "hall", "meadow"]
var error_label: Label

func _ready() -> void:
    theme = Style.make()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var room := TextureRect.new()
    room.texture = load("res://assets/menu/shelf_background.png")
    room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    room.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(room)
    var shade := ColorRect.new()
    shade.color = Color("273a37")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.offset_left = 30
    shade.offset_right = -30
    shade.offset_top = 18
    shade.offset_bottom = -18
    add_child(shade)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 60)
    for side in ["top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 40)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    margin.add_child(column)
    var title := Label.new()
    title.text = "NRCU  /  SET UP YOUR MATCH"
    title.add_theme_font_size_override("font_size", 30)
    column.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Choose your fighters. Make unused slots Empty."
    column.add_child(subtitle)
    var mode_row := HBoxContainer.new()
    column.add_child(mode_row)
    var mode_label := Label.new()
    mode_label.text = "MATCH MODE    "
    mode_row.add_child(mode_label)
    mode = _choice(mode_row, ["Free-for-all", "Teams (friendly fire off)"], 240)
    var level_label := Label.new()
    level_label.text = "    LEVEL    "
    mode_row.add_child(level_label)
    level = _choice(mode_row, ["Fortress", "Toy Shelf / Bedroom", "Sky (legacy freeplay)", "Turbo Music Hall", "GGB Flower Meadow"], 300)
    level.name = "LevelSelect"
    var stages := HBoxContainer.new()
    stages.add_theme_constant_override("separation", 18)
    column.add_child(stages)
    for i in LEVEL_IDS.size():
        var card := Button.new()
        card.name = "StageCard" + str(i)
        card.custom_minimum_size = Vector2(214,126)
        card.tooltip_text = level.get_item_text(i)
        stages.add_child(card)
        var picture := TextureRect.new()
        picture.name = "StageThumbnail" + str(i)
        picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        picture.texture = load("res://assets/menu/stage_" + LEVEL_IDS[i] + ".png")
        picture.position = Vector2(5,5)
        picture.size = Vector2(204,96)
        picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(picture)
        var caption := Label.new()
        caption.text = ["Fortress", "Toy Shelf", "Sky (legacy)", "Music Hall", "Flower Meadow"][i]
        caption.position = Vector2(5,100)
        caption.size.x = 204
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.add_theme_font_size_override("font_size",16)
        caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(caption)
        card.pressed.connect(func(): level.select(i))
    var defaults := Config.default_slots()
    for i in range(4):
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        column.add_child(row)
        var label := Label.new()
        label.text = "P%d" % (i + 1)
        label.custom_minimum_size.x = 35
        row.add_child(label)
        var kind := _choice(row, ["Human", "Bot", "Empty"], 110)
        kind.select(0 if i == 0 else 1)
        var character := _choice(row, Config.NAMES, 160)
        character.select(i)
        var difficulty := _choice(row, ["Easy", "Normal", "Hard"], 110)
        difficulty.select(1)
        var team := _choice(row, ["Team A", "Team B"], 120)
        team.select(defaults[i].team)
        var device := _choice(row, ["Keyboard %d" % (i + 1) if i < 2 else "Gamepad required"], 240)
        device.set_item_metadata(0, -1)
        for id in Input.get_connected_joypads():
            device.add_item("Pad %d: %s" % [id + 1, Input.get_joy_name(id)])
            device.set_item_metadata(device.item_count - 1, id)
        if i >= 2 and device.item_count > 1:
            device.select(mini(i - 1, device.item_count - 1))
        rows.append({"kind": kind, "character": character, "difficulty": difficulty, "team": team, "device": device})
        kind.item_selected.connect(func(_index): _refresh())
    mode.item_selected.connect(func(_index): _refresh())
    var controls := Label.new()
    controls.text = "P1: WASD · Space jump · F basic · G special    |    How to Play: both players & moves"
    controls.add_theme_font_size_override("font_size", 16)
    column.add_child(controls)
    error_label = Label.new()
    error_label.modulate = Color(1, 0.65, 0.35)
    error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    error_label.custom_minimum_size.y = 28
    column.add_child(error_label)
    var start := Button.new()
    start.text = "START MATCH"
    start.name = "StartMatchButton"
    start.custom_minimum_size.y = 48
    start.pressed.connect(_start)
    var actions := HBoxContainer.new()
    column.add_child(actions)
    start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    actions.add_child(start)
    var story := Button.new()
    story.name = "StoryModeButton"
    story.text = "Story Mode"
    story.custom_minimum_size = Vector2(400, 48)
    story.pressed.connect(func(): story_requested.emit())
    actions.add_child(story)
    var navigation := HBoxContainer.new()
    column.add_child(navigation)
    var back := Button.new()
    back.name = "BackToMenu"
    back.text = "Back to Menu"
    back.custom_minimum_size = Vector2(240,44)
    back.pressed.connect(func(): back_requested.emit())
    navigation.add_child(back)
    var help_button := Button.new()
    help_button.name = "SetupHelp"
    help_button.text = "How to Play / Moves"
    help_button.custom_minimum_size = Vector2(310,44)
    help_button.pressed.connect(func(): help_page = Style.help(self, func(): help_button.grab_focus()))
    navigation.add_child(help_button)
    _refresh()
    start.grab_focus()

func close_help() -> bool:
    if is_instance_valid(help_page) and not help_page.is_queued_for_deletion():
        help_page.queue_free()
        find_child("SetupHelp",true,false).grab_focus()
        return true
    return false

func _choice(parent: Node, values: Array, width: float) -> OptionButton:
    var choice := OptionButton.new()
    choice.custom_minimum_size = Vector2(width, 44)
    for value in values:
        choice.add_item(value)
    parent.add_child(choice)
    return choice

func _refresh() -> void:
    for row in rows:
        row.difficulty.disabled = row.kind.selected != 1
        row.device.disabled = row.kind.selected != 0
        row.character.disabled = row.kind.selected == 2
        row.team.disabled = mode.selected == 0 or row.kind.selected == 2

func _start() -> void:
    var slots: Array = []
    for row in rows:
        slots.append({"kind": ["human", "bot", "empty"][row.kind.selected], "character": Config.CHARACTERS[row.character.selected], "difficulty": Config.DIFFICULTIES[row.difficulty.selected], "team": row.team.selected, "device": row.device.get_item_metadata(row.device.selected)})
    var error := Config.validate(slots, mode.selected == 1)
    error_label.text = error
    if error.is_empty():
        start_requested.emit(slots, mode.selected == 1)

func selected_level() -> String:
    return LEVEL_IDS[level.selected]

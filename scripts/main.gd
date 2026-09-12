extends Node3D

const FighterScript = preload("res://scripts/fighter.gd")
const Config = preload("res://scripts/match_config.gd")
const SetupScript = preload("res://scripts/match_setup.gd")
const DemoStyle = preload("res://scripts/demo_style.gd")
const StoryStageScript = preload("res://scripts/story_stage.gd")
var ready_remaining := 0.0
var go_remaining := 0.0
var ready_label: Label
var result_panel: Panel

var fighters: Array = []
var active_level := "debug"
var stage_theme: Node3D
var debug_visuals: Array[Node3D] = []
var hud_labels: Array[Label] = []
var setup: Control
var teams_enabled := false
var active_slots: Array = []
# One encounter only. Empty state means ordinary freeplay.
var story_state := ""
var story_panel: Control
var story_title: Label
var story_detail: Label
var story_action: Button
var story_back: Button
var story_character: OptionButton
var story_choice_row: HBoxContainer
var story_stage: Control
var hud_title: Label
var hud_controls: Label
var freeplay_controls: String
var bobo_health_bar: ProgressBar

var player_one: CharacterBody3D
var player_two: CharacterBody3D
var p1_label: Label
var p2_label: Label
var winner_label: Label
var match_over := false
var p1_spawn := Vector3(-4.0, 1.0, 0.0)
var p2_spawn := Vector3(4.0, 1.0, 0.0)

func _ready() -> void:
    DisplayServer.window_set_title("NRCU — Friend Demo")
    get_window().min_size = Vector2i(800,450)
    _build_environment()
    _build_stage()
    var backdrop_start := get_child_count()
    _build_hangar_backdrop()
    var terminal := preload("res://scripts/kainan_terminal.gd").new()
    terminal.position = Vector3(0.0, 3.1, -4.90)
    add_child(terminal)
    for i in range(backdrop_start, get_child_count()):
        debug_visuals.append(get_child(i))
    for child in get_children():
        if child is StaticBody3D:
            debug_visuals.append(child.get_child(0))
    _build_hud()
    var menu_layer := CanvasLayer.new()
    menu_layer.layer = 10
    add_child(menu_layer)
    setup = SetupScript.new()
    menu_layer.add_child(setup)
    setup.start_requested.connect(start_match)
    setup.story_requested.connect(open_story)
    setup.back_requested.connect(back_to_menu)
    _build_story_panel(menu_layer)

func _process(_delta: float) -> void:
    for i in range(fighters.size()):
        var fighter = fighters[i]
        var side: String = "  TEAM %s" % ("A" if fighter.team_id == 0 else "B") if teams_enabled else ""
        hud_labels[i].text = "P%d  %s%s\n%d%%   STOCKS %d" % [fighter.player_index, fighter.fighter_name, side, roundi(fighter.damage_percent), fighter.stocks]
        if fighter.character_id == "bobo":
            hud_labels[i].text = "BOBO\n%d / 400 HP" % ceili(fighter.health)
            bobo_health_bar.value = fighter.health


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        if setup.visible and setup.close_help(): return
        if setup.visible: back_to_menu()
        else: show_setup()
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and match_over:
        _reset_match()

func back_to_menu() -> void:
    show_setup()
    get_tree().change_scene_to_file("res://scenes/home.tscn")

func show_setup() -> void:
    _cancel_ready()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    result_panel.hide()
    story_state = ""
    story_panel.hide()
    bobo_health_bar.hide()
    for fighter in fighters:
        fighter.controls_enabled = false
        fighter._clear_move_state()
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    match_over = false
    winner_label.visible = false
    setup.show()
    setup.find_child("StartMatchButton",true,false).grab_focus()

func start_match(slots: Array, teams: bool, bobo_encounter := false) -> bool:
    var validation_slots := slots.duplicate(true)
    if bobo_encounter and validation_slots[1].character == "bobo":
        validation_slots[1].character = "ice_mage"
    var error := Config.validate(validation_slots, teams)
    if not error.is_empty():
        setup.error_label.text = error
        return false
    apply_level(setup.selected_level())
    for fighter in fighters:
        remove_child(fighter)
        fighter.queue_free()
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    fighters.clear()
    for label in hud_labels:
        label.text = ""
    story_state = ""
    story_panel.hide()
    hud_title.text = "NRCU"
    hud_controls.text = freeplay_controls
    active_slots = slots.duplicate(true)
    teams_enabled = teams
    match_over = false
    winner_label.visible = false
    var roster = load("res://scripts/roster.gd")
    var palette_counts: Dictionary = {}
    for i in range(slots.size()):
        var slot: Dictionary = slots[i]
        if slot.kind == "empty":
            continue
        var fighter = load("res://scripts/bobo_fighter.gd").new() if bobo_encounter and i == 1 else FighterScript.new()
        fighter.character_id = slot.character
        fighter.fighter_name = roster.display_name(slot.character).to_upper()
        fighter.player_index = i + 1
        var palette_index: int = palette_counts.get(slot.character, 0)
        fighter.body_color = roster.palette(slot.character, palette_index)
        palette_counts[slot.character] = palette_index + 1
        fighter.team_id = slot.team if teams else -1
        fighter.control_type = slot.kind
        fighter.bot_difficulty = slot.difficulty
        fighter.input_device = slot.device
        fighter.position = Vector3([-6.5, -2.2, 2.2, 6.5][i], 0.2, 0)
        add_child(fighter)
        fighter.eliminated.connect(_on_fighter_eliminated)
        hud_labels[fighters.size()].modulate = fighter.body_color
        fighters.append(fighter)
    player_one = fighters[0]
    player_two = fighters[1]
    setup.hide()
    result_panel.hide()
    bobo_health_bar.visible = bobo_encounter
    _begin_ready()
    return true

func _build_story_panel(layer: CanvasLayer) -> void:
    story_panel = Control.new()
    story_panel.theme = DemoStyle.make()
    story_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(story_panel)
    var shade := ColorRect.new()
    shade.color = Color("273a37")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    story_panel.add_child(shade)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    story_panel.add_child(center)
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = 700
    column.add_theme_constant_override("separation", 24)
    center.add_child(column)
    story_title = Label.new()
    story_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    story_title.add_theme_font_size_override("font_size", 42)
    column.add_child(story_title)
    story_detail = Label.new()
    story_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    story_detail.add_theme_font_size_override("font_size", 20)
    column.add_child(story_detail)
    story_choice_row = HBoxContainer.new()
    story_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
    story_choice_row.add_theme_constant_override("separation", 20)
    column.add_child(story_choice_row)
    var choice_stack := VBoxContainer.new()
    choice_stack.add_theme_constant_override("separation", 14)
    story_choice_row.add_child(choice_stack)
    var choice_label := Label.new()
    choice_label.text = "PICK YOUR FIGHTER / P1"
    choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    choice_stack.add_child(choice_label)
    var cards_row := HBoxContainer.new()
    cards_row.name = "FighterCardRow"
    cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
    cards_row.add_theme_constant_override("separation", 18)
    choice_stack.add_child(cards_row)
    # Hidden selection model: the card stage drives it; kept for state + tests.
    var roster = load("res://scripts/roster.gd")
    var playable_ids := _story_playable_ids()
    story_character = OptionButton.new()
    story_character.name = "StoryCharacterSelect"
    story_character.custom_minimum_size = Vector2(300, 48)
    for id in playable_ids:
        story_character.add_item(roster.display_name(id))
        story_character.set_item_metadata(story_character.item_count - 1, id)
    story_character.select(playable_ids.find("turbofit"))
    story_character.hide()
    story_panel.add_child(story_character)
    story_action = Button.new()
    story_action.custom_minimum_size.y = 54
    story_action.pressed.connect(start_story)
    column.add_child(story_action)
    story_back = Button.new()
    story_back.text = "BACK TO MATCH SETUP"
    story_back.custom_minimum_size.y = 48
    story_back.pressed.connect(show_setup)
    column.add_child(story_back)
    story_stage = StoryStageScript.new()
    story_stage.name = "StoryStage"
    story_panel.add_child(story_stage)
    story_stage.build(playable_ids, cards_row)
    story_stage.chosen.connect(_on_story_card_chosen)
    story_stage.cursor.add_target(story_action)
    story_stage.cursor.add_target(story_back)
    story_stage.set_selected_id("turbofit")
    story_panel.hide()

func apply_level(id: String) -> void:
    if id not in SetupScript.LEVEL_IDS: id = "debug"
    if id == active_level: return
    if is_instance_valid(stage_theme):
        remove_child(stage_theme)
        stage_theme.queue_free()
    stage_theme = null
    active_level = id
    var layout = preload("res://scripts/stage_layouts.gd")
    var surfaces: Array = layout.surfaces(id)
    for i in layout.NAMES.size():
        var body: StaticBody3D = get_node(layout.NAMES[i])
        # Keep RIDs alive for existing fighter one-way exceptions, but absent
        # surfaces must have neither collision nor presentation.
        body.collision_layer = (1 if i == 0 else 2) if i < surfaces.size() else 0
        if i >= surfaces.size():
            body.get_child(0).hide()
            continue
        body.position = surfaces[i][0]
        body.get_child(0).mesh.size = surfaces[i][1]
        body.get_child(1).shape.size = surfaces[i][1]
        if i > 0:
            body.set_meta("top_y", surfaces[i][0].y + surfaces[i][1].y * 0.5)
            body.set_meta("half_width", surfaces[i][1].x * 0.5)
    for visual in debug_visuals: visual.visible = id == "debug"
    if id != "debug":
        stage_theme = preload("res://scripts/stage_theme.gd").new()
        stage_theme.level_id = id
        add_child(stage_theme)

func open_story() -> void:
    show_setup()
    setup.hide()
    story_state = "ready"
    story_title.text = "STORY 01 / BOBO"
    story_detail.text = "A big goofball with a slow two-hit claw attack.\nDeplete Bobo's 400 HP. Dodge his claws, then punish the recovery!\nHe stays put. You have three stocks — watch the edges!\n\nA / D move · Space jump · F basic · G special\nAim with WASD · E shield · Esc back to setup"
    story_choice_row.show()
    story_action.text = "START ENCOUNTER"
    story_panel.show()
    story_stage.begin_pick()
    var current_meta = story_character.get_selected_metadata()
    var current: String = current_meta if current_meta is String and current_meta != "" else "turbofit"
    story_stage.set_selected_id(current)
    story_stage.cursor.reset()
    story_stage.focus_selected()
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _story_playable_ids() -> Array[String]:
    # The prototype remains available to encounters and freeplay, not Story P1.
    var ids: Array[String] = load("res://scripts/roster.gd").ids()
    ids.erase("ice_mage")
    return ids

func start_story() -> void:
    var slots := Config.default_slots()
    var selected = story_character.get_selected_metadata()
    if not selected is String or selected not in _story_playable_ids():
        selected = "turbofit"
        for index in story_character.item_count:
            if story_character.get_item_metadata(index) == selected:
                story_character.select(index)
                break
    story_stage.set_selected_id(selected)
    slots[0].character = selected
    slots[0].kind = "human"
    slots[0].device = -1
    slots[1].character = "bobo"
    slots[1].kind = "bot"
    slots[1].difficulty = "normal"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    if start_match(slots, false, true):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        story_state = "playing"
        hud_title.text = "STORY 01 — %s VS BOBO" % player_one.fighter_name
        hud_controls.text = "YOU / P1: WASD move & aim · Space jump · F basic · G special · E shield\nBobo: 400 HP · slow two-hit claws · punish his recovery! · Esc: match setup"
        player_one.reset_fighter(p1_spawn, true)
        # Central floor lane keeps this large opponent clear of side platforms.
        player_two.reset_fighter(Vector3(0.6, 1.0, 0.0), true)
        player_one.facing = 1.0
        player_two.facing = -1.0
        _begin_ready()

func _build_environment() -> void:
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.012, 0.018, 0.035)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.25, 0.35, 0.55)
    env.ambient_light_energy = 0.72
    env.tonemap_mode = Environment.TONE_MAPPER_AGX
    environment.environment = env
    add_child(environment)

    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
    key.light_color = Color(0.72, 0.82, 1.0)
    key.light_energy = 1.5
    key.shadow_enabled = true
    add_child(key)

    # Keep fighters readable under the upper platforms without flattening the set.
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
    fill.light_color = Color(0.7, 0.8, 1.0)
    fill.light_energy = 0.65
    fill.shadow_enabled = false
    add_child(fill)

    var camera := Camera3D.new()
    camera.position = Vector3(0.0, 5.8, 19.5)
    camera.fov = 48.0
    camera.look_at_from_position(camera.position, Vector3(0.0, 2.0, 0.0))
    add_child(camera)

func _build_stage() -> void:
    _platform("MainPlatform", Vector3(0.0, -0.55, 0.0), Vector3(18.0, 1.0, 5.0), Color(0.12, 0.16, 0.23))
    _platform("LeftPlatform", Vector3(-5.2, 3.0, 0.0), Vector3(5.0, 0.45, 3.8), Color(0.16, 0.22, 0.32))
    _platform("RightPlatform", Vector3(5.2, 3.0, 0.0), Vector3(5.0, 0.45, 3.8), Color(0.16, 0.22, 0.32))
    _platform("TopPlatform", Vector3(0.0, 6.0, 0.0), Vector3(4.5, 0.4, 3.4), Color(0.18, 0.25, 0.36))

func _platform(node_name: String, location: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = location
    if node_name != "MainPlatform":
        body.add_to_group("pass_through_platforms")
        body.set_meta("top_y", location.y + size.y * 0.5)
        body.set_meta("half_width", size.x * 0.5)
        body.collision_layer = 2
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = 0.72
    material.roughness = 0.25
    mesh_instance.material_override = material
    body.add_child(mesh_instance)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _build_hangar_backdrop() -> void:
    var dark := Color(0.035, 0.05, 0.075)
    var steel := Color(0.12, 0.17, 0.24)
    for x in [-11.0, 11.0]:
        _visual_box(Vector3(x, 5.5, -4.2), Vector3(1.0, 13.0, 1.0), steel)
        _visual_box(Vector3(x * 0.78, 11.2, -4.2), Vector3(0.8, 7.0, 1.0), steel, deg_to_rad(-28.0 * signf(x)))
    for y in [0.0, 4.0, 8.0, 12.0]:
        _visual_box(Vector3(0.0, y, -5.0), Vector3(22.0, 0.32, 0.55), dark)
    for x in [-8.0, -4.0, 4.0, 8.0]:
        _emissive_strip(Vector3(x, 8.0, -4.35), Vector3(0.16, 9.0, 0.12), Color(0.25, 0.72, 1.0))
    _visual_box(Vector3(0.0, 2.2, -5.4), Vector3(19.0, 8.0, 0.5), Color(0.025, 0.035, 0.055))
    _emissive_strip(Vector3(0.0, 9.2, -4.7), Vector3(14.0, 0.18, 0.12), Color(0.45, 0.78, 1.0))
    _visual_box(Vector3(0.0, -1.0, -2.8), Vector3(27.0, 0.18, 7.0), Color(0.045, 0.06, 0.085))

    for x in [-9.5, 9.5]:
        for y in [0.8, 3.2, 5.6]:
            _visual_box(Vector3(x, y, -3.4), Vector3(1.3, 1.1, 1.2), dark)
    for x in [-7.5, 7.5]:
        _emissive_strip(Vector3(x, -0.82, -2.2), Vector3(0.18, 0.08, 2.0), Color(1.0, 0.12, 0.08))

func _visual_box(location: Vector3, size: Vector3, color: Color, z_rotation := 0.0) -> void:
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.position = location
    instance.rotation.z = z_rotation
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = 0.65
    material.roughness = 0.3
    instance.material_override = material
    add_child(instance)

func _emissive_strip(location: Vector3, size: Vector3, color: Color) -> void:
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.position = location
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 4.0
    instance.material_override = material
    add_child(instance)

func _build_hud() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 1
    add_child(layer)

    var title := Label.new()
    hud_title = title
    title.text = "NRCU"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.position = Vector2(200, 18)
    title.size = Vector2(880, 42)
    title.add_theme_font_size_override("font_size", 26)
    layer.add_child(title)

    for i in range(4):
        var label := Label.new()
        label.position = Vector2(20 + i * 315, 605)
        label.size = Vector2(305, 60)
        label.add_theme_font_size_override("font_size", 18)
        layer.add_child(label)
        hud_labels.append(label)
    p1_label = hud_labels[0]
    p2_label = hud_labels[1]
    bobo_health_bar = ProgressBar.new()
    bobo_health_bar.name = "BoboHealthBar"
    bobo_health_bar.position = Vector2(335, 653)
    bobo_health_bar.size = Vector2(290, 14)
    bobo_health_bar.max_value = 400
    bobo_health_bar.value = 400
    bobo_health_bar.show_percentage = false
    bobo_health_bar.hide()
    layer.add_child(bobo_health_bar)

    var controls := Label.new()
    controls.text = "P1: WASD / Space jump / F basic / G special / E shield    |    P2: Arrows / Enter jump / K basic / L special / O shield\nPad: stick aim / A jump / X basic / B special / shoulder shield    ·    Down: drop through    ·    Esc: match setup"
    controls.name = "MatchControls"
    hud_controls = controls
    freeplay_controls = controls.text
    controls.position = Vector2(20, 672)
    controls.size = Vector2(1240, 46)
    controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    controls.add_theme_font_size_override("font_size", 15)
    controls.modulate = Color(0.7, 0.78, 0.9)
    layer.add_child(controls)

    winner_label = Label.new()
    winner_label.position = Vector2(340, 270)
    winner_label.size = Vector2(600, 120)
    winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    winner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    winner_label.add_theme_font_size_override("font_size", 38)
    winner_label.visible = false
    result_panel = Panel.new()
    result_panel.name = "WinnerPanel"
    result_panel.position = Vector2(290,235)
    result_panel.size = Vector2(700,250)
    result_panel.theme = DemoStyle.make()
    result_panel.add_theme_stylebox_override("panel",DemoStyle.box(Color("273a37"),Color("aa784c"),2))
    layer.add_child(result_panel)
    winner_label.position = Vector2(20,15)
    winner_label.size = Vector2(660,110)
    winner_label.add_theme_font_size_override("font_size",30)
    result_panel.add_child(winner_label)
    for i in 2:
        var action := Button.new()
        action.name = "Rematch" if i == 0 else "ChangeFighters"
        action.text = "Rematch" if i == 0 else "Change Fighters"
        action.position = Vector2(30+i*335,160)
        action.size = Vector2(305,55)
        result_panel.add_child(action)
        action.pressed.connect(_reset_match if i == 0 else show_setup)
    result_panel.hide()
    ready_label = Label.new()
    ready_label.name = "ReadyGo"
    ready_label.position = Vector2(340,270)
    ready_label.size = Vector2(600,120)
    ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ready_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ready_label.theme = DemoStyle.make()
    ready_label.add_theme_font_size_override("font_size",72)
    ready_label.add_theme_color_override("font_shadow_color",Color("152b2b"))
    ready_label.add_theme_constant_override("shadow_offset_x",4)
    ready_label.add_theme_constant_override("shadow_offset_y",4)
    ready_label.hide()
    layer.add_child(ready_label)

func _on_fighter_eliminated(_loser: CharacterBody3D) -> void:
    if match_over:
        return
    var survivors: Array = fighters.filter(func(f): return f.stocks > 0)
    var sides: Array = []
    for fighter in survivors:
        if fighter.team_id not in sides:
            sides.append(fighter.team_id)
    if (teams_enabled and sides.size() > 1) or (not teams_enabled and survivors.size() > 1):
        return
    match_over = true
    _cancel_ready()
    for fighter in fighters:
        fighter.controls_enabled = false
        fighter._clear_move_state()
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    if story_state == "playing":
        Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
        var won: bool = player_one.stocks > 0 and player_two.stocks <= 0
        story_state = "complete" if won else "lost"
        story_title.text = "your pretty cool" if won else "TRY AGAIN"
        story_detail.text = "STAGE COMPLETE\nBobo is all tuckered out. You win this first encounter!" if won else "Out of stocks! Bobo is still standing.\nRetry with three fresh stocks and Bobo at 400 HP."
        story_action.text = "REPLAY" if won else "RETRY"
        story_choice_row.hide()
        winner_label.visible = false
        story_panel.show()
        story_action.grab_focus()
        return
    if survivors.is_empty():
        winner_label.text = "DRAW"
    elif teams_enabled:
        winner_label.text = "TEAM %s WINS!" % ("A" if sides[0] == 0 else "B")
    else:
        winner_label.text = "P%d %s WINS!" % [survivors[0].player_index, survivors[0].fighter_name]
    winner_label.visible = true
    result_panel.show()
    result_panel.get_node("Rematch").grab_focus()

func _reset_match() -> void:
    if story_state in ["complete", "lost"]:
        start_story()
        return
    match_over = false
    winner_label.visible = false
    for fighter in fighters:
        fighter.reset_fighter(fighter.spawn_position, true)
    result_panel.hide()
    _begin_ready()

func _cancel_ready() -> void:
    ready_remaining = 0
    go_remaining = 0
    ready_label.hide()
    for fighter in fighters: fighter.ready_settling = false

func _begin_ready() -> void:
    ready_remaining = 1.35
    go_remaining = 0
    ready_label.text = "READY"
    ready_label.show()
    for fighter in fighters:
        fighter._clear_move_state()
        fighter.controls_enabled = false
        fighter.ready_settling = true

func _physics_process(delta: float) -> void:
    if ready_remaining > 0:
        ready_remaining = maxf(0,ready_remaining-delta)
        if ready_remaining == 0:
            ready_label.text = "GO!"
            go_remaining = 0.45
            for fighter in fighters:
                fighter.ready_settling = false
                fighter.controls_enabled = true
                if fighter.control_type == "human":
                    var held: Dictionary = fighter.read_controls(0)
                    fighter._attack_was_down = held.attack
                    fighter._special_was_down = held.special
                    fighter._jump_was_down = held.jump or held.up
                    fighter._down_was_down = held.down
    elif go_remaining > 0:
        go_remaining = maxf(0,go_remaining-delta)
        if go_remaining == 0: ready_label.hide()

func _on_story_card_chosen(id: String) -> void:
    var index := _story_playable_ids().find(id)
    if index >= 0:
        story_character.select(index)

func _exit_tree() -> void:
    if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

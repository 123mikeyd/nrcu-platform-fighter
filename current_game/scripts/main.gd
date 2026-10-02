extends Node3D

const FighterScript = preload("res://scripts/fighter.gd")
const Config = preload("res://scripts/match_config.gd")
const SetupScript = preload("res://scripts/match_setup.gd")
const DemoStyle = preload("res://scripts/demo_style.gd")
var ready_remaining := 0.0
var go_remaining := 0.0
var ready_label: Label
var result_panel: Panel
var victory_screen: Control

var fighters: Array = []
var active_level := "debug"
var stage_theme: Node3D
var debug_visuals: Array[Node3D] = []
var hud_labels: Array[Label] = []
var setup: Control
var teams_enabled := false
var active_slots: Array = []
# Local two-encounter run. Empty state means ordinary freeplay.
var story_state := ""
var story_encounter := 0
var story_hero := "turbofit"
var story_panel: Control
var story_title: Label
var story_detail: Label
var story_action: Button
var story_back: Button
var story_character: OptionButton
var story_choice_row: HBoxContainer
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
var pause_menu: Control
var dev_overlay: Node3D
var heavy_bag_mode: Node   # Heavy Bag mini-game round (null outside the mini-game)

# Fighter unlocks + Story gauntlet (Mike 2026-09-30). See scripts/unlocks.gd.
const Unlocks = preload("res://scripts/unlocks.gd")
# Provisional order, not a difficulty ranking. The chosen hero is skipped.
# Mephisto (preserved form-switching Story version) is the placeholder last slot.
const STORY_ORDER := ["bobo", "ice_mage", "witcheer", "ggb", "turbofit", "doge_man", "teknium", "mephisto"]
const StoryCredits = preload("res://scripts/story_credits.gd")
var story_route: Array = []
# Story glow-up (Mike 2026-09-30): VS splash before each fresh encounter, the
# victory screen after Story wins, and the STORY COMPLETE? ending + credits roll.
var story_vs: Control
var story_ending: Control
var story_shade: ColorRect
var story_center: CenterContainer
var story_column: VBoxContainer
var story_result_bar: ColorRect
var challenger_screen: Control
var challenger_id := ""
var challenger_hero := "teknium"
var _challenger_serial := 0
var _story_boss_next := false
# Public v0.5 freeplay worlds (character_world.gd); Story/Challenger/Heavy Bag use Fortress there.
const FREEPLAY_WORLDS := ["hall", "meadow"]
var _special_mode_start := false
var world: Node3D
var world_environment: Dictionary = {}

func _ready() -> void:
    DisplayServer.window_set_title("NRCU — v0.6")
    if not OS.has_feature("web"): get_window().min_size = Vector2i(800,450)
    _build_environment()
    _build_stage()
    var backdrop_start := get_child_count()
    _build_hangar_backdrop()
    var terminal := preload("res://scripts/kainan_terminal.gd").new()
    # Fortress: keep the Kainan cameo clear of the shaft/bed silhouette (from the v9 candidate).
    terminal.position = Vector3(-13.0, 1.0, -6.5)
    terminal.scale = Vector3.ONE * 1.25
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
    setup.heavy_bag_requested.connect(open_heavy_bag)
    setup.back_requested.connect(back_to_menu)
    _build_story_panel(menu_layer)
    story_vs = preload("res://scripts/story_vs_splash.gd").new()
    menu_layer.add_child(story_vs)
    story_vs.finished.connect(_on_story_vs_finished)
    story_ending = preload("res://scripts/story_ending.gd").new()
    menu_layer.add_child(story_ending)
    story_ending.finished.connect(_on_story_ending_finished)
    pause_menu = preload("res://scripts/pause_menu.gd").new()
    menu_layer.add_child(pause_menu)
    pause_menu.resume_requested.connect(resume_match)
    pause_menu.setup_requested.connect(func(): _close_pause(); show_setup())
    pause_menu.home_requested.connect(func(): _close_pause(); back_to_menu())
    dev_overlay = preload("res://scripts/dev_overlay.gd").new()
    var challenger_layer := CanvasLayer.new()
    challenger_layer.layer = 20
    add_child(challenger_layer)
    challenger_screen = preload("res://scripts/challenger_screen.gd").new()
    challenger_layer.add_child(challenger_screen)
    challenger_screen.fight_requested.connect(start_challenger)
    challenger_screen.later_requested.connect(show_setup)
    challenger_screen.continue_requested.connect(show_setup)
    dev_overlay.name = "DevOverlay"
    dev_overlay.main = self
    add_child(dev_overlay)
    # Public home routes straight into Story / Heavy Bag; otherwise match setup.
    if get_tree().has_meta("nrcu_entry"):
        var entry = get_tree().get_meta("nrcu_entry")
        get_tree().remove_meta("nrcu_entry")
        if entry == "story": open_story()
        elif entry == "heavy_bag": open_heavy_bag()

func _process(_delta: float) -> void:
    var mobile = get_node_or_null("/root/MobileTouch")
    var touch_hud: bool = mobile != null and mobile.touch_mode
    # Mike's rule: no text on screen during gameplay unless Dev Mode is on.
    # Damage/stocks, P1 markers, READY/GO and results stay.
    var dev = get_node_or_null("/root/DevMode")
    var dev_on: bool = dev != null and dev.enabled
    hud_title.visible = dev_on
    hud_controls.visible = not touch_hud and dev_on
    for i in hud_labels.size():
        hud_labels[i].position.y = 80 if touch_hud else 605
        hud_labels[i].add_theme_font_size_override("font_size", 22 if touch_hud else 18)
    bobo_health_bar.position.y = 140 if touch_hud else 653
    for i in range(fighters.size()):
        var fighter = fighters[i]
        var side: String = "  TEAM %s" % ("A" if fighter.team_id == 0 else "B") if teams_enabled else ""
        hud_labels[i].text = "P%d  %s%s\n%d%%   STOCKS %d" % [fighter.player_index, fighter.fighter_name, side, roundi(fighter.damage_percent), fighter.stocks]
        if heavy_bag_mode:   # mini-game: no damage %, and no label for the bag
            hud_labels[i].text = "" if fighter.has_method("is_heavy_bag") else "P%d  %s\nSTOCKS %d" % [fighter.player_index, fighter.fighter_name, fighter.stocks]
        if fighter.get_script() == preload("res://scripts/bobo_fighter.gd"):
            hud_labels[i].text = "BOBO\n%d / 400 HP" % ceili(fighter.health)
            bobo_health_bar.value = fighter.health


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        if pause_menu.visible:
            pause_menu.back()
            get_viewport().set_input_as_handled()
            return
        if match_active():
            pause_match()
            get_viewport().set_input_as_handled()
            return
        if setup.visible and setup.close_help(): return
        if setup.visible: back_to_menu()
        else: show_setup()
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and match_over:
        _reset_match()

## A live fight (freeplay or Story) with no menu or result screen on top.
func match_active() -> bool:
    return not fighters.is_empty() and not setup.visible and not story_panel.visible and not result_panel.visible and not match_over

func pause_match() -> void:
    DevMode.set_menu_paused(true)
    pause_menu.open()

func resume_match() -> void:
    _close_pause()
    # Keys used to click menu buttons (Space/Enter) must not fire moves on resume.
    for fighter in fighters:
        if fighter.controls_enabled and fighter.control_type == "human":
            var held: Dictionary = fighter.read_controls(0)
            fighter._attack_was_down = held.attack
            fighter._special_was_down = held.special
            fighter._jump_was_down = held.jump or held.up
            fighter._down_was_down = held.down

func _close_pause() -> void:
    pause_menu.hide()
    DevMode.set_menu_paused(false)

func back_to_menu() -> void:
    show_setup()
    DevMode.reset_match_state()
    get_tree().change_scene_to_file("res://scenes/home.tscn")

func show_setup() -> void:
    if pause_menu: pause_menu.hide()
    _challenger_serial += 1
    if challenger_screen: challenger_screen.hide()
    DevMode.reset_match_state()
    _cancel_ready()
    result_panel.hide()
    if victory_screen: victory_screen.clear()
    story_state = ""
    if story_vs: story_vs.skip()
    if story_ending: story_ending.skip()   # state is already cleared: no result panel
    story_panel.hide()
    _layout_story_panel(false)
    bobo_health_bar.hide()
    _end_heavy_bag_mode()
    for fighter in fighters:
        fighter.controls_enabled = false
        fighter._clear_move_state()
        # Retained match actors are not previews: stop rendering/ticking in menus.
        fighter.hide()
        fighter.process_mode = Node.PROCESS_MODE_DISABLED
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    match_over = false
    winner_label.visible = false
    setup.show()
    setup.find_child("StartMatchButton",true,false).grab_focus()

func start_match(slots: Array, teams: bool, bobo_encounter := false, heavy_bag := false) -> bool:
    var validation_slots := slots.duplicate(true)
    if bobo_encounter and validation_slots[1].character == "bobo":
        validation_slots[1].character = "ice_mage"
    var error := Config.validate(validation_slots, teams)
    if not error.is_empty():
        setup.error_label.text = error
        return false
    var level: String = setup.selected_level()
    if (_special_mode_start or bobo_encounter or heavy_bag) and level in FREEPLAY_WORLDS: level = "debug"
    apply_level(level)
    for fighter in fighters:
        remove_child(fighter)
        fighter.queue_free()
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    fighters.clear()
    _end_heavy_bag_mode()
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
        var fighter = _create_fighter(slot, i, bobo_encounter, heavy_bag)
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
    _story_boss_next = false
    player_one = fighters[0]
    player_two = fighters[1]
    setup.hide()
    result_panel.hide()
    if victory_screen: victory_screen.clear()
    bobo_health_bar.visible = bobo_encounter
    if active_level in FREEPLAY_WORLDS:
        # World floors differ from the base layout: drop fighters in from above.
        var spots: Array = [-4.0, 4.0] if fighters.size() == 2 else [-8.0, -4.0, 4.0, 8.0]
        for i in fighters.size():
            fighters[i].reset_fighter(Vector3(spots[min(i, spots.size() - 1)], 3, 0), true)
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
    story_shade = shade
    # Slim bottom bar used when the victory screen is showing behind the panel.
    story_result_bar = ColorRect.new()
    story_result_bar.name = "StoryResultBar"
    story_result_bar.color = Color(0.02, 0.03, 0.045, 0.86)
    story_result_bar.position = Vector2(0, 520)
    story_result_bar.size = Vector2(1280, 200)
    story_result_bar.hide()
    story_panel.add_child(story_result_bar)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    story_panel.add_child(center)
    story_center = center
    var column := VBoxContainer.new()
    story_column = column
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
    var choice_label := Label.new()
    choice_label.text = "YOUR CHARACTER / P1"
    story_choice_row.add_child(choice_label)
    story_character = OptionButton.new()
    story_character.name = "StoryCharacterSelect"
    story_character.custom_minimum_size = Vector2(300, 48)
    var roster = load("res://scripts/roster.gd")
    var playable_ids := _story_playable_ids()
    for id in playable_ids:
        story_character.add_item(roster.display_name(id))
        story_character.set_item_metadata(story_character.item_count - 1, id)
    story_character.select(playable_ids.find("turbofit"))
    story_choice_row.add_child(story_character)
    story_action = Button.new()
    story_action.custom_minimum_size.y = 54
    story_action.pressed.connect(start_story)
    column.add_child(story_action)
    story_back = Button.new()
    story_back.text = "BACK TO MATCH SETUP"
    story_back.custom_minimum_size.y = 48
    story_back.pressed.connect(show_setup)
    column.add_child(story_back)
    story_panel.hide()

## compact = victory screen visible behind a bottom bar (Story wins).
func _layout_story_panel(compact: bool) -> void:
    if story_shade == null: return
    story_shade.visible = not compact
    story_result_bar.visible = compact
    story_title.visible = not compact   # the victory screen already shows the headline
    story_center.offset_top = 520.0 if compact else 0.0
    story_column.add_theme_constant_override("separation", 10 if compact else 24)

func _show_story_victory(headline: String, opponent: String) -> void:
    if victory_screen == null: return
    _layout_result(true)
    victory_screen.show_results([{"id": story_hero, "color": player_one.body_color}],
        [{"id": opponent, "color": player_two.body_color}], headline)

func _on_story_vs_finished() -> void:
    # Skipped early: READY keeps its normal length.
    if ready_remaining > 1.35: ready_remaining = 1.35
    if ready_remaining > 0: ready_label.show()

func _on_story_ending_finished() -> void:
    if story_state != "complete": return
    if victory_screen: victory_screen.clear()
    _layout_story_panel(false)
    story_panel.show()
    story_action.grab_focus()
    _queue_challenger_check(story_hero, "complete")

func apply_level(id: String) -> void:
    if id not in SetupScript.LEVEL_IDS: id = "debug"
    if id == active_level: return
    _clear_world()
    if id in FREEPLAY_WORLDS:
        apply_level("debug")
        active_level = id
        for n in preload("res://scripts/stage_layouts.gd").NAMES:
            var body: StaticBody3D = get_node(n)
            body.collision_layer = 0
            body.get_child(0).hide()
        for v in debug_visuals: v.hide()
        world = preload("res://scripts/character_world.gd").new()
        world.world_id = id
        add_child(world)
        var env: Environment = _world_env()
        for k in ["background_color", "ambient_light_color", "ambient_light_energy"]: world_environment[k] = env.get(k)
        env.background_color = Color("9ebabe") if id == "meadow" else Color("17191d")
        env.ambient_light_color = Color("bccac1") if id == "meadow" else Color("e0cfb6")
        env.ambient_light_energy = 0.85
        return
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
    if id == "weaver":
        stage_theme = preload("res://scripts/weaver_stage.gd").new()
        add_child(stage_theme)
    elif id != "debug":
        stage_theme = preload("res://scripts/stage_theme.gd").new()
        stage_theme.level_id = id
        add_child(stage_theme)

func _world_env() -> Environment:
    return (find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment

## Restore the base stage after a public freeplay world (keeps the base collider RIDs).
func _clear_world() -> void:
    if not world_environment.is_empty():
        var env: Environment = _world_env()
        for k in world_environment: env.set(k, world_environment[k])
        world_environment.clear()
    if is_instance_valid(world):
        remove_child(world)
        world.queue_free()
    world = null

func open_story() -> void:
    show_setup()
    story_encounter = 0
    story_route = []
    setup.hide()
    story_state = "ready"
    story_title.text = "STORY 01 / BOBO"
    story_detail.text = "THE GAUNTLET · 7 encounters ending with Mephisto · your hero is skipped\n\nFirst up: Bobo, a big goofball with a slow two-hit claw attack.\nDeplete Bobo's 400 HP. Dodge his claws, then punish the recovery!\nHe stays put. You have three stocks — watch the edges!\n\n" + _story_controls_text()
    story_choice_row.show()
    Unlocks.apply_to_option(story_character, [])
    story_action.text = "START ENCOUNTER"
    story_panel.show()
    story_character.grab_focus()

func _story_controls_text() -> String:
    if get_node_or_null("/root/MobileTouch") and get_node("/root/MobileTouch").touch_mode:
        return "Left pad: move / aim · Up: jump · Down: drop\nRight thumb: Attack / Special (hold to charge) · Setup: back"
    return "A / D move · Space jump · F basic · G special\nAim with WASD · Esc back to setup"

func _story_playable_ids() -> Array[String]:
    # Ice Mage is a Story-only NPC. Bobo's incomplete player kit is freeplay-only.
    var ids: Array[String] = load("res://scripts/roster.gd").ids()
    ids.erase("ice_mage")
    ids.erase("bobo")
    return ids

func story_opponent() -> String:
    return story_route[story_encounter] if story_encounter < story_route.size() else ""

func _story_name(id: String) -> String:
    return load("res://scripts/roster.gd").display_name(id).replace(" (Prototype)", "").to_upper()

func _story_display(id: String) -> String:
    return load("res://scripts/roster.gd").display_name(id).replace(" (Prototype)", "")

func _show_story_briefing() -> void:
    var opponent := story_opponent()
    story_title.text = "STORY %02d / %s" % [story_encounter + 1, _story_name(opponent)]
    var lines := "Defeat the Normal %s bot.\nBoth fighters start fresh with three stocks." % _story_display(opponent)
    if opponent == "ice_mage":
        lines = "Defeat the Normal Ice Mage. Watch for freezing Frost Bolts!\nBoth fighters start fresh with three stocks."
    elif opponent == "mephisto":
        lines = "LAST ENCOUNTER\nMephisto shifts between his girl and demon forms.\nBoth fighters start fresh with three stocks."
    story_detail.text = "%s\n\nCLEARED %d / %d\n\n%s" % [lines, story_encounter, story_route.size(), _story_controls_text()]
    story_action.text = "START ENCOUNTER"

func start_story() -> void:
    if story_state.begins_with("bag"):
        start_heavy_bag()
        return
    if story_state == "complete":
        open_story()
        return
    if story_state == "stage_complete":
        story_encounter += 1
        story_state = "ready"
        match_over = false
        bobo_health_bar.hide()
        if victory_screen: victory_screen.clear()
        _layout_story_panel(false)
        _show_story_briefing()
        story_action.grab_focus()
        return
    # Fresh encounter (from its briefing) gets the VS splash; Retry goes straight in.
    var fresh := story_state == "ready"
    if victory_screen: victory_screen.clear()
    _layout_story_panel(false)
    var slots := Config.default_slots()
    if story_encounter == 0:
        var selected = story_character.get_selected_metadata()
        if not selected is String or selected not in _story_playable_ids() or Unlocks.is_locked(selected):
            selected = "turbofit"
            for index in story_character.item_count:
                if story_character.get_item_metadata(index) == selected:
                    story_character.select(index)
                    break
        story_hero = selected
        story_route = STORY_ORDER.duplicate()
        story_route.erase(story_hero)
    var opponent := story_opponent()
    slots[0].character = story_hero
    slots[0].kind = "human"
    slots[0].device = -1
    slots[1].character = opponent
    slots[1].kind = "bot"
    slots[1].difficulty = "normal"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    _story_boss_next = opponent == "mephisto"
    _special_mode_start = true
    var started := start_match(slots, false, opponent == "bobo")
    _special_mode_start = false
    if started:
        story_state = "playing"
        hud_title.text = "STORY %02d — %s VS %s" % [story_encounter + 1, player_one.fighter_name, _story_name(opponent)]
        hud_controls.text = "YOU / P1: WASD move & aim · Space jump · F basic · G special\n%s · Esc: pause" % ("Bobo: 400 HP · slow two-hit claws · punish his recovery!" if opponent == "bobo" else "%s: Normal bot · three stocks" % _story_display(opponent))
        player_one.reset_fighter(p1_spawn, true)
        # Central floor lane keeps this large opponent clear of side platforms.
        player_two.reset_fighter(Vector3(0.6, 1.0, 0.0) if opponent == "bobo" else p2_spawn, true)
        player_one.facing = 1.0
        player_two.facing = -1.0
        _begin_ready()
        if fresh:
            # The match loads behind the splash; READY counts down once it clears.
            ready_remaining += story_vs.SECONDS
            ready_label.hide()
            story_vs.play(story_hero, opponent, Unlocks.is_locked(opponent), "STORY %02d / %02d" % [story_encounter + 1, story_route.size()])
    _story_boss_next = false

func _create_fighter(slot: Dictionary, index: int, bobo_encounter: bool, heavy_bag: bool) -> Node:
    if heavy_bag and index == 1: return load("res://scripts/heavy_bag.gd").new()
    if bobo_encounter and index == 1: return load("res://scripts/bobo_fighter.gd").new()
    # Preserved form-switching Story Mephisto (story_boss/, isolated from playable Mephisto).
    if _story_boss_next and index == 1 and slot.character == "mephisto":
        return load("res://story_boss/scripts/fighter.gd").new()
    if slot.character == "bobo": return load("res://scripts/bobo_player.gd").new()
    return FighterScript.new()

# ---------------------------------------------------------------- Challengers (unlocks)
## After a finished match: if a locked fighter's condition is met, the
## "A NEW FIGHTER APPROACHES" screen appears over the result after a short beat.
func _queue_challenger_check(hero: String, expected_state: String) -> void:
    var id := Unlocks.next_challenger()
    if id == "": return
    challenger_hero = hero if Unlocks.is_playable(hero) and hero != "bobo" else "teknium"
    _challenger_serial += 1
    var serial := _challenger_serial
    get_tree().create_timer(1.6).timeout.connect(func():
        if serial != _challenger_serial or story_state != expected_state: return
        if not (result_panel.visible or story_panel.visible): return
        result_panel.hide()
        if victory_screen: victory_screen.clear()
        story_panel.hide()
        challenger_screen.show_approach(id))

func start_challenger(id: String) -> void:
    var slots := Config.default_slots()
    slots[0].character = challenger_hero
    slots[0].kind = "human"
    slots[0].device = -1
    slots[1].character = id
    slots[1].kind = "bot"
    slots[1].difficulty = Unlocks.CHALLENGER_DIFFICULTY.get(id, "normal")
    slots[1].device = -1
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    _special_mode_start = true
    var started := start_match(slots, false, id == "bobo")
    _special_mode_start = false
    if not started:
        show_setup()
        return
    story_state = "challenger"
    challenger_id = id
    hud_title.text = "CHALLENGER — %s VS %s" % [player_one.fighter_name, _story_name(id)]
    player_one.reset_fighter(p1_spawn, true)
    player_two.reset_fighter(Vector3(0.6, 1.0, 0.0) if id == "bobo" else p2_spawn, true)
    player_one.facing = 1.0
    player_two.facing = -1.0
    _begin_ready()

func _first_human_character() -> String:
    for slot in active_slots:
        if slot.kind == "human": return slot.character
    return "teknium"

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

    var camera := preload("res://scripts/fortress_shared_camera.gd").new()
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
    # Fortress v9 (cameo is the Tek infiltration).
    add_child(preload("res://scripts/fortress_shootout_stage.gd").new())

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
    controls.text = "P1: WASD / Space jump / F basic / G special    |    P2: Arrows / Enter jump / K basic / L special\nPad: stick aim / A jump / X basic / B special    ·    Down: drop through    ·    Esc: pause"
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
    victory_screen = preload("res://scripts/victory_screen.gd").new()
    layer.add_child(victory_screen)
    layer.move_child(victory_screen, result_panel.get_index())
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
    if victory_screen: victory_screen.clear()
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
    if story_state == "bag_playing" and heavy_bag_mode:
        heavy_bag_mode.finish()
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
        # Deferred: disabling a body inside the attacker's physics callback pulls it out of the space mid-move.
        _park_fighter.call_deferred(fighter)
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    if story_state == "challenger":
        var beat: bool = player_one.stocks > 0 and player_two.stocks <= 0
        story_state = "challenger_done"
        if beat: Unlocks.record_unlock(challenger_id)
        winner_label.visible = false
        if beat: challenger_screen.show_joined(challenger_id)
        else: challenger_screen.show_escaped(challenger_id)
        return
    if story_state == "playing":
        var won: bool = player_one.stocks > 0 and player_two.stocks <= 0
        var last := story_encounter >= story_route.size() - 1
        var opponent := story_opponent()
        story_state = ("complete" if last else "stage_complete") if won else "lost"
        # Smash-style: the winner's name on the victory screen. Final clear: "STORY COMPLETE?" (Mike).
        story_title.text = ("STORY COMPLETE?" if last else "%s WINS!" % _story_name(story_hero)) if won else "TRY AGAIN"
        story_choice_row.hide()
        winner_label.visible = false
        if won:
            story_detail.text = "Bobo is all tuckered out. You win this first encounter!" if opponent == "bobo" else "%s defeated! %d of %d cleared." % [_story_display(opponent), story_encounter + 1, story_route.size()]
            story_action.text = "NEXT ENCOUNTER"
            _show_story_victory(story_title.text, opponent)
            if last:
                Unlocks.record_story_clear(story_hero)
                story_detail.text = "STORY COMPLETE?\n%s beat all %d encounters!\n\n%s\n%s" % [_story_name(story_hero), story_route.size(), StoryCredits.CLOSING, " · ".join(StoryCredits.NAMES)]
                story_action.text = "RESTART RUN"
                # Victory pose -> fade to black -> credits; the result panel follows.
                story_panel.hide()
                story_ending.play()
                return
            _layout_story_panel(true)
        else:
            story_detail.text = "Out of stocks! Bobo is still standing.\nRetry with three fresh stocks and Bobo at 400 HP." if opponent == "bobo" else "Out of stocks! %s wins this encounter.\nRetry with three fresh stocks for both fighters." % _story_display(opponent)
            story_action.text = "RETRY"
            _layout_story_panel(false)
        story_panel.show()
        story_action.grab_focus()
        return
    if survivors.is_empty():
        winner_label.text = "DRAW"
    elif teams_enabled:
        winner_label.text = "TEAM %s WINS!" % ("A" if sides[0] == 0 else "B")
    else:
        winner_label.text = "P%d %s WINS!" % [survivors[0].player_index, survivors[0].fighter_name]
    _show_victory(survivors)
    winner_label.visible = true
    result_panel.show()
    result_panel.get_node("Rematch").grab_focus()
    Unlocks.record_versus_match()
    _queue_challenger_check(_first_human_character(), "")

func _show_victory(survivors: Array) -> void:
    # Melee-style results: winner(s) pose-in to a freeze frame, everyone else claps.
    _layout_result(not survivors.is_empty())
    if survivors.is_empty() or victory_screen == null:
        return
    var winners: Array = []
    var losers: Array = []
    for fighter in fighters:
        var entry := {"id": fighter.character_id, "color": fighter.body_color}
        if fighter in survivors or (teams_enabled and fighter.team_id == survivors[0].team_id): winners.append(entry)
        else: losers.append(entry)
    victory_screen.show_results(winners, losers, winner_label.text)

func _layout_result(compact: bool) -> void:
    # compact = slim bar along the bottom so the victory screen stays visible
    result_panel.position = Vector2(290, 572) if compact else Vector2(290, 235)
    result_panel.size = Vector2(700, 132) if compact else Vector2(700, 250)
    winner_label.position = Vector2(20, 2) if compact else Vector2(20, 15)
    winner_label.size = Vector2(660, 52) if compact else Vector2(660, 110)
    winner_label.add_theme_font_size_override("font_size", 26 if compact else 30)
    for i in 2:
        var action: Button = result_panel.get_node("Rematch" if i == 0 else "ChangeFighters")
        action.position = Vector2(30 + i * 335, 62 if compact else 160)

func _reset_match() -> void:
    if story_state.begins_with("challenger"):
        return
    if story_state == "bag_done":
        start_heavy_bag()
        return
    if story_state in ["stage_complete", "complete", "lost"]:
        if story_ending.visible: return   # R doesn't restart the run during the credits
        start_story()
        return
    match_over = false
    winner_label.visible = false
    for fighter in fighters:
        fighter.process_mode = Node.PROCESS_MODE_INHERIT
        fighter.reset_fighter(fighter.spawn_position, true)
    result_panel.hide()
    if victory_screen: victory_screen.clear()
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
            if story_vs and story_vs.visible: story_vs.skip()
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

# ---------------------------------------------------------------- Heavy Bag mini-game
func open_heavy_bag() -> void:
    show_setup()
    setup.hide()
    story_state = "bag_ready"
    Unlocks.apply_to_option(story_character, [])
    story_title.text = "HEAVY BAG"
    story_detail.text = "15 seconds. Hit the bag as hard as you can.\nDeeper hits score more. Break all 4 layers, then shatter THE CORE\nfor a big bonus plus time bonus. Keep hitting to chain combos (up to x2).\n\nA / D move · Space jump · F basic · G special · Esc pause"
    story_choice_row.show()
    story_action.text = "START"
    story_panel.show()
    story_character.grab_focus()

func start_heavy_bag() -> void:
    var selected = story_character.get_selected_metadata()
    if not selected is String or selected not in _story_playable_ids() or Unlocks.is_locked(selected):
        selected = "turbofit"
    var slots := Config.default_slots()
    slots[0].character = selected
    slots[0].kind = "human"
    slots[0].device = -1
    slots[1].character = "teknium"   # placeholder id for validation; the bag replaces it
    slots[1].kind = "bot"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    if not start_match(slots, false, false, true):
        return
    story_state = "bag_playing"
    player_one.reset_fighter(p1_spawn, true)
    player_two.reset_fighter(Vector3(0.6, 1.0, 0.0), true)
    player_one.facing = 1.0
    heavy_bag_mode = preload("res://scripts/heavy_bag_mode.gd").new()
    heavy_bag_mode.name = "HeavyBagMode"
    add_child(heavy_bag_mode)
    heavy_bag_mode.setup(self, player_two, selected)
    _begin_ready()

func _park_fighter(fighter) -> void:
    if match_over and is_instance_valid(fighter):
        fighter.hide()
        fighter.process_mode = Node.PROCESS_MODE_DISABLED

func finish_heavy_bag(mode: Node, best: int, new_best: bool) -> void:
    match_over = true
    _cancel_ready()
    for fighter in fighters:
        fighter.controls_enabled = false
        fighter._clear_move_state()
        # Deferred: disabling a body inside the attacker's physics callback pulls it out of the space mid-move.
        _park_fighter.call_deferred(fighter)
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    story_state = "bag_done"
    story_title.text = ("SHATTERED! NEW BEST!" if new_best else "SHATTERED!") if mode.shattered else ("NEW BEST!" if new_best else "TIME!")
    var bonus: String = "\nCore shattered: +%d  ·  Time bonus: +%d" % [mode.SHATTER_BONUS, mode.time_bonus] if mode.shattered else ""
    story_detail.text = "%s\n\nSCORE  %d\nBEST  %d\n\nLayers broken %d/5%s\nHits %d · Core hits %d · Best combo %d · Deepest: %s" % [
        player_one.fighter_name, mode.score, best, mode.layers_broken, bonus, mode.hits, mode.core_hits, mode.best_chain, mode.depth_name(mode.deepest)]
    story_action.text = "TRY AGAIN"
    story_choice_row.show()
    winner_label.visible = false
    story_panel.show()
    story_action.grab_focus()
    _queue_challenger_check(mode.hero_id, "bag_done")

func _end_heavy_bag_mode() -> void:
    if is_instance_valid(heavy_bag_mode):
        remove_child(heavy_bag_mode)
        heavy_bag_mode.queue_free()
    heavy_bag_mode = null

extends Node3D
# Gameplay arena (Doc 02 §1: "main.tscn may keep its name; its responsibility
# becomes gameplay"). The player-facing routes no longer load this scene
# directly — scenes/match_flow.tscn hosts Character Select / Stage Select / the
# Story Encounter Briefing and constructs the arena with an immutable
# MatchLaunchConfig (WP-0 steps 3-5).
#
# Two ways in:
#   * the MatchFlow router sets `launch_config` BEFORE tree entry; _ready then
#     prewarms gameplay and reports `presentation_ready` (Doc 02 §6). The match
#     starts through start_match_from_config(), which consumes only the frozen
#     snapshot — mode, resolved slots, the launch stage and, for Story, the
#     encounter payload.
#   * a direct load (tests, F10 debug launcher) is the explicit Debug/F10 route
#     (Doc 02 §9): the arena builds its own Debug Match Setup launcher.
#
# WP-0 step 5: gameplay OWNS NO RESULTS SCREEN. At match resolution it produces
# the immutable end-state data (MatchResult / StoryOutcome, Doc 02 §4) and hands
# it to the router through the typed post-match payload (AppState
# .return_to_post_match) — the RETURN verb of Doc 02 §5 — which tears this arena
# down and lets the frontend present PostMatch. No frame of this scene survives
# behind Results, and no Results surface ever reads a live fighter.
#
# WP-0 steps 7-8: gameplay constructs NO production frontend any more. The
# in-arena Char/Stage panels and their VS entry route (open_vs, CSS -> SSS ->
# launch inside main.tscn) are DELETED — the player route lives in MatchFlow,
# which owns CSS/SSS/Story/PostMatch, and this scene is only the destination it
# launches with a validated MatchLaunchConfig. The Debug Match Setup screen is
# constructed on the explicit Debug/F10 route ONLY: a production arena never
# instantiates, shows or reads it.

signal presentation_ready

const FighterScript = preload("res://scripts/fighter.gd")
const Config = preload("res://scripts/match_config.gd")
const DemoStyle = preload("res://scripts/demo_style.gd")
const MatchResultScript = preload("res://scripts/match_result.gd")
const AppStateScript = preload("res://scripts/app_state.gd")
# Debug Match Setup (Doc 02 §9): built by the explicit Debug/F10 route only.
const SetupScript = preload("res://scripts/match_setup.gd")
# Gameplay stage ids: the launch stage is validated against the shared catalog
# (the debug setup reads the same catalog for its own level list).
const StageCatalog = preload("res://scripts/catalogs/stage_catalog.gd")
# Adapters only: the launch snapshot's typed kinds/input sources are mapped back
# to the legacy slot vocabulary start_match() already speaks.
const StateScript = preload("res://scripts/match_flow_state.gd")

const MATCH_FLOW_SCENE := "res://scenes/match_flow.tscn"
const HOME_SCENE := "res://scenes/home.tscn"

# Shipped Story HUD sentence (main.gd start_story), now built from the launch
# config's Story payload: enemy identity + HP come from the snapshot.
const STORY_CONTROLS_TEMPLATE := "YOU / P1: WASD move & aim · Space jump · F basic · G special · E shield\n%s: %d HP, stationary, no attacks. Deplete his HP! · Esc: back to main"

# The immutable launch snapshot handed over by the MatchFlow router (Doc 02 §3).
# Set before tree entry; null for every direct load.
var launch_config = null
var _launched_from_flow := false
var ready_remaining := 0.0
var go_remaining := 0.0
var ready_label: Label

var fighters: Array = []
var active_level := "debug"
var stage_theme: Node3D
var debug_visuals: Array[Node3D] = []
var hud_labels: Array[Label] = []
# Debug Match Setup (Doc 02 §9). Null in a production arena: the launcher is
# constructed only by the explicit Debug/F10 route and is never production
# state storage (no production code path reads a field on it).
var setup: Control = null
var teams_enabled := false
var active_slots: Array = []
# Story state machine (Doc 07 §11-16). One encounter only, driven entirely by
# the MatchLaunchConfig's Story payload: "" = freeplay, "playing" while the
# encounter runs, "complete"/"lost" at resolution (the Story Result itself is a
# frontend surface — the arena returns to the MatchFlow host).
var story_state := ""
var _story_encounter := false
var _story_won := false
var hud_title: Label
var hud_controls: Label
var freeplay_controls: String
var bobo_health_bar: ProgressBar

var player_one: CharacterBody3D
var player_two: CharacterBody3D
var p1_label: Label
var p2_label: Label
var match_over := false
# Elimination order observed during the match (player_index sequence). The
# result snapshot is built from it at resolution, before any reset mutates
# the fighters (Doc 06 §4/§19).
var _elimination_order: Array = []
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
    # The legacy entry flag selected an in-arena screen route; that route is
    # gone (WP-0 steps 7-8). The flag is consumed so a stale value can never
    # re-enter it.
    AppStateScript.enter_mode = "debug"
    if launch_config != null:
        # MatchFlow destination (Doc 02 §1/§6): the router already validated the
        # setup and constructed this arena with an immutable MatchLaunchConfig,
        # so NO frontend screen is constructed here. Gameplay is prewarmed and
        # reports readiness; the match starts when the router releases the
        # frontend.
        _launched_from_flow = true
        call_deferred("_announce_presentation_ready")
    else:
        # Explicit Debug/F10 route (Doc 02 §9): the developer launcher is the
        # arena's own setup surface, and this is the ONLY construction site.
        _build_debug_setup()
    # Arriving through the persistent transition layer: the previous screen
    # may have held its frame for the crossfade (Main Menu PLAY). Reveal this
    # scene underneath it — never leave a stale hold covering the arena.
    Frontend.release(0.28)

func _build_debug_setup() -> void:
    # Debug Match Setup (Doc 02 §9): instantiate the launcher ONLY on the
    # explicit Debug/F10 route. It consumes the shared catalogs (match_setup.gd
    # builds its level list from StageCatalog, never a private array), it is NOT
    # production state storage — a production arena never constructs it and no
    # production code path reads a field on it — and it never receives
    # player-facing validation errors during VS: the VS route validates through
    # MatchFlowState in the router before a MatchLaunchConfig exists.
    var menu_layer := CanvasLayer.new()
    menu_layer.name = "DebugMenuLayer"
    menu_layer.layer = 10
    add_child(menu_layer)
    setup = SetupScript.new()
    menu_layer.add_child(setup)
    setup.start_requested.connect(start_match)
    setup.back_requested.connect(back_to_menu)

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
        if setup != null and setup.visible and setup.close_help(): return
        # Consume the event BEFORE the route action: the arena is the current
        # scene on a flow launch, so a route change frees this node and any
        # later statement here would run on a freed instance.
        get_viewport().set_input_as_handled()
        if setup != null and not setup.visible:
            # Debug route with a match running: the setup screen reopens in
            # place (shipped debug launcher behaviour).
            show_setup()
        else:
            # Debug launcher at rest (its screen is already up) and production
            # both leave the arena for Main. Production has NO arena-side setup
            # screen any more (Doc 02 §9 / WP-0 steps 7-8): the in-arena CSS/SSS
            # it used to reopen are deleted and the frontend owns the route.
            back_to_menu()
    # WP-0 step 5: the raw R rematch bypass is REMOVED. A resolved match hands
    # its end-state payload to the frontend, which owns the visible Results
    # actions (Doc 06 §9: no hidden raw rematch; Doc 09 WP-5 "remove host raw R
    # bypass"). Results input is owned by the PostMatch surface.

func back_to_menu() -> void:
    # Leaving the arena for the frontend: the shipped stand-down (cancel READY,
    # drop the encounter-only HUD, stop the fighters, clear live projectiles)
    # runs on BOTH routes — production has no setup screen to present, but the
    # route still leaves a stopped, story-free arena behind (Doc 02 §9).
    _stand_down_match()
    if setup != null:
        setup.show()
        setup.find_child("StartMatchButton",true,false).grab_focus()
    get_tree().change_scene_to_file(HOME_SCENE)

func show_setup() -> void:
    _stand_down_match()
    if setup == null:
        # Production arena (MatchLaunchConfig): no arena-side setup screen
        # exists to show (Doc 02 §9).
        return
    setup.show()
    setup.find_child("StartMatchButton",true,false).grab_focus()

func _stand_down_match() -> void:
    # Shipped stand-down shared by the debug launcher re-open and the Main
    # route: cancel READY, leave the story state, hide the encounter-only HUD,
    # stop every fighter and clear live projectiles.
    _cancel_ready()
    story_state = ""
    _story_encounter = false
    if bobo_health_bar != null:
        bobo_health_bar.hide()
    for fighter in fighters:
        fighter.controls_enabled = false
        fighter._clear_move_state()
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    match_over = false

func start_match(slots: Array, teams: bool, bobo_encounter := false, level := "") -> bool:
    var validation_slots := slots.duplicate(true)
    if bobo_encounter and validation_slots[1].character == "bobo":
        validation_slots[1].character = "ice_mage"
    var error := Config.validate(validation_slots, teams)
    if not error.is_empty():
        if setup != null:
            # Debug route only. The VS route validates through MatchFlowState
            # (Doc 02 §2) before a MatchLaunchConfig exists, so production never
            # reaches a player-facing error through this screen (Doc 02 §9).
            setup.error_label.text = error
        return false
    # The launch stage rides the immutable snapshot; the debug launcher's own
    # model is read ONLY when the caller passed no stage (the debug route).
    var launch_level := level
    if launch_level == "" and setup != null:
        launch_level = setup.selected_level()
    apply_level(launch_level)
    for fighter in fighters:
        remove_child(fighter)
        fighter.queue_free()
    for projectile in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("goo_puddles"):
        projectile.queue_free()
    fighters.clear()
    for label in hud_labels:
        label.text = ""
    story_state = ""
    _story_encounter = false
    _story_won = false
    hud_title.text = "NRCU"
    hud_controls.text = freeplay_controls
    active_slots = slots.duplicate(true)
    teams_enabled = teams
    _elimination_order.clear()
    match_over = false
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
    if setup != null:
        # Debug launcher: the setup screen steps aside once the match starts. A
        # production arena has no setup screen (Doc 02 §9).
        setup.hide()
    bobo_health_bar.visible = bobo_encounter
    _begin_ready()
    return true

# --- MatchFlow launch contract (Doc 02 §3, §6, §10.5) -----------------------

func _announce_presentation_ready() -> void:
    # Doc 02 §6: the destination reports it is visually ready BEFORE the router
    # releases the frontend, so the LAUNCH transition never happens over a
    # black/cursor-only construction frame. The world, HUD and result layer are
    # already built at this point; what is still constructed synchronously after
    # the reveal is the match itself (start_match_from_config spawns fighters).
    presentation_ready.emit()

func start_match_from_config(cfg) -> bool:
    # Gameplay consumes the immutable snapshot only (Doc 02 §3): the config
    # carries the mode, the resolved slots, the launch stage and the Story
    # payload, so nothing here reaches into Character Select, Stage Select, the
    # Story Briefing, the Debug Setup model or any screen node.
    if cfg == null or not cfg.is_valid():
        return false
    var slots: Array = []
    for entry in cfg.slots():
        var slot: Dictionary = entry
        slots.append({
            "kind": StateScript.kind_to_legacy(int(slot.get("kind", 0))),
            "character": str(slot.get("fighter_id", "")),
            "team": int(slot.get("team_id", 0)),
            "difficulty": str(slot.get("difficulty", "normal")),
            "device": StateScript.input_source_to_legacy_device(slot.get("input_source", {})),
        })
    var started: bool = start_match(slots, int(cfg.mode()) == 1, cfg.has_story(), str(cfg.stage_id()))
    if started and cfg.has_story():
        _begin_story_encounter(cfg.story_payload())
    return started

func _begin_story_encounter(payload: Dictionary) -> void:
    # The Story state machine over the frozen payload (Doc 02 §3/§4): the
    # encounter's HUD copy and its spawn/facing metadata arrive in the snapshot,
    # exactly the values the shipped start_story() applied from the briefing.
    _story_encounter = true
    _story_won = false
    story_state = "playing"
    hud_title.text = str(payload.get("hud_title_template", "STORY 01 — %s VS BOBO")) % player_one.fighter_name
    # The encounter owns the enemy identity and its HP; the shipped HUD sentence
    # is kept with the catalog's values (BOBO -> "Bobo" sentence case).
    var enemy_name := str(payload.get("enemy_display_name", "BOBO")).capitalize()
    var enemy_hp := int(payload.get("enemy_hp", 400))
    hud_controls.text = STORY_CONTROLS_TEMPLATE % [enemy_name, enemy_hp]
    player_one.reset_fighter(Vector3(payload.get("player_spawn", p1_spawn)), true)
    # Central floor lane keeps this large opponent clear of side platforms.
    player_two.reset_fighter(Vector3(payload.get("enemy_spawn", Vector3(0.6, 1.0, 0.0))), true)
    player_one.facing = float(payload.get("player_facing", 1.0))
    player_two.facing = float(payload.get("enemy_facing", -1.0))
    _begin_ready()

func _return_to_post_match(payload: Dictionary) -> void:
    # Gameplay end -> the frontend owns post-match (Doc 02 §1, §5 RETURN): the
    # typed end-state payload (MatchResult / StoryOutcome) is handed to the
    # MatchFlow router, and this scene change tears the completed arena down
    # before the PostMatch surface becomes interactive. Gameplay never shows a
    # Results screen and never reads a live fighter for one.
    AppStateScript.return_to_post_match(payload)
    get_tree().change_scene_to_file(MATCH_FLOW_SCENE)

func apply_level(id: String) -> void:
    # Gameplay stage application. The id arrives from the immutable launch
    # snapshot (or the debug launcher's own model); unknown ids fall back to the
    # debug arena exactly like before, validated against the shared catalog.
    if not StageCatalog.has(id): id = "debug"
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
    # The Esc destination is route-dependent: the debug launcher opens its own
    # setup screen; a production arena (launch_config) has none and returns to
    # Main (WP-0 steps 7-8 removed the in-arena setup screens).
    var escape_hint := "match setup" if launch_config == null else "main menu"
    controls.text = "P1: WASD / Space jump / F basic / G special / E shield    |    P2: Arrows / Enter jump / K basic / L special / O shield\nPad: stick aim / A jump / X basic / B special / shoulder shield    ·    Down: drop through    ·    Esc: %s" % escape_hint
    controls.name = "MatchControls"
    hud_controls = controls
    freeplay_controls = controls.text
    controls.position = Vector2(20, 672)
    controls.size = Vector2(1240, 46)
    controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    controls.add_theme_font_size_override("font_size", 15)
    controls.modulate = Color(0.7, 0.78, 0.9)
    layer.add_child(controls)

    # WP-0 step 5: gameplay builds no Results screen. The result layer moved to
    # the MatchFlow host's PostMatch surface (scripts/frontend/post_match.gd);
    # at resolution this arena hands the immutable payload over and RETURNs.
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

func _on_fighter_eliminated(loser: CharacterBody3D) -> void:
    if match_over:
        return
    # Elimination order is match-layer state: recorded here, before the
    # survivor check can end the match (Doc 06 §4).
    if int(loser.stocks) <= 0 and loser.player_index not in _elimination_order:
        _elimination_order.append(loser.player_index)
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
        _story_won = player_one.stocks > 0 and player_two.stocks <= 0
        story_state = "complete" if _story_won else "lost"
        # Doc 02 §1/§4: the arena produces the typed StoryOutcome and RETURNs to
        # the MatchFlow router, which owns the post-match presentation (the
        # shipped Story result state today — Doc 07 §16: the story wording with
        # replay/retry + MAIN MENU, never the multiplayer Results screen).
        # Deferred so this frame's resolution stays intact.
        var encounter_id: String = launch_config.story_encounter_id() if launch_config != null and launch_config.has_story() else ""
        call_deferred("_return_to_post_match", AppStateScript.story_return_payload(
            _story_won, str(encounter_id), str(player_one.character_id), str(active_level), launch_config))
        return
    # Explicit result snapshot at match resolution, before any reset mutates the
    # fighter state (Doc 06 §4): stable fighter ids, explicit placement, teams
    # and winner flags. PostMatch is pure presentation over this payload — no
    # live-fighter node is ever consulted for a result again.
    var result = MatchResultScript.resolve(fighters, teams_enabled, _elimination_order)
    call_deferred("_return_to_post_match", AppStateScript.vs_return_payload(
        result, launch_config, teams_enabled, str(active_level), active_slots))

func _reset_match() -> void:
    # Local match restart (debug launcher / test lifecycle). Player-facing
    # REMATCH is the PostMatch route action: it LAUNCHes a fresh arena from the
    # preserved MatchLaunchConfig instead of restarting this one in place.
    if _story_encounter and match_over:
        # A finished Story encounter is replayed through the Story Result's
        # REPLAY/RETRY (the arena is a fresh launch by then), so a local reset
        # never restarts a resolved encounter in place.
        return
    _elimination_order.clear()
    match_over = false
    for fighter in fighters:
        fighter.reset_fighter(fighter.spawn_position, true)
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


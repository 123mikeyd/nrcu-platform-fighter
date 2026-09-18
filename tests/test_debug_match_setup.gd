extends SceneTree
# Debug Match Setup isolation — Doc 02 §9 (WP-0 step 8).
#
# The debug launcher is developer tooling:
#   * it is instantiated ONLY on the explicit Debug/F10 route (a direct
#     main.tscn load, which is exactly what home.gd's F10 developer route
#     performs: enter_mode "debug" + main.tscn);
#   * a PRODUCTION arena (constructed from an immutable MatchLaunchConfig by the
#     MatchFlow router) never constructs it — arena.setup is null there;
#   * it consumes the shared catalogs: its level list, captions and thumbnails
#     come from StageCatalog (no private array);
#   * it is not production state storage: a production launch reads no field on
#     it — the launch stage rides the immutable snapshot;
#   * the removed in-arena CSS/SSS constructs stay removed.
const StageCatalog = preload("res://scripts/catalogs/stage_catalog.gd")
const AppStateScript = preload("res://scripts/app_state.gd")

var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func stage_texts() -> Array:
    var texts: Array = []
    for entry in StageCatalog.entries():
        texts.append(str(entry["dropdown_text"]))
    return texts

func run():
    await part_a_debug_route_constructs_launcher()
    await part_b_catalog_consumption()
    await part_c_production_arena_has_no_setup()
    if failures == 0:
        print("PASS: debug match setup isolated (Debug/F10 route only, StageCatalog-driven, absent from production arenas)")
    quit(1 if failures else 0)

# ---------------------------------------------------------------------------
# Part A — the explicit Debug/F10 route constructs the launcher; the removed
# in-arena production constructs stay removed.
# ---------------------------------------------------------------------------
func part_a_debug_route_constructs_launcher() -> void:
    # The F10 developer route passes through Main: enter_mode "debug" + main.tscn.
    AppStateScript.enter_mode = "debug"
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await frames(5)
    check(arena.setup != null and arena.setup.visible, "the Debug/F10 route constructs its setup launcher")
    check(arena.get_node_or_null("DebugMenuLayer") != null, "the launcher lives on the debug layer")
    check(arena.setup.find_child("StartMatchButton", true, false) != null, "the launcher keeps its Start control")
    # WP-0 steps 7-8: no in-arena CSS/SSS construct survives.
    check(arena.get("char_panel") == null and arena.get("stage_panel") == null,
        "main.gd exposes no in-arena char/stage panel handles")
    check(arena.get("char_select") == null and arena.get("stage_select") == null and arena.get("selection_state") == null,
        "no in-arena CSS/SSS screen instance or selection mirror survives in gameplay")
    check(arena.get("open_vs") == null, "the in-arena VS entry route is gone")
    check(arena.find_child("CharPanel", true, false) == null and arena.find_child("StagePanel", true, false) == null,
        "no in-arena CSS/SSS host nodes exist in the arena")
    check(arena.setup.find_child("StageSelect", true, false) == null, "the debug setup hosts no stage page")
    # The debug launcher still starts a match in place.
    arena.setup._start()
    await frames(3)
    check(arena.fighters.size() >= 2 and not arena.setup.visible, "the debug launcher starts a match in place")
    arena.queue_free()
    await frames(3)

# ---------------------------------------------------------------------------
# Part B — the launcher consumes the shared StageCatalog.
# ---------------------------------------------------------------------------
func part_b_catalog_consumption() -> void:
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await frames(5)
    var setup = arena.setup
    var ids: Array = StageCatalog.ids()
    var texts: Array = stage_texts()
    check(setup.selected_level() == str(ids[0]), "the launcher opens on the catalog's first stage")
    var items: Array = []
    for i in setup.level.item_count:
        items.append(setup.level.get_item_text(i))
    check(items == texts, "the level dropdown is the StageCatalog list (no private array)")
    for i in ids.size():
        var card = setup.find_child("StageCard" + str(i), true, false)
        check(card != null, "stage card %d exists from the catalog" % i)
        var thumb = setup.find_child("StageThumbnail" + str(i), true, false)
        check(thumb != null and thumb.texture != null, "thumbnail %d loads from the catalog path" % i)
        if card != null:
            card.pressed.emit()
            await frames(1)
            check(setup.selected_level() == str(ids[i]), "card %d selects its catalog stage directly" % i)
    setup.select_level_by_id("sky")
    await frames(1)
    check(setup.selected_level() == "sky", "select_level_by_id resolves through the catalog")
    # LEVEL is a regular value row over the same catalog list (the stage page it
    # used to open was removed with WP-0 steps 7-8).
    check(setup.main_menu.rows.size() >= 2, "the debug menu carries its rows")
    var level_row: Dictionary = setup.main_menu.rows[1]
    check(str(level_row.get("kind", "")) == "value", "LEVEL is a value row, not a stage-page action")
    check(level_row.get("values", []) == texts, "the LEVEL row offers the catalog stage list")
    # The debug launcher applies its own catalog-selected stage on Start.
    setup.select_level_by_id("toy_room")
    setup._start()
    await frames(3)
    check(arena.active_level == "toy_room", "the debug launcher applies its own catalog-selected stage")
    arena.queue_free()
    await frames(3)

# ---------------------------------------------------------------------------
# Part C — a production arena never constructs the debug launcher.
# ---------------------------------------------------------------------------
func part_c_production_arena_has_no_setup() -> void:
    var vs = load("res://tests/fixtures/vs_route.gd").new()
    var host = await vs.enter(self)
    var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "toy_room")
    check(arena != null and is_instance_valid(arena), "the production route launches the arena")
    if arena == null or not is_instance_valid(arena):
        return
    check(arena.setup == null, "a production arena (MatchLaunchConfig) constructs NO debug setup screen")
    check(arena.get_node_or_null("DebugMenuLayer") == null, "the debug launcher layer is not built on a production launch")
    check(arena.find_child("StartMatchButton", true, false) == null and arena.find_child("LevelSelect", true, false) == null,
        "no debug launcher control exists in a production arena")
    check(bool(arena._launched_from_flow), "gameplay knows it was launched from the flow")
    check(arena.active_level == "toy_room", "the stage comes from the immutable snapshot, never a hidden model")
    await vs.free_arenas(self)

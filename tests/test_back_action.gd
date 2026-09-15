extends SceneTree
# Shared BackAction contract: one component, one authored anchor, one quiet
# header grammar, and a safe-edge hit area on every migrated screen.

const COMPONENT_PATH := "res://scenes/components/BackAction.tscn"
const SAFE_RIGHT := 1224.0
const CONTENT_INSET := 24.0
const SCREENS := {
    "character_select": {
        "path": "res://scenes/character_select.tscn",
        "back_path": "ReferenceFrame/Header/BackAction",
    },
    "story_select": {
        "path": "res://scenes/story_select.tscn",
        "back_path": "ReferenceFrame/Header/BackAction",
    },
    "story_briefing": {
        "path": "res://scenes/story_briefing.tscn",
        "back_path": "ReferenceFrame/Header/BackAction",
    },
    "story_result": {
        "path": "res://scenes/story_result.tscn",
        "back_path": "ReferenceFrame/Header/BackAction",
    },
    "how_to_play": {
        "path": "res://scenes/how_to_play.tscn",
        "back_path": "ReferenceFrame/Header/HelpBack",
    },
}

var failures := 0

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for _i in count:
        await process_frame

func run() -> void:
    var packed := load(COMPONENT_PATH) as PackedScene
    check(packed != null, "BackAction component scene exists")
    if packed == null:
        quit(1)
        return

    var probe_host := Control.new()
    probe_host.name = "BackActionProbeHost"
    probe_host.size = Vector2(1280.0, 720.0)
    root.add_child(probe_host)
    var probe := packed.instantiate()
    probe.name = "ProbeBack"
    probe.position = Vector2(1060.0, 30.0)
    probe.size = Vector2(164.0, 40.0)
    probe_host.add_child(probe)
    await frames(3)

    check(probe is Button, "BackAction root remains Button-compatible")
    check(probe.text == "BACK", "BackAction uses the canonical BACK label")
    var anchor := probe.get_node_or_null("CursorAnchor")
    var rail := probe.get_node_or_null("BackRail")
    check(anchor != null and anchor.has_method("anchor_position"),
        "BackAction owns an authored CursorAnchor")
    check(rail != null and rail is Panel, "BackAction owns its shared BackRail")
    check(absf(float(probe.get_theme_stylebox("normal").content_margin_right) - CONTENT_INSET) < 0.01,
        "BackAction normal style carries the S24 optical right inset")
    check(probe.get_theme_stylebox("normal").bg_color.a == 0.0,
        "BackAction idle style has no permanent surface")
    check(probe.get_theme_stylebox("normal").border_width_left == 0,
        "BackAction idle style has no permanent border")
    check(not rail.visible, "BackAction rail is quiet while idle")
    probe.mouse_entered.emit()
    check(rail.visible, "BackAction rail appears on hover")
    probe.mouse_exited.emit()
    check(not rail.visible, "BackAction rail clears after hover")
    probe.grab_focus()
    await frames(1)
    check(rail.visible, "BackAction rail appears on focus")
    probe.release_focus()
    await frames(1)
    check(not rail.visible, "BackAction rail clears after focus")

    for screen_id in SCREENS:
        var spec: Dictionary = SCREENS[screen_id]
        var screen_scene := load(str(spec["path"])) as PackedScene
        check(screen_scene != null, "%s scene loads" % screen_id)
        if screen_scene == null:
            continue
        var screen := screen_scene.instantiate()
        root.add_child(screen)
        await frames(3)
        var back := screen.get_node_or_null(str(spec["back_path"]))
        check(back != null and back is Button, "%s uses a Button-compatible BackAction" % screen_id)
        if back != null:
            check(back.scene_file_path == COMPONENT_PATH,
                "%s uses the shared BackAction scene" % screen_id)
            check(back.text == "BACK", "%s uses the canonical BACK label" % screen_id)
            check(back.get_node_or_null("CursorAnchor") != null,
                "%s BackAction keeps its authored CursorAnchor" % screen_id)
            check(back.get_node_or_null("BackRail") != null,
                "%s BackAction keeps its shared BackRail" % screen_id)
            var expected_x_ratio := 0.2 if screen_id == "how_to_play" else 0.8
            check(absf(float(back.get_node("CursorAnchor").x_ratio) - expected_x_ratio) < 0.01,
                "%s preserves its authored Back cursor hotspot ratio" % screen_id)
            check(absf(back.get_global_rect().end.x - SAFE_RIGHT) < 0.01,
                "%s BackAction hit area ends at the ReferenceFrame safe edge" % screen_id)
        screen.queue_free()
        await frames(2)

    var stage_script = load("res://scripts/stage_select.gd")
    var stage = stage_script.new()
    root.add_child(stage)
    await frames(2)
    var stage_slots: Array = []
    for entry in load("res://scripts/catalogs/stage_catalog.gd").entries():
        stage_slots.append({
            "id": str(entry.get("id", "")),
            "name": str(entry.get("display_name", "")),
            "tex": str(entry.get("thumbnail", "")),
        })
    stage.build(stage_slots)
    await frames(3)
    var stage_back: Button = stage.get_back_button()
    check(stage_back != null and stage_back.scene_file_path == COMPONENT_PATH,
        "Stage Select builds its Back action from the shared component")
    check(stage_back != null and stage_back.get_node_or_null("CursorAnchor") != null,
        "Stage Select keeps the shared authored CursorAnchor")
    check(stage_back != null and absf(stage_back.get_global_rect().end.x - SAFE_RIGHT) < 0.01,
        "Stage Select Back hit area ends at the ReferenceFrame safe edge")
    stage.queue_free()
    await frames(2)

    probe_host.queue_free()
    await frames(2)
    if failures == 0:
        print("PASS: shared BackAction component, safe-edge geometry, inset, hover/focus rail, and migrated screens")
    quit(1 if failures else 0)

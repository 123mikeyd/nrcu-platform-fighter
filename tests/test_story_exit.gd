extends SceneTree
# Story exit path (Doc 07 §11-16) — MIGRATED for WP-0 step 4: the briefing is
# hosted by the MatchFlow frontend, and its exit animation replaces the retired
# StoryStage flow. Back follows the player route Story -> Main.
#
# This suite previously guarded every assertion behind a removed node and
# passed VACUOUSLY with zero checks. It is migrated so that the legacy node
# being gone is itself asserted, and the exit contract runs unconditionally.
var failures := 0
var story

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func run():
    root.size = Vector2i(1280, 720)
    story = load("res://tests/fixtures/story_route.gd").new()
    var host = await story.enter(self)
    var briefing = host.story_briefing()
    check(briefing != null and briefing.visible, "story open")
    check(briefing.find_child("StoryStage", true, false) == null,
        "the legacy StoryStage overlay is gone (asserted, not assumed)")
    check(briefing.find_child("FighterCard0", true, false) == null,
        "the legacy card row is gone")
    if briefing == null:
        quit(1)
        return
    briefing.back_button().pressed.emit()
    await create_timer(0.05).timeout
    check(briefing.is_exiting(), "exit animation started")
    check(briefing.visible, "the briefing stays presented for the length of its exit")
    check(root.get_node_or_null("MainArena") == null, "no arena is constructed for a Back return")
    await create_timer(0.9).timeout
    check(not briefing.visible, "the briefing surface is closed after the exit animation")
    check(current_scene != null and str(current_scene.scene_file_path).find("home.tscn") != -1,
        "the exit finishes on the Main route")
    if current_scene != null:
        current_scene.queue_free()
    await story.free_hosts(self)
    if failures == 0: print("PASS: story exit animation path (hosted briefing, unconditional checks, Main route)")
    quit(1 if failures else 0)

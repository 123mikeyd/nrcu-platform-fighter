extends RefCounted
# Shared helper for the WP-0 step-4 Story-route test migration.
#
# The Story route is frontend-owned: Main Menu STORY MODE -> the MatchFlow host
# in story mode -> the Encounter Briefing -> the encounter launch. Tests enter
# it exactly the way the player does, and gameplay is only ever constructed by
# the host from an immutable MatchLaunchConfig.
#
# Usage (inside a SceneTree test):
#     var story = load("res://tests/fixtures/story_route.gd").new()
#     var host = await story.enter(self)
#     var arena = await story.start_encounter(self, host)
#
# Not a test runner: run_all_tests.py discovers tests/test_*.gd only.

const AppStateScript = preload("res://scripts/app_state.gd")
const FLOW_SCENE := "res://scenes/match_flow.tscn"

var last_host: Node = null

func enter(tree: SceneTree, fighter_id: String = "", mode: String = "story") -> Node:
    # Fresh Story entry: the host is the only scene, as after Main's STORY MODE
    # row (mode "story"; pass "" to keep whatever entry flag is set).
    if fighter_id != "":
        AppStateScript.story_fighter_id = fighter_id
    if mode != "":
        AppStateScript.enter_mode = mode
    var host = (load(FLOW_SCENE) as PackedScene).instantiate()
    tree.root.add_child(host)
    last_host = host
    await settle(tree, 12)
    return host

func start_encounter(tree: SceneTree, host: Node) -> Node:
    # Presses the briefing's own START ENCOUNTER action and waits for the full
    # §6 handshake: the destination is constructed hidden, the briefing plays
    # its exit, the match starts from the config and the frontend is released.
    # Tests wait for the release so the arena is the live frame (it is the
    # current scene by then, which is what the post-match route replaces).
    if host == null or not is_instance_valid(host) or host.story_briefing() == null:
        return null
    host.story_briefing().action_button().pressed.emit()
    # The host constructs its destination synchronously and hands it over before
    # tree entry: read the node the host itself owns (a name lookup in root is
    # ambiguous while a previous arena is still pending free).
    var arena: Node = host.gameplay_node()
    for i in 240:
        await tree.process_frame
        if arena != null and is_instance_valid(arena) and not arena.fighters.is_empty() and not is_instance_valid(host):
            return arena
    return arena

func wait_for_flow(tree: SceneTree, previous_id: int = 0) -> Node:
    # Waits for a MatchFlow host — optionally a NEW one (post-match re-entry).
    # Iterates the tree: duplicate sibling names get auto-suffixed, and a test
    # that mounted a host manually outlives the route (the engine only frees the
    # CURRENT scene on a scene change).
    for i in 300:
        await tree.process_frame
        var newest: Node = null
        for child in tree.root.get_children():
            if not child.has_method("entry_mode"):
                continue
            newest = child
            if previous_id != 0 and child.get_instance_id() == previous_id:
                newest = null
                continue
            if previous_id != 0:
                return child
        if previous_id == 0 and newest != null:
            return newest
    return null

func free_hosts(tree: SceneTree) -> void:
    # Test hygiene: a manually mounted host is not the current scene, so the
    # route's own scene change cannot free it. Never leave one mounted across
    # parts (the next part's wait_for_flow would find the stale one).
    for child in tree.root.get_children():
        if child.has_method("entry_mode"):
            child.queue_free()
    await settle(tree, 3)

func wait_for_scene(tree: SceneTree, scene_name: String) -> Node:
    # Waits for a change_scene_to_file destination (home.tscn / match_flow.tscn).
    for i in 300:
        await tree.process_frame
        var scene = tree.current_scene
        if scene != null and str(scene.scene_file_path).find(scene_name) != -1:
            return scene
    return null

func wait_for(tree: SceneTree, condition: Callable, limit: int = 180) -> bool:
    for i in limit:
        await tree.process_frame
        if bool(condition.call()):
            return true
    return false

func run_ready(arena: Node) -> void:
    # Completes the shipped READY gate (1.35 s) so combat fixtures run against
    # the live match, exactly like the pre-migration tests did.
    if arena != null and is_instance_valid(arena):
        arena._physics_process(arena.ready_remaining)

func settle(tree: SceneTree, frames: int) -> void:
    for i in frames:
        await tree.process_frame

extends RefCounted
# Shared helper for the WP-0 step-5 PostMatch-route suites (and the migrated
# Results / route tests).
#
# The VS route is frontend-owned: the MatchFlow host is entered the way Main
# PLAY enters it, fighters are committed through the Character Select screen's
# own commit path, READY pushes Stage Select, a stage confirm LAUNCHes gameplay
# from an immutable MatchLaunchConfig, and the completed match RETURNs to the
# host's PostMatch surface.
#
# Usage (inside a SceneTree test):
#     var vs = load("res://tests/fixtures/vs_route.gd").new()
#     var host = await vs.enter(self)
#     var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "sky")
#
# Not a test runner: run_all_tests.py discovers tests/test_*.gd only.

const AppStateScript = preload("res://scripts/app_state.gd")
const FLOW_SCENE := "res://scenes/match_flow.tscn"

var last_host: Node = null

func enter(tree: SceneTree, mode: String = "vs") -> Node:
    AppStateScript.enter_mode = mode
    var host = (load(FLOW_SCENE) as PackedScene).instantiate()
    tree.root.add_child(host)
    last_host = host
    await settle(tree, 12)
    return host

# --- configuration ----------------------------------------------------------

func set_kind(host: Node, player_index: int, kind: String) -> bool:
    # The station kind cycles human -> bot -> empty through the bay control.
    var css = host.char_select()
    if css == null:
        return false
    for i in 4:
        if str(host.selection_state.slots[player_index - 1].get("kind", "")) == kind:
            return true
        css._on_kind_clicked(player_index - 1)
    return str(host.selection_state.slots[player_index - 1].get("kind", "")) == kind

func set_mode(host: Node, mode: int) -> bool:
    # FFA (0) / teams (1) through the header mode control.
    var css = host.char_select()
    if css == null:
        return false
    css._set_mode(mode)
    return int(host.selection_state.mode) == mode

func commit_fighter(host: Node, player_index: int, fighter_id: String) -> bool:
    var css = host.char_select()
    if css == null:
        return false
    css._on_bay_activated(player_index - 1)
    css._on_tile_pressed(fighter_id)
    return str(host.selection_state.slots[player_index - 1]["character"]) == fighter_id

func wait_css_ready(host: Node, tree: SceneTree) -> bool:
    # The CSS enters under a short input guard; commits are inert until it ends.
    var css = host.char_select()
    if css == null:
        return false
    for i in 120:
        await tree.process_frame
        if css.get_phase() == 1 and css._guard <= 0.0:
            return true
    return false

func configure(host: Node, specs: Array) -> bool:
    # specs: 4 entries; "" = EMPTY station, otherwise the fighter id to commit.
    # P1 stays Human, P2..P4 stay CPUs — the shipped fresh VS station kinds.
    var ok := true
    for i in specs.size():
        var id := str(specs[i])
        if id == "":
            ok = set_kind(host, i + 1, "empty") and ok
        else:
            ok = set_kind(host, i + 1, "human" if i == 0 else "bot") and ok
            ok = commit_fighter(host, i + 1, id) and ok
    return ok

# --- route ------------------------------------------------------------------

func ready(host: Node, tree: SceneTree) -> bool:
    # READY through the band's own activation path; the host re-validates the
    # state through the ONE authority and PUSHes Stage Select.
    var css = host.char_select()
    if css == null:
        return false
    css._on_ready_pressed()
    for i in 240:
        await tree.process_frame
        if host.active_surface() == "sss":
            return true
    return false

func confirm_stage(host: Node, stage_id: String, tree: SceneTree) -> Node:
    # Stage Select owns the stage; its confirm LAUNCHes through the §6 handshake.
    # The screen is inert while its entry choreography and input lock run, so the
    # confirm is issued from the settled state and retried if it did not take.
    var sss = host.stage_select()
    if sss == null:
        return null
    var index: int = sss._index_of(stage_id)
    if index < 0:
        return null
    for attempt in 3:
        for i in 240:
            await tree.process_frame
            if sss._phase != 1 or sss._lock > 0.0:
                continue
            sss.hover_slot(index)
            if sss.get_hovered_id() == stage_id:
                break
        await tree.process_frame
        sss.confirm()
        for i in 20:
            await tree.process_frame
            if host.pending_launch_config() != null or host.launch_state() != "idle":
                break
        if host.pending_launch_config() != null or host.launch_state() != "idle":
            break
    var arena: Node = host.gameplay_node()
    for i in 300:
        await tree.process_frame
        if arena != null and is_instance_valid(arena) and not arena.fighters.is_empty() and not is_instance_valid(host):
            return arena
    return arena

func launch(tree: SceneTree, host: Node, specs: Array, stage_id: String) -> Node:
    # Full production route: configure -> READY -> SSS -> confirm -> gameplay.
    if not await wait_css_ready(host, tree):
        return null
    if not configure(host, specs):
        return null
    if not await ready(host, tree):
        return null
    return await confirm_stage(host, stage_id, tree)

func resolve(tree: SceneTree, arena: Node, survivors: Array) -> void:
    # Resolves the match through the production elimination signal, leaving only
    # `survivors` (player_index values) standing.
    if arena == null or not is_instance_valid(arena):
        return
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    for fighter in arena.fighters:
        if int(fighter.player_index) in survivors:
            continue
        fighter.stocks = 0
        arena._on_fighter_eliminated(fighter)
    await settle(tree, 4)

# --- waits ------------------------------------------------------------------

func host_ids(tree: SceneTree) -> Array:
    # Instance ids of the hosts already mounted; a post-match RETURN must
    # produce a host that is NOT one of them (a launched host is freed, and an
    # id can be reused).
    var out: Array = []
    for child in tree.root.get_children():
        if child.has_method("entry_mode"):
            out.append(child.get_instance_id())
    return out

func wait_for_new_host(tree: SceneTree, previous: Array) -> Node:
    for i in 300:
        await tree.process_frame
        for child in tree.root.get_children():
            if not child.has_method("entry_mode"):
                continue
            if not (child.get_instance_id() in previous):
                return child
    return null

func wait_for_post_match(tree: SceneTree, previous_id: int = 0) -> Node:
    # Waits for a MatchFlow host presenting the PostMatch surface (the RETURN
    # destination of a completed match).
    for i in 300:
        await tree.process_frame
        for child in tree.root.get_children():
            if not child.has_method("active_surface"):
                continue
            if previous_id != 0 and child.get_instance_id() == previous_id:
                continue
            if child.active_surface() == "postmatch":
                return child
    return null

func wait_for_flow(tree: SceneTree, previous_id: int = 0) -> Node:
    # A MatchFlow host — optionally a NEW one (post-match RETURN).
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

func wait_for_scene(tree: SceneTree, scene_name: String) -> Node:
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

func free_arenas(tree: SceneTree) -> void:
    # Test hygiene: a manually mounted/left-behind gameplay arena would keep
    # participating in later parts; free every root arena.
    for child in tree.root.get_children():
        if child is Node3D and str(child.name).begins_with("MainArena"):
            child.queue_free()
        elif child.has_method("start_match_from_config") and not child.has_method("entry_mode"):
            child.queue_free()
    await settle(tree, 3)

func free_hosts(tree: SceneTree) -> void:
    # Test hygiene: a manually mounted host is not the current scene, so the
    # route's own scene change cannot free it.
    for child in tree.root.get_children():
        if child.has_method("entry_mode"):
            child.queue_free()
    await settle(tree, 3)

func settle(tree: SceneTree, frames: int) -> void:
    for i in frames:
        await tree.process_frame

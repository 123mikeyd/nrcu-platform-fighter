extends SceneTree
# WP-0 GATE — Doc 09 "WP-0 ... Gate" end-to-end through public entry points
# (Doc 02 §1 boundary, §5 router verbs, §6 destination readiness, §9 debug
# isolation; Doc 02 §10 steps 7-8).
#
# The four Doc 09 gate assertions:
#   (a) Main -> CSS/Story has no black gap;
#   (b) gameplay does not exist while merely configuring;
#   (c) a completed match is torn down BEFORE CSS/SSS post-match configuration;
#   (d) route returns restore fully visible screens.
#
# Evidence class: PUBLIC_INPUT_ACCEPTANCE for the entries (the Main rows' own
# activation path) and ROUTE_CONTRACT for the router/handshake state that IS the
# subject under test here (frontend_present until presentation_ready +
# exit_finished, presented-surface alpha, teardown ordering).
const Tokens = preload("res://scripts/ui_tokens.gd")

var failures := 0
var vs                      # tests/fixtures/vs_route.gd helper
var story                   # tests/fixtures/story_route.gd helper
# Frames where the presented frontend surface(s) were not visible above alpha 0
# (a "black gap" would show up here).
var presented_violations: Array = []
# Frames where the §6 handshake released the frontend before the destination was
# ready / before the exit completed.
var handshake_violations: Array = []

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func run() -> void:
    root.size = Vector2i(1280, 720)
    vs = load("res://tests/fixtures/vs_route.gd").new()
    story = load("res://tests/fixtures/story_route.gd").new()
    await part_a_main_to_css_and_story_no_black_gap()
    await part_b_no_gameplay_while_configuring()
    await part_c_teardown_before_post_match_configuration()
    await part_d_returns_restore_visible_screens()
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: WP-0 gate (no black gap on Main -> CSS/Story, no gameplay while configuring, teardown before post-match configuration, returns restore visible screens)")
    quit(0)

# --- shared evidence helpers ------------------------------------------------

func sample_presented(host: Node, count: int) -> void:
    # (a) "the previous frame's surface stays presented": in every sampled frame
    # at least one frontend surface is presented AND visible above alpha zero —
    # never a frame whose only visible thing is an alpha-zero/bare backdrop.
    for i in count:
        await process_frame
        if host == null or not is_instance_valid(host):
            return
        var presented: Array = host.presented_surfaces()
        if presented.is_empty():
            presented_violations.append("no surface presented at frame %d" % i)
            continue
        var best := 0.0
        var visible := false
        for name in presented:
            var alpha: float = host.surface_root_alpha(str(name))
            best = maxf(best, alpha)
            var root_node: Control = host.surface_root(str(name))
            if root_node != null and root_node.is_visible_in_tree() and alpha > 0.0:
                visible = true
        if best <= 0.001 or not visible:
            presented_violations.append("only alpha-zero/bare surfaces presented at frame %d" % i)

func backdrop_authored(host: Node) -> bool:
    var backdrop := host.get_node_or_null("Backdrop") as Panel
    if backdrop == null:
        return false
    var box := backdrop.get_theme_stylebox("panel") as StyleBoxFlat
    if box == null:
        return false
    # The authored dark field: never pure black, and the documented BASE token.
    return box.bg_color.is_equal_approx(Tokens.BASE) and box.bg_color.get_luminance() > 0.0

func gameplay_absent() -> bool:
    # (b) no gameplay exists: no arena node mounted, no main.gd instance in the
    # tree, and main.tscn is not the current scene.
    for child in root.get_children():
        if str(child.name).begins_with("MainArena"):
            return false
        if child.has_method("start_match_from_config") and not child.has_method("entry_mode"):
            return false
    if current_scene != null and str(current_scene.scene_file_path).find("main.tscn") != -1:
        return false
    return true

func enter_from_main(row_index: int) -> Node:
    # Public entry: the Main Menu row's own activation path.
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    await frames(45)
    var rows: Array = home.menu_rows()
    if rows.size() != 4:
        home.queue_free()
        return null
    rows[row_index].get_node("HitArea").pressed.emit()
    var host: Node = await vs.wait_for_flow(self)
    if is_instance_valid(home):
        home.queue_free()
    return host

# ---------------------------------------------------------------------------
# (a) Main -> CSS and Main -> Story have no black gap
# ---------------------------------------------------------------------------
func part_a_main_to_css_and_story_no_black_gap() -> void:
    print("--- gate (a): Main -> CSS/Story, no black gap ---")
    var host = await enter_from_main(0)
    check(host != null, "PLAY reaches the MatchFlow host")
    if host != null:
        await sample_presented(host, 20)
        check(presented_violations.is_empty(),
            "Main -> CSS never shows an alpha-zero/bare frame (%s)" % " | ".join(presented_violations))
        check(host.active_surface() == "css" and host.is_surface_presented("css"),
            "the CSS is the presented surface on entry")
        check(host.surface_root_alpha("css") > 0.0, "the CSS root enters above alpha 0")
        var css_root: Control = host.surface_root("css")
        check(css_root != null and css_root.is_visible_in_tree(), "the CSS root is visible when entered")
        check(backdrop_authored(host), "the released frame is the authored field, never a bare/black backdrop")
        if is_instance_valid(host):
            host.queue_free()
    await frames(3)

    presented_violations.clear()
    host = await enter_from_main(1)
    check(host != null, "STORY MODE reaches the MatchFlow host")
    if host != null:
        await sample_presented(host, 20)
        check(presented_violations.is_empty(),
            "Main -> Story never shows an alpha-zero/bare frame (%s)" % " | ".join(presented_violations))
        check(host.active_surface() == "story" and host.is_surface_presented("story"),
            "the Story briefing is the presented surface on entry")
        check(host.surface_root_alpha("story") > 0.0, "the Story root enters above alpha 0")
        var story_root: Control = host.surface_root("story")
        check(story_root != null and story_root.is_visible_in_tree(), "the Story root is visible when entered")
        check(backdrop_authored(host), "the Story entry frame is the authored field too")
        if is_instance_valid(host):
            host.queue_free()
    await frames(3)

# ---------------------------------------------------------------------------
# (b) gameplay does not exist while merely configuring
# ---------------------------------------------------------------------------
func part_b_no_gameplay_while_configuring() -> void:
    print("--- gate (b): no gameplay while merely configuring ---")
    var host = await vs.enter(self)
    var violations: Array = []
    for i in 30:
        await process_frame
        if not is_instance_valid(host):
            break
        if not gameplay_absent():
            violations.append("CSS state, frame %d" % i)
    check(violations.is_empty(), "no gameplay exists while configuring the CSS (%s)" % " | ".join(violations))
    check(host.gameplay_node() == null, "the host owns no destination yet")
    var ready: bool = await vs.ready(host, self)
    check(ready, "READY pushes Stage Select (configuration continues)")
    violations.clear()
    for i in 30:
        await process_frame
        if not is_instance_valid(host):
            break
        if not gameplay_absent():
            violations.append("SSS state, frame %d" % i)
    check(violations.is_empty(), "no gameplay exists while configuring the stage (%s)" % " | ".join(violations))
    check(host.gameplay_node() == null, "still no destination while a stage is only being chosen")
    if is_instance_valid(host):
        host.queue_free()
    await frames(3)

    var host2 = await story.enter(self)
    violations.clear()
    for i in 30:
        await process_frame
        if not is_instance_valid(host2):
            break
        if not gameplay_absent():
            violations.append("Story state, frame %d" % i)
    check(violations.is_empty(), "no gameplay exists while the Story briefing is up (%s)" % " | ".join(violations))
    check(host2.gameplay_node() == null, "the Story configuration owns no gameplay")
    if is_instance_valid(host2):
        host2.queue_free()
    await frames(3)

# ---------------------------------------------------------------------------
# (c) a finished match is torn down BEFORE post-match configuration
# ---------------------------------------------------------------------------
func part_c_teardown_before_post_match_configuration() -> void:
    print("--- gate (c): teardown before post-match configuration ---")
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    if not await vs.wait_css_ready(host, self):
        check(false, "the CSS settled for configuration")
        return
    if not vs.configure(host, ["ggb", "ggb", "", ""]):
        check(false, "the CSS accepted the configuration")
        return
    if not await vs.ready(host, self):
        check(false, "READY pushed Stage Select")
        return
    # LAUNCH handshake evidence for (a): the frontend stays presented until
    # presentation_ready + exit_finished, and the destination is prewarmed
    # hidden underneath it.
    var arena: Node = await confirm_stage_with_sampling(host, "sky")
    check(handshake_violations.is_empty(),
        "the frontend stayed presented until ready + exit finished (%s)" % " | ".join(handshake_violations))
    check(arena != null and is_instance_valid(arena), "the confirmed stage launched gameplay")
    if arena == null or not is_instance_valid(arena):
        return
    check(arena.fighters.size() == 2, "the launched match carries the configured roster")

    # --- resolve: the RETURN tears gameplay down before PostMatch is up -----
    await vs.resolve(self, arena, [1])
    var post: Node = await vs.wait_for_flow(self, host_id)
    check(post != null, "the resolved match RETURNs to the MatchFlow host")
    if post == null:
        return
    # Ordering: at the FIRST frame the PostMatch surface is up (and before any
    # input reaches it) the completed arena is already gone.
    check(not is_instance_valid(arena), "gameplay is torn down before PostMatch accepts input")
    check(post.gameplay_node() == null, "the returning host owns no arena")
    check(gameplay_absent(), "no arena node survives behind PostMatch")
    check(post.active_surface() == "postmatch" and post.post_match() != null and post.post_match().visible,
        "PostMatch is up over the immutable payload")

    # --- CHANGE STAGE (Results -> SSS PUSH): still no gameplay --------------
    post.post_match().result_screen.finish_reveal()
    check(post.post_match().is_interactive(), "the Results surface is interactive")
    check(not is_instance_valid(arena), "gameplay is still gone when Results is interactive")
    var change_stage: Button = post.post_match().result_screen.find_child("ChangeStage", true, false)
    check(change_stage != null and change_stage.visible, "Results offers CHANGE STAGE")
    change_stage.pressed.emit()
    var pushed_sss: bool = await vs.wait_for(self, func() -> bool: return post.active_surface() == "sss", 180)
    check(pushed_sss, "CHANGE STAGE PUSHes Stage Select")
    check(gameplay_absent(), "no gameplay exists during post-match stage configuration")
    check(post.route_origin() == "results", "the post-match SSS records the RESULTS origin")

    # --- return to Results: fully visible again (d) -------------------------
    post.stage_select().request_back()
    var restored: bool = await vs.wait_for(self, func() -> bool:
            return post.active_surface() == "postmatch" and post.is_surface_presented("postmatch"), 240)
    check(restored, "the SSS Back POPs back to Results")
    check(post.surface_root_alpha("postmatch") > 0.0, "the restored Results root is above alpha 0")
    check(post.surface_root("postmatch").is_visible_in_tree(), "the restored Results surface is visible")
    check(post.post_match().is_interactive() and not post.post_match().is_revealing(),
        "the restored Results keeps its revealed state")
    check(gameplay_absent(), "still no gameplay during post-match configuration")

    # --- CHANGE FIGHTERS (Results -> CSS PUSH): still no gameplay ----------
    var change_fighters: Button = post.post_match().result_screen.find_child("ChangeFighters", true, false)
    check(change_fighters != null and change_fighters.visible, "Results offers CHANGE FIGHTERS")
    change_fighters.pressed.emit()
    var pushed_css: bool = await vs.wait_for(self, func() -> bool: return post.active_surface() == "css", 180)
    check(pushed_css, "CHANGE FIGHTERS PUSHes the CSS")
    check(gameplay_absent(), "no gameplay exists during post-match fighter configuration")
    check(post.surface_root_alpha("css") > 0.0 and post.surface_root("css").is_visible_in_tree(),
        "the re-entered CSS is fully visible (no alpha-zero return)")
    if is_instance_valid(post):
        post.queue_free()
    await vs.free_arenas(self)
    await frames(3)

# ---------------------------------------------------------------------------
# (d) returns restore fully visible screens
# ---------------------------------------------------------------------------
func part_d_returns_restore_visible_screens() -> void:
    print("--- gate (d): returns restore fully visible screens ---")
    var host = await vs.enter(self)
    if not await vs.wait_css_ready(host, self):
        check(false, "the CSS settled for the return contract")
        return
    if not vs.configure(host, ["ggb", "ggb", "", ""]):
        check(false, "the CSS accepted the configuration")
        return
    if not await vs.ready(host, self):
        check(false, "READY pushed Stage Select")
        return
    var pushed: bool = await vs.wait_for(self, func() -> bool: return host.is_surface_presented("sss"), 240)
    check(pushed, "the CSS -> SSS push settles")
    check(host.surface_root_alpha("sss") > 0.0, "the entering SSS is above alpha 0")
    # POP back to the CSS: the alpha-zero return bug stays fixed.
    host.stage_select().request_back()
    var back: bool = await vs.wait_for(self, func() -> bool: return host.active_surface() == "css" and host.is_surface_presented("css"), 240)
    check(back, "the SSS Back restores the CSS")
    check(host.surface_root_alpha("css") >= 0.99, "the restored CSS root is back at its authored alpha")
    var css_root: Control = host.surface_root("css")
    check(css_root != null and css_root.is_visible_in_tree(), "the restored CSS root is visible")
    if is_instance_valid(host):
        host.queue_free()
    await frames(3)

# ---------------------------------------------------------------------------
# LAUNCH handshake sampling (used by (c) and as the (a) launch-transition
# evidence): the outgoing frontend surface stays presented until the
# destination reported readiness AND its exit finished; the destination is
# prewarmed hidden underneath.
# ---------------------------------------------------------------------------
var _launch_report: Dictionary = {}

func confirm_stage_with_sampling(host: Node, stage_id: String) -> Node:
    var sss = host.stage_select()
    var index: int = sss._index_of(stage_id)
    if index < 0:
        return null
    host.launch_finished.connect(func() -> void: _launch_report = host.handshake_report())
    # Production timeline: the player confirms on a PRESENTED stage page (the
    # push settles after the CSS exit), so wait for the screen to be up first.
    for i in 240:
        await process_frame
        if host.is_surface_presented("sss"):
            break
    for i in 240:
        await process_frame
        if sss._phase == 1 and sss._lock <= 0.0:
            break
    sss.hover_slot(index)
    await frames(2)
    sss.confirm()
    var arena: Node = null
    var sss_up_after_confirm := false
    for i in 300:
        await process_frame
        if not is_instance_valid(host):
            break
        var candidate: Node = host.gameplay_node()
        if candidate != null and is_instance_valid(candidate):
            arena = candidate
        else:
            candidate = null
        if host.launch_state() != "launched":
            # (a) "the previous frame's surface stays presented": until the
            # destination is revealed, at least one frontend surface is still
            # presented — never a bare/alpha-zero frame.
            if host.is_surface_presented("sss"):
                sss_up_after_confirm = true
            if host.presented_surfaces().is_empty():
                handshake_violations.append("no frontend surface presented during the handshake (state %s, frame %d)" % [host.launch_state(), i])
            if candidate != null and candidate.visible:
                handshake_violations.append("destination visible before the launch transition (state %s)" % host.launch_state())
        elif arena != null:
            break
    check(sss_up_after_confirm, "the outgoing Stage Select stayed presented into the handshake")
    for i in 240:
        await process_frame
        if arena != null and is_instance_valid(arena) and not arena.fighters.is_empty() and not is_instance_valid(host):
            break
    check(not _launch_report.is_empty(), "the launch released the frontend")
    if not _launch_report.is_empty():
        check(bool(_launch_report.get("presentation_ready_received", false)),
            "gameplay reported presentation_ready during the handshake")
        check(bool(_launch_report.get("constructed_hidden_while_frontend_up", false)),
            "gameplay was prewarmed hidden while the frontend stayed presented (Doc 02 §6)")
        check(not bool(_launch_report.get("presentation_timed_out", true)),
            "the release waited on the destination's own signal, not the deadline")
        check(bool(_launch_report.get("frontend_released_after_ready", false)),
            "the frontend was released only after readiness")
    return arena

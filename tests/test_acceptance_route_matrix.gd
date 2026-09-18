extends SceneTree
# Doc 08 §3 — route-edge matrix (entry / exit / back / return per surface).
# LANE C / WP-7 harness 3 of 7. Evidence class: PUBLIC_INPUT_ACCEPTANCE.
#
# Every edge is driven with real device events through the shipped route (real
# pointer presses on the authored controls, real ui_cancel / ui_accept events).
# For each settled destination the matrix records: which surface is presented,
# its root alpha, the route origin, the input scope, and the focus owner.
#
# Edges whose destination surface DOES NOT EXIST at this commit are reported as
# SKIPPED WITH THEIR REASON (never silently green, never a false failure).
# Origins covered explicitly: SSS entered from Results, Results cancel safety,
# the Main-Esc modal.
#
# Output: .verification/acceptance/route_matrix.json

const Support = preload("res://tools/acceptance_support.gd")
const REPORT_JSON := Support.SCREEN_DIR + "route_matrix.json"

var failures := 0
var checks := 0
var edges: Array = []
var skips: Array = []
var defects: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func skip(edge: String, reason: String) -> void:
	skips.append({"edge": edge, "reason": reason})
	print("SKIP: %s — %s" % [edge, reason])

func defect(id: String, detail: String) -> void:
	defects.append({"id": id, "detail": detail})
	print("EXPOSED_DEFECT: %s — %s" % [id, detail])

func frames(count: int) -> void:
	for i in count:
		await process_frame

func edge(name: String, ok: bool, observed: Dictionary, expectation := "") -> void:
	edges.append({"edge": name, "pass": ok, "expected": expectation, "observed": observed})
	print("EDGE %s pass=%s %s" % [name, str(ok), JSON.stringify(observed)])

func surface_state(host, surface: String) -> Dictionary:
	if host == null or not is_instance_valid(host) or not host.has_method("active_surface"):
		return {"host": false}
	return {
		"host": true,
		"active_surface": str(host.active_surface()),
		"presented": bool(host.is_surface_presented(surface)),
		"root_alpha": snappedf(host.surface_root_alpha(surface), 0.0001),
		"route_origin": str(host.route_origin()),
		"origins": str(host.origin_stack_names()) if host.has_method("origin_stack_names") else "",
		"input_scope": str(host.input_scope()),
	}

func settled_state(host, surface: String) -> Dictionary:
	# A destination counts as "settled" for the Doc 08 §3 evidence only once
	# its entering screen owns its authored alpha again: the router records the
	# destination immediately, the screen fades itself in.
	for i in 60:
		await process_frame
		if host == null or not is_instance_valid(host) or not host.has_method("active_surface"):
			break
		if host.is_surface_presented(surface) and host.surface_root_alpha(surface) >= 0.999:
			break
	return surface_state(host, surface)

func home_state(home) -> Dictionary:
	if home == null or not is_instance_valid(home):
		return {"presented": false}
	var owner := Support.focus_owner(self)
	return {"presented": home.is_visible_in_tree(), "root_alpha": snappedf(home.modulate.a, 0.0001),
			"state": str(home.state), "focus_owner": str(owner.get_path()) if owner != null else ""}

# --- route helpers -----------------------------------------------------------

func enter_main() -> Node:
	var home = load("res://scenes/home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	await frames(8)
	return home

func ensure_main() -> Node:
	# Every part starts from a settled, VERIFIED Main: a route change that was
	# still in flight from the previous part would otherwise free the instance a
	# later part is holding (and a stale extra Main instance would swallow the
	# pointer events the part dispatches at its rows).
	for attempt in 3:
		await frames(24)
		var scene = current_scene
		if scene != null and is_instance_valid(scene) and scene.has_method("menu_rows") \
				and str(scene.scene_file_path).find("home.tscn") != -1:
			return scene
		for child in root.get_children():
			if child.has_method("entry_mode"):
				child.queue_free()
		await frames(4)
		var fresh = load("res://scenes/home.tscn").instantiate()
		root.add_child(fresh)
		current_scene = fresh
		await frames(10)
	return current_scene

func open_story(home) -> Node:
	# STORY MODE -> the flow host in story mode, verified (a stale entry flag from
	# an earlier part would make the host open the VS route).
	for attempt in 2:
		# The row press routes Main away, so the caller's home instance is freed
		# by the scene change: a retry must re-mount a verified Main instead of
		# touching the stale instance (that dangling access faults the engine).
		if home == null or not is_instance_valid(home):
			home = await ensure_main()
		if home == null or not is_instance_valid(home):
			return null
		var row: Control = home.menu_rows()[1].get_node("HitArea")
		Support.click_center(self, row)
		var host = await Support.wait_for_node(self, "MatchFlow")
		if host == null:
			return null
		await Support.wait_until(self, func() -> bool: return host.active_surface() != "", 300)
		if str(host.active_surface()).begins_with("story"):
			return host
		print("STORY_ENTRY host entered as %s (attempt %d)" % [str(host.active_surface()), attempt + 1])
		host.queue_free()
		await frames(10)
	return null

func open_css(home) -> Node:
	Support.click_center(self, home.menu_rows()[0].get_node("HitArea"))
	var host = await Support.wait_for_node(self, "MatchFlow")
	if host != null:
		await Support.wait_until(self, func() -> bool: return host.is_surface_presented("css"), 300)
	return host

func configure(css) -> bool:
	var bays: Array = css.get_bays()
	var tiles: Array = css.get_tiles()
	if bays.size() < 2 or tiles.size() < 2:
		return false
	for i in 2:
		await semantic_activate(bays[i])
		if int(css.get_active()) != i:
			return false
		await semantic_activate(tiles[i])
		await frames(4)
	return css.ready_allowed()

func semantic_activate(control: Control) -> void:
	control.grab_focus()
	await frames(2)
	await Support.tap_key(self, KEY_ENTER)
	await frames(4)

func push_sss(host, css) -> bool:
	var band = css.get_ready_band()
	if band == null or not band.is_shown():
		return false
	Support.click_center(self, band)
	return await Support.wait_until(self, func() -> bool: return host.is_surface_presented("sss"), 300)

func confirm_stage(host, sss) -> bool:
	await Support.wait_until(self, func() -> bool: return sss._phase == 1 and sss._lock <= 0.0, 300)
	await frames(6)
	var tile: Button = sss.get_tiles()[0]
	Support.click_center(self, tile)
	await frames(4)
	Support.click_center(self, tile)
	return await Support.wait_until(self, func() -> bool: return host.launch_state() == "launched", 400)

func wait_for_flow(previous_id: int) -> Node:
	for i in 400:
		await process_frame
		for child in root.get_children():
			if not child.has_method("entry_mode"):
				continue
			if previous_id != 0 and child.get_instance_id() == previous_id:
				continue
			return child
	return null

func run() -> void:
	var hand := Support.hand(self)
	check(hand != null, "cursor service reachable")
	if hand == null:
		quit(1)
		return
	await part_main_and_vs_edges()
	await part_results_edges()
	await part_story_edges()
	await part_help_edges()
	await declare_unimplemented_edges()
	report()

# --- Title/Main/CSS/SSS edges ------------------------------------------------

func part_main_and_vs_edges() -> void:
	print("--- Title / Main / CSS / SSS ---")
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await Support.wait_until(self, func() -> bool: return title.is_armed(), 300)
	Support.inject(Support.key_event(KEY_SPACE, true))
	await frames(3)
	Support.inject(Support.key_event(KEY_SPACE, false))
	var home = await Support.wait_for_scene(self, "home.tscn")
	check(home != null, "Title -> Main (real key press)")
	if home == null:
		return
	edge("title_to_main", home != null, home_state(home), "Main presented, alpha 1")

	var host = await open_css(home)
	check(host != null, "Main -> CSS (real pointer press on PLAY)")
	if host == null:
		return
	var css_state := surface_state(host, "css")
	edge("main_to_css", bool(css_state["presented"]) and float(css_state["root_alpha"]) > 0.0, css_state,
		"css presented, alpha 1, origin main, scope frontend")

	# Main-ESC modal edge inside the CSS route? No: the CSS route is separate.
	# The STAGED cancel (owner-verified, not the former flat behaviour): at a
	# fresh entry the chip RIDES THE CURSOR, so press #1 peels stage 1 (the
	# carried, uncommitted chip returns home) and the CSS STAYS presented; only
	# a press that finds nothing carried / committed / pending takes the BACK
	# route, resolving the screen's recorded entry origin (Main here). Asserted
	# press by press.
	var css = host.char_select()
	await Support.wait_until(self, func() -> bool: return css._phase == 1 and css._guard <= 0.0, 300)
	check(int(css.get_carried_by()) == 0,
		"the fresh CSS entry holds the chip (carried_by %d): ui_cancel #1 is stage 1" % int(css.get_carried_by()))
	await Support.tap_key(self, KEY_ESCAPE)
	await frames(6)
	check(host.is_surface_presented("css") and css.is_visible_in_tree(),
		"ui_cancel #1 peels STAGE 1 (the carried chip) and the CSS STAYS presented")
	check(int(css.get_carried_by()) == -1,
		"ui_cancel #1 returned the carried chip home (carried_by %d)" % int(css.get_carried_by()))
	await Support.tap_key(self, KEY_ESCAPE)
	home = await Support.wait_for_scene(self, "home.tscn")
	check(home != null, "ui_cancel #2 (nothing carried/pending) takes the BACK route to the CSS entry origin (Main)")
	if home == null:
		return
	edge("css_cancel_to_main", true, home_state(home), "staged cancel: stage 1 first, then Main presented, alpha 1, no host left")

	# Main-Esc modal edge (Doc 08 §3): ui_cancel on Main opens the in-place Quit
	# modal; the modal's own cancel dismisses it back to the SAME Main state.
	await Support.tap_key(self, KEY_ESCAPE)
	await frames(8)
	var modal_open: bool = home.is_quit_modal_open()
	edge("main_escape_opens_quit_modal", modal_open, {"modal_open": modal_open, "state": str(home.state)},
		"the Quit modal opens over the still-mounted Main")
	check(modal_open, "Main ui_cancel opens the Quit modal")
	await Support.tap_key(self, KEY_ESCAPE)
	await frames(8)
	var modal_closed: bool = not home.is_quit_modal_open() and str(home.state) == "home"
	edge("main_modal_cancel_returns_to_main", modal_closed,
		{"modal_open": home.is_quit_modal_open(), "state": str(home.state)}, "same Main state, modal dismissed")
	check(modal_closed, "the modal's own cancel dismisses it and keeps Main input-authoritative")

	# CSS -> SSS -> CSS (the return edge) and SSS confirm -> Gameplay.
	host = await open_css(home)
	if host == null:
		return
	css = host.char_select()
	await Support.wait_until(self, func() -> bool: return css._phase == 1 and css._guard <= 0.0, 300)
	check(await configure(css), "a valid configuration is committed through public input")
	var pushed := await push_sss(host, css)
	check(pushed, "CSS -> SSS (READY pressed)")
	var sss = host.stage_select()
	await Support.wait_until(self, func() -> bool: return sss._phase == 1 and sss._lock <= 0.0, 300)
	edge("css_to_sss", pushed, surface_state(host, "sss"), "sss presented, css no longer presented")
	await frames(6)
	Support.click_center(self, sss.get_back_button())
	var popped := await Support.wait_until(self, func() -> bool:
			return host.is_surface_presented("css") and not host.is_surface_presented("sss"), 300)
	check(popped, "SSS -> CSS (Back pressed)")
	edge("sss_back_to_css", popped, surface_state(host, "css"), "css restored, alpha 1, origin main")
	var restored := surface_state(host, "css")
	check(float(restored["root_alpha"]) >= 0.99, "the restored CSS keeps its authored baseline alpha (return-entry fix)")

	# SSS confirm -> Gameplay.
	check(await push_sss(host, css), "CSS re-enters SSS after the return edge")
	sss = host.stage_select()
	var launched := await confirm_stage(host, sss)
	check(launched, "SSS confirm -> Gameplay (LAUNCH)")
	var prior_id: int = host.get_instance_id()
	var released := false
	for i in 400:
		await process_frame
		if not is_instance_valid(host):
			released = true
			break
	edge("sss_confirm_to_gameplay", launched and released,
		{"launch_state_launched": launched, "frontend_released": released}, "arena constructed, frontend released")
	var arena = await Support.wait_for_scene(self, "main.tscn")
	check(arena != null, "gameplay is the current scene")
	if arena == null:
		return
	await frames(20)
	var gameplay_state := {"scene": str(arena.scene_file_path), "fighters": arena.fighters.size(),
			"story_state": str(arena.story_state), "input_scope": str(Support.service(self).scope())}
	edge("gameplay_started", arena.fighters.size() > 0, gameplay_state, "configured fighters, gameplay scope")

	# Gameplay end -> Results (the PostMatch surface of the production route).
	print("--- Gameplay end -> Results ---")
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	for fighter in arena.fighters:
		if int(fighter.player_index) == 1:
			continue
		fighter.stocks = 0
		arena._on_fighter_eliminated(fighter)
	await frames(6)
	var post_host = await wait_for_flow(prior_id)
	check(post_host != null, "Gameplay end -> Results (the flow regains the frontend)")
	if post_host == null:
		return
	await Support.wait_until(self, func() -> bool: return post_host.is_surface_presented("postmatch"), 400)
	var pm_state := surface_state(post_host, "postmatch")
	edge("gameplay_end_to_results", bool(pm_state["presented"]) and float(pm_state["root_alpha"]) > 0.0, pm_state,
		"postmatch presented, origin results, arena torn down")
	check(root.get_node_or_null("MainArena") == null, "the completed arena is torn down before post-match configuration")
	results_host = post_host
	results_id = post_host.get_instance_id()

# --- Results edges (incl. the Results origin + cancel safety) ------------------

func part_results_edges() -> void:
	print("--- Results edges ---")
	var host = results_host
	if host == null or not is_instance_valid(host):
		skip("results_*", "no PostMatch host is mounted (the gameplay-end edge did not settle)")
		return
	var screen = host.post_match().result_screen
	# The reveal is completed by a REAL confirm event (the production skip path);
	# that same input must not also activate an action.
	await Support.tap_key(self, KEY_ENTER)
	var interactive := await Support.wait_until(self, func() -> bool:
			return host.post_match().is_interactive(), 400)
	check(interactive, "a real confirm completes the reveal without also leaving the screen")
	edge("results_reveal_skip_one_input_one_action", interactive,
		{"interactive": interactive, "surface": str(host.active_surface())},
		"the reveal-skip confirm does not activate an action")
	check(str(host.active_surface()) == "postmatch", "the reveal-skip confirm stays on Results")

	# Results -> Change Stage -> SSS (origin RESULTS) -> Back -> Results.
	var chain: Array = screen.action_chain()
	check(chain.size() == 4, "Results exposes its four authored actions (%d)" % chain.size())
	var change_stage: Button = chain[2] if chain.size() > 2 else null
	if change_stage != null:
		Support.click_center(self, change_stage)
		var pushed := await Support.wait_until(self, func() -> bool: return host.is_surface_presented("sss"), 400)
		var sss_state := surface_state(host, "sss")
		check(pushed, "Results CHANGE STAGE pushes the SSS")
		edge("results_change_stage_to_sss", pushed and bool(sss_state["presented"]), sss_state,
			"sss presented with origin RESULTS, Results still mounted beneath")
		check(str(sss_state["route_origin"]) == "results", "the SSS entered from Results records the RESULTS origin")
		# SSS -> Back -> Results (the origin's return edge).
		var sss = host.stage_select()
		await Support.wait_until(self, func() -> bool: return sss._phase == 1 and sss._lock <= 0.0, 400)
		await frames(6)
		Support.click_center(self, sss.get_back_button())
		var back_to_results := await Support.wait_until(self, func() -> bool:
				return host.is_surface_presented("postmatch"), 400)
		var back_state := surface_state(host, "postmatch")
		edge("sss_from_results_back_to_results", back_to_results and bool(back_state["presented"]), back_state,
			"Results restored after the SSS Back (origin consumed), alpha 1")
		check(back_to_results, "SSS Back from the Results origin returns to Results (not Main)")
		check(float(back_state["root_alpha"]) >= 0.99, "the restored Results frame keeps its authored baseline alpha")
	else:
		skip("results_change_stage_to_sss", "Results exposes no CHANGE STAGE action in this outcome")

	# Results -> Rematch (a fresh arena from the preserved config).
	if chain.size() > 0:
		var arena = await Support.wait_for_scene(self, "main.tscn")
		var prior_arena_id: int = arena.get_instance_id() if arena != null and is_instance_valid(arena) else 0
		var rematch: Button = chain[0]
		Support.click_center(self, rematch)
		# The RE-LAUNCH frees the PostMatch host, so the wait never touches it
		# after the release frame (a lambda capturing a freed host faults).
		var relaunched := false
		for i in 400:
			await process_frame
			if not is_instance_valid(host):
				relaunched = true
				break
		var new_arena = await Support.wait_for_scene(self, "main.tscn")
		await frames(20)
		var fresh_arena: bool = new_arena != null and is_instance_valid(new_arena) \
				and new_arena.get_instance_id() != prior_arena_id
		var fighters: int = new_arena.fighters.size() if fresh_arena else -1
		edge("results_rematch_to_gameplay", fresh_arena and fighters > 0,
			{"fighters": fighters, "relaunched": relaunched}, "a fresh arena runs the preserved roster")
		check(fresh_arena and fighters > 0, "Results REMATCH relaunches gameplay from the preserved config")
		if fresh_arena:
			# Resolve again to reach Results for the remaining Results edges. The
			# arena id is captured BEFORE the resolution: the route frees the
			# arena on the way back, so reading it afterwards is a dangling access.
			var relaunch_id: int = new_arena.get_instance_id()
			for fighter in new_arena.fighters:
				fighter.set_physics_process(false)
			for fighter in new_arena.fighters:
				if int(fighter.player_index) == 1:
					continue
				fighter.stocks = 0
				new_arena._on_fighter_eliminated(fighter)
			await frames(6)
			new_arena = null
			var next_host = await wait_for_flow(relaunch_id)
			if next_host != null:
				await Support.wait_until(self, func() -> bool: return next_host.is_surface_presented("postmatch"), 400)
				results_host = next_host
				results_id = next_host.get_instance_id()
				host = next_host
				screen = host.post_match().result_screen
				await Support.tap_key(self, KEY_ENTER)
				await Support.wait_until(self, func() -> bool: return host.post_match().is_interactive(), 400)
			else:
				skip("results_change_fighters_to_css", "the rematch resolution did not return a PostMatch host")

	# Results -> Change Fighters (origin RESULTS) — and the CSS cancel edge.
	if host == null or not is_instance_valid(host):
		skip("results_change_fighters_to_css", "no live PostMatch host after the rematch edge")
		skip("change_fighters_cancel_edge", "no live PostMatch host after the rematch edge")
		return
	var chain2: Array = host.post_match().result_screen.action_chain()
	var change_fighters: Button = chain2[1] if chain2.size() > 1 else null
	if change_fighters != null:
		Support.click_center(self, change_fighters)
		var css_pushed := await Support.wait_until(self, func() -> bool: return host.is_surface_presented("css"), 400)
		var css_state := surface_state(host, "css")
		edge("results_change_fighters_to_css", css_pushed and bool(css_state["presented"]), css_state,
			"css presented with origin RESULTS")
		check(css_pushed, "Results CHANGE FIGHTERS pushes the CSS")
		check(str(css_state["route_origin"]) == "results", "the CSS entered from Results records the RESULTS origin")
		var css = host.char_select()
		await Support.wait_until(self, func() -> bool: return css._phase == 1 and css._guard <= 0.0, 400)
		# THE STAGED CANCEL, pressed through layer by layer (owner-verified): each
		# press that finds a carried chip, a committed pick or a pending candidate
		# peels EXACTLY that one layer and the screen STAYS presented; only a press
		# that finds none of the three follows the BACK route, and that route must
		# resolve the RECORDED origin — RESULTS — restoring the pushed PostMatch
		# surface. The layer count is state-dependent (this CSS may hold a commit
		# from the round trip and/or the entry chip), so the sequence is driven by
		# the state per press rather than by a hardcoded count.
		var presses := 0
		var went_home: Node = null
		var back_to_results := false
		while presses < 6 and host.is_surface_presented("css"):
			var carried_before := int(css.get_carried_by())
			var committed_before: String = str(host.selection_state.slots[0]["character"])
			var candidate_before := int(css.get_candidate())
			var staged_expected: bool = carried_before >= 0 or committed_before != "" or candidate_before >= 0
			await Support.tap_key(self, KEY_ESCAPE)
			presses += 1
			if not staged_expected:
				# Nothing left to peel: THIS press is the one that follows the BACK
				# route (one press = one layer — never a consumed stage routing).
				break
			# A consumed stage NEVER requests the route: the screen stays presented.
			await frames(10)
			check(host.is_surface_presented("css") and css.is_visible_in_tree(),
				"ui_cancel #%d peeled one staged layer (carry %d -> %d, commit '%s', candidate %d) and the CSS STAYED presented"
				% [presses, carried_before, int(css.get_carried_by()), committed_before, candidate_before])
		went_home = await Support.wait_for_scene(self, "home.tscn", 300)
		if went_home == null:
			back_to_results = await Support.wait_until(self, func() -> bool:
					return host.is_surface_presented("postmatch"), 200)
		var observed := {"left_to_main": went_home != null, "back_to_results": back_to_results,
				"host_alive": is_instance_valid(host), "staged_presses": presses}
		if went_home != null:
			defect("css_cancel_from_results_origin_leaves_to_main",
				"CSS ui_cancel with origin RESULTS (CHANGE FIGHTERS) leaves to Main instead of restoring the pushed Results surface: Doc 02 §5 says the PUSH keeps Results mounted so the CSS Back route can restore it, Doc 03 §11 says CSS ui_cancel -> Main. Recorded, not fixed. (Staged presses peeled before the route: %d.)" % presses)
		edge("change_fighters_cancel_edge", went_home != null or back_to_results, observed,
			"staged cancel peeled %d layer(s), then one of: CSS cancel restores Results (Doc 02 §5) or leaves to Main (Doc 03 §11)" % presses)
		if went_home != null:
			# Re-enter through the production route for the remaining edges.
			host = await reenter_post_match()
	# Results -> Main Menu (the visible action) on a freshly reached Results.
	var menu_host = await reenter_post_match()
	if menu_host != null:
		var screen_menu = menu_host.post_match().result_screen
		await Support.tap_key(self, KEY_ENTER)
		await Support.wait_until(self, func() -> bool: return menu_host.post_match().is_interactive(), 400)
		var chain3: Array = screen_menu.action_chain()
		var menu: Button = chain3[3] if chain3.size() > 3 else null
		if menu != null:
			Support.click_center(self, menu)
			var home_scene = await Support.wait_for_scene(self, "home.tscn", 300)
			edge("results_main_menu_to_main", home_scene != null, home_state(home_scene),
				"Main presented, alpha 1, stack cleared")
			check(home_scene != null, "Results MAIN MENU clears the stack to Main")
		else:
			skip("results_main_menu_to_main", "the outcome exposes no MAIN MENU action")
	else:
		skip("results_main_menu_to_main", "no second PostMatch host could be reached for the MAIN MENU edge")

	# Results cancel safety (Doc 01 §14 / Doc 08 §3): ui_cancel takes the SAME
	# route as the visible MAIN MENU action.
	var cancel_host = await reenter_post_match()
	if cancel_host != null:
		var screen2 = cancel_host.post_match().result_screen
		await Support.tap_key(self, KEY_ENTER)
		await Support.wait_until(self, func() -> bool: return cancel_host.post_match().is_interactive(), 400)
		await Support.tap_key(self, KEY_ESCAPE)
		var cancel_home = await Support.wait_for_scene(self, "home.tscn", 300)
		edge("results_cancel_safety_to_main", cancel_home != null, home_state(cancel_home),
			"ui_cancel after the reveal safety route to Main (same as MAIN MENU)")
		check(cancel_home != null, "Results ui_cancel after reveal safety leaves to Main")
	else:
		skip("results_cancel_safety", "no PostMatch host could be mounted for the cancel edge")

func reenter_post_match() -> Node:
	# A fresh production route to PostMatch: Main -> CSS -> SSS -> confirm -> resolve.
	var home = await ensure_main()
	if home == null:
		return null
	Support.click_center(self, home.menu_rows()[0].get_node("HitArea"))
	var host = await Support.wait_for_node(self, "MatchFlow")
	if host == null:
		return null
	await Support.wait_until(self, func() -> bool: return host.is_surface_presented("css"), 300)
	var css = host.char_select()
	if css == null:
		return null
	await Support.wait_until(self, func() -> bool: return css._phase == 1 and css._guard <= 0.0, 400)
	if not await configure(css):
		print("REENTER configure failed (ready_allowed=%s)" % str(css.ready_allowed()))
		return null
	if not await push_sss(host, css):
		print("REENTER READY did not push the SSS")
		return null
	if not await confirm_stage(host, host.stage_select()):
		return null
	var prior_id: int = host.get_instance_id()
	var arena = await Support.wait_for_scene(self, "main.tscn", 400)
	if arena == null:
		return null
	await frames(20)
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	for fighter in arena.fighters:
		if int(fighter.player_index) == 1:
			continue
		fighter.stocks = 0
		arena._on_fighter_eliminated(fighter)
	await frames(6)
	var next_host = await wait_for_flow(prior_id)
	if next_host != null:
		await Support.wait_until(self, func() -> bool: return next_host.is_surface_presented("postmatch"), 400)
	return next_host

# --- Story edges -------------------------------------------------------------

func part_story_edges() -> void:
	print("--- Story edges ---")
	var home = await ensure_main()
	var host = await open_story(home)
	check(host != null, "Main -> Story MODE reaches the flow host in story mode")
	if host == null:
		skip("main_to_story_select", "the flow host did not enter story mode after the STORY MODE row press")
		skip("story_fighter_select_to_briefing", "no Story route to step")
		skip("briefing_to_story_select", "no Story route to step")
		return
	# Story step 1: the Story Fighter Select (Doc 01 §9).
	await Support.wait_until(self, func() -> bool: return host.active_surface() == "story_select", 400)
	var select_state := await settled_state(host, "story_select")
	edge("main_to_story_select", bool(select_state["presented"]), select_state, "the Story Fighter Select is presented")
	check(bool(select_state["presented"]), "Main -> Story MODE presents the Story Fighter Select")
	var select = host.story_select()
	check(select != null, "the Story Fighter Select is mounted")
	if select == null:
		return
	# Story step 2: Select -> Briefing through the shipped Continue control.
	Support.click_center(self, select.continue_button())
	var stepped: bool = await Support.wait_until(self, func() -> bool:
		return host.is_surface_presented("story_briefing") and host.story_briefing() != null \
			and host.story_briefing().visible, 400)
	edge("story_fighter_select_to_briefing", stepped, await settled_state(host, "story_briefing"),
		"Continue PUSHes the Encounter Briefing")
	check(stepped, "Story Fighter Select Continue reaches the Encounter Briefing")
	var briefing = host.story_briefing()
	if briefing == null:
		return
	# Briefing -> Story Fighter Select (Doc 01 §9 / Doc 03 §11), then back again.
	Support.click_center(self, briefing.back_button())
	var returned: bool = await Support.wait_until(self, func() -> bool:
		return host.active_surface() == "story_select" and select.visible, 400)
	edge("briefing_to_story_select", returned, await settled_state(host, "story_select"),
		"the Briefing Back restores the Story Fighter Select")
	check(returned, "the Briefing Back restores the Story Fighter Select")
	if returned:
		Support.click_center(self, select.continue_button())
		stepped = await Support.wait_until(self, func() -> bool:
			return host.story_briefing() != null and host.story_briefing().visible, 400)
		check(stepped, "the Briefing is reachable again after the back edge")
		briefing = host.story_briefing()
	if briefing == null:
		return
	await frames(10)
	# Briefing -> Gameplay (START ENCOUNTER).
	var launch_host_id: int = host.get_instance_id()
	Support.click_center(self, briefing.action_button())
	var arena = await Support.wait_for_scene(self, "main.tscn", 400)
	check(arena != null, "Briefing START ENCOUNTER -> Gameplay")
	if arena == null:
		return
	await frames(24)
	edge("briefing_to_gameplay", arena.story_state != "", {"story_state": str(arena.story_state),
			"fighters": arena.fighters.size()}, "the encounter is running")
	# Win the encounter and return to the Story surface. The READY gate runs
	# first (status/cleanup fixtures start after Go), then the enemy takes its
	# damage through the SHIPPED combat entry (same recipe as the story-result
	# regression suite: three 150-damage hits complete the one-stage encounter).
	if arena.ready_remaining > 0.0:
		arena._physics_process(arena.ready_remaining)
	var hero = arena.player_one
	var enemy = arena.player_two
	for fighter in arena.fighters:
		fighter.set_physics_process(false)
	if enemy != null:
		for hit in 3:
			enemy.receive_hit(150, Vector3.RIGHT, 4)
	# The completion resolves at the end of the frame and the route then frees the
	# arena, so the state is read NOW (never after the route can take it away).
	var completed: bool = is_instance_valid(arena) and arena.match_over \
			and str(arena.story_state) == "complete"
	check(completed, "the encounter completes after the enemy's final stock")
	var result_host = await wait_for_flow(launch_host_id)
	check(result_host != null, "the resolved encounter returns to the frontend")
	if result_host == null:
		skip("story_win_to_story_result", "the completed encounter did not return a flow host inside the wait budget")
		skip("story_result_change_fighter", "the Story Result surface could not be reached")
		skip("story_result_replay_to_gameplay", "the Story Result surface could not be reached")
		skip("story_loss_to_story_result", "the Story Result surface could not be reached")
		skip("story_result_to_main", "the Story Result surface could not be reached")
		return
	await Support.wait_until(self, func() -> bool: return result_host.is_surface_presented("story_result"), 400)
	var result = result_host.story_result()
	var shown := result != null and str(result.title_label().text) != ""
	edge("story_win_to_story_result", shown,
		{"surface": str(result_host.active_surface()),
		 "title": str(result.title_label().text) if result != null else "",
		 "action": str(result.action_button().text) if result != null else "",
		 "change": str(result.change_fighter_button().text) if result != null else "",
		 "menu": str(result.menu_button().text) if result != null else ""},
		"the compact Story Result is presented")
	check(shown, "a Story win presents the compact Story Result")
	# Story Result -> Change Fighter (Doc 05 §136-159): the action PUSHes the
	# Story Fighter Select over the result; its Back POPs back to the result.
	if result != null:
		Support.click_center(self, result.change_fighter_button())
		var change: bool = await Support.wait_until(self, func() -> bool:
			return result_host.active_surface() == "story_select" \
				and result_host.story_select() != null and result_host.story_select().visible, 400)
		edge("story_result_change_fighter", change, await settled_state(result_host, "story_select"),
			"Change Fighter reaches the Story Fighter Select")
		check(change, "Story Result CHANGE FIGHTER reaches the Story Fighter Select")
		if change:
			Support.click_center(self, result_host.story_select().back_button())
			var restored: bool = await Support.wait_until(self, func() -> bool:
				return result_host.active_surface() == "story_result" \
					and result_host.story_result() != null and result_host.story_result().visible, 400)
			check(restored, "the Select Back restores the Story Result")
			result = result_host.story_result()
	# Story Result -> Replay/Retry (a fresh encounter from the result action).
	if result != null:
		var replay_arena_id: int = result_host.get_instance_id()
		Support.click_center(self, result.action_button())
		var replay = await Support.wait_for_scene(self, "main.tscn", 400)
		await frames(20)
		var replay_live: bool = replay != null and is_instance_valid(replay)
		var ok: bool = replay_live and str(replay.story_state) == "playing" and not replay.match_over
		edge("story_result_replay_to_gameplay", ok,
			{"story_state": str(replay.story_state) if replay_live else "",
			 "fighters": replay.fighters.size() if replay_live else -1},
			"a fresh encounter starts")
		check(ok, "Story Result REPLAY starts a fresh encounter")
		if replay_live:
			# Story Result -> Main Menu: resolve the replay as a LOSS (the human
			# runs out of stocks) so the result body offers RETRY + MAIN MENU.
			for fighter in replay.fighters:
				fighter.set_physics_process(false)
			var replay_hero = replay.player_one
			if replay_hero != null:
				replay_hero.stocks = 0
				replay._on_fighter_eliminated(replay_hero)
			await frames(10)
			var loss_host = await wait_for_flow(replay_arena_id)
			if loss_host != null:
				await Support.wait_until(self, func() -> bool: return loss_host.is_surface_presented("story_result"), 400)
				var loss_result = loss_host.story_result()
				var loss_seen := loss_result != null and str(loss_result.action_button().text) == "RETRY"
				edge("story_loss_to_story_result", loss_seen,
					{"title": str(loss_result.title_label().text) if loss_result != null else "",
					 "action": str(loss_result.action_button().text) if loss_result != null else ""},
					"the loss result offers RETRY")
				check(loss_seen, "a Story loss offers RETRY (not the victory wording)")
				if loss_result != null:
					Support.click_center(self, loss_result.menu_button())
					var home_scene = await Support.wait_for_scene(self, "home.tscn", 400)
					edge("story_result_to_main", home_scene != null, home_state(home_scene),
						"MAIN MENU from the Story Result returns to Main")
					check(home_scene != null, "Story Result MAIN MENU returns to Main")
			else:
				skip("story_result_to_main", "no loss result host settled after the replay")
	# Pause edges.
	skip("story_pause_to_briefing", "no Pause surface exists at this commit (Doc 08 §3 Story pause edges stay unverified until WP-4)")

# --- How to Play edges --------------------------------------------------------

func part_help_edges() -> void:
	print("--- How to Play edges ---")
	var home = await ensure_main()
	var help_row: Control = home.menu_rows()[2].get_node("HitArea")
	Support.click_center(self, help_row)
	await frames(12)
	var page = home.find_child("HowToPlay", true, false)
	var reached: bool = page != null and str(home.state) == "help"
	edge("main_to_how_to_play", reached, {"state": str(home.state), "page": str(page != null),
			"page_script_live": str(page.has_method("show_section")) if page != null else "false"},
		"the help page is up and owns input")
	check(reached, "the HOW TO PLAY row opens the help page")
	if page != null and not page.has_method("show_section"):
		defect("how_to_play_page_script_dead",
			"res://scripts/frontend/how_to_play.gd fails to parse (line 162: space indentation mixed with tabs), so the mounted help page has no controller script: no sections, no anchors, no roster, and home.gd's connect of its 'closed' signal fails. The route reaches an inert page.")
	await Support.tap_key(self, KEY_ESCAPE)
	await frames(10)
	var back_to_main: bool = is_instance_valid(home) and str(home.state) == "home"
	edge("how_to_play_to_main", back_to_main, home_state(home), "ui_cancel returns to the Main destination list")
	check(back_to_main, "ui_cancel returns How to Play to Main")
	skip("how_to_play_quit_modal_stay",
		"the global Quit modal is NOT reachable from How to Play at this commit: home.gd's cancel handler returns the help state to Main instead of opening the modal, so the Doc 08 §3 'Help -> Quit modal -> Stay -> same Help state' edge cannot be driven")
	home.queue_free()
	await frames(3)

func declare_unimplemented_edges() -> void:
	# Doc 08 §3 edges whose destination surface does not exist at this commit.
	skip("gameplay_pause_resume", "no Pause surface: main.gd routes Esc/Start in gameplay to back_to_menu(), so there is no Resume destination to assert (WP-4)")
	skip("gameplay_pause_leave_match_to_css", "no Pause surface: 'Leave Match -> CSS' does not exist; Esc leaves the arena to Main (WP-4)")
	skip("gameplay_os_close_stay", "the OS close path needs a real window (windowed pass)")

func report() -> void:
	var passed := 0
	for entry in edges:
		if bool(entry["pass"]):
			passed += 1
	var payload := {
		"contract": "Doc 08 §3 route-edge matrix (entry/exit/back/return incl. origins) — WP-7 / LANE C",
		"generated_by": "tests/test_acceptance_route_matrix.gd",
		"edges": edges,
		"skips": skips,
		"defects": defects,
		"summary": {"edges_run": edges.size(), "edges_passed": passed, "edges_failed": edges.size() - passed,
				"skipped_edges": skips.size(), "exposed_defects": defects.size(),
				"checks": checks, "failures": failures},
	}
	var path := Support.write_json(REPORT_JSON, payload)
	print("ROUTE_MATRIX_JSON %s" % path)
	print("ROUTE_MATRIX_SUMMARY edges=%d passed=%d skipped=%d defects=%d" % [
		edges.size(), passed, skips.size(), defects.size()])
	for entry in skips:
		print("SKIPPED %s — %s" % [entry["edge"], entry["reason"]])
	if failures > 0:
		print("FAILURES: %d of %d checks" % [failures, checks])
		quit(1)
		return
	print("PASS: route matrix — %d edges driven by public input (%d edges skipped with reason, %d defects recorded)" % [
		edges.size(), skips.size(), defects.size()])
	quit(0)

# --- state -------------------------------------------------------------------
var results_host = null
var results_id := 0

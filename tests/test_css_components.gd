extends SceneTree
# WP-D component contract (Doc 04 §6/§9/§12-13A/§19, Doc 09 §16/§22):
# FighterRenderView profiles and subjects, portrait assets, FighterTile
# candidate/geometry rules, PlayerBay state visibility, ReadyBand states,
# PlayerTokenView variants, and token/name-band geometry. Runs the components
# in isolation (headless) — no screen assembly required.
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func run():
	var Roster = load("res://scripts/roster.gd")
	var Tokens = load("res://scripts/ui_tokens.gd")
	var PortraitData = load("res://scripts/frontend/portrait_data.gd")
	var RenderView = load("res://scripts/frontend/fighter_render_view.gd")
	var ids: Array = Roster.ids()

	# --- 1. FighterRenderView: seven roster ids, framing, update policy ----
	var view = RenderView.new()
	view.name = "TestRenderView"
	view.size = Vector2(320.0, 320.0)
	root.add_child(view)
	for i in 3: await process_frame
	view.set_profile("PORTRAIT")
	check(view.profile_name() == "PORTRAIT", "render view accepts the PORTRAIT profile by name")
	check(not view.is_live(), "render view is not live by default")
	check(view.update_mode() != SubViewport.UPDATE_ALWAYS, "render view defaults to render-on-change, never UPDATE_ALWAYS")
	for id in ids:
		view.set_subjects([str(id)])
		for i in 3: await process_frame
		check(view.get_subject_count() == 1, "render view builds one subject for %s" % str(id))
		var box: AABB = view.model_aabb()
		check(box.size.length() > 0.05, "render view %s builds a visible model with a valid AABB" % str(id))
		check(view.get_fit_distance() > 0.1, "render view %s gets a camera fit distance" % str(id))
		var subject: Node3D = view.subject_nodes()[0] if view.get_subject_count() > 0 else null
		check(subject != null and not subject.is_in_group("fighters"), "render view %s subject stays out of the fighters group" % str(id))
		check(subject != null and not subject.is_physics_processing(), "render view %s subject has physics disabled" % str(id))
	# profile framing: the full-body bay frame needs more distance than the bust
	view.set_subjects(["teknium"])
	for i in 3: await process_frame
	var bust_fit: float = view.get_fit_distance()
	view.set_profile("PLAYER_BAY")
	for i in 3: await process_frame
	var bay_fit: float = view.get_fit_distance()
	check(bust_fit > 0.1 and bay_fit > 0.1 and not is_equal_approx(bust_fit, bay_fit), "PORTRAIT and PLAYER_BAY frame differently (%.2f vs %.2f)" % [bust_fit, bay_fit])
	check(view.profile_name() == "PLAYER_BAY", "render view switches profiles")
	# team profile: several subjects, combined framing, one camera/light rig
	view.set_profile("RESULTS_TEAM")
	view.set_subjects(["teknium", "doge_man", "ggb"])
	for i in 3: await process_frame
	check(view.get_subject_count() == 3, "team profile instantiates every subject")
	var combined: AABB = view.framed_box()
	var solo: AABB = RenderView.PROFILES[RenderView.PROFILE_RESULTS_TEAM]["box"]
	check(combined.size.x > solo.size.x + 1.0, "team profile frames the combined subject span")
	check(view.get_fit_distance() > 0.1, "team profile computes a usable fit distance")
	var rig_lights := 0
	for node in view.view().find_children("*", "DirectionalLight3D", true, false):
		rig_lights += 1
	check(rig_lights == 2 and view.view().own_world_3d, "team profile uses ONE lighting rig in its own world")
	# live only on request
	view.set_live(true)
	check(view.update_mode() == SubViewport.UPDATE_ALWAYS, "set_live(true) is the only path to UPDATE_ALWAYS")
	view.set_live(false)
	check(view.update_mode() != SubViewport.UPDATE_ALWAYS, "set_live(false) returns to render-on-change")
	check(view.render_target() != null and view.texture_rect() != null, "render view exposes its render target texture rect")
	view.clear_subjects()
	await process_frame
	check(not view.has_subjects() and view.get_subject_count() == 0, "render view clears its subjects")
	view.queue_free()

	# --- 2. portrait assets exist and load ---------------------------------
	for id in ids:
		var path: String = PortraitData.portrait_path(str(id))
		var exists: bool = FileAccess.file_exists(path)
		var size := 0
		if exists:
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				size = file.get_length()
		check(exists and size > 0, "portrait asset %s exists and is non-empty" % path)
		var tex: Texture2D = PortraitData.portrait_texture(str(id))
		check(tex != null and tex is Texture2D, "portrait texture %s loads" % path)
	check(PortraitData.missing_ids(ids).is_empty(), "no roster id is missing a portrait")

	# --- 3. FighterTile -----------------------------------------------------
	var tile = load("res://scenes/components/FighterTile.tscn").instantiate()
	root.add_child(tile)
	await process_frame
	tile.setup("teknium", "Teknium", PortraitData.portrait_texture("teknium"))
	check(tile.portrait_texture() != null, "tile shows the portrait texture")
	check(tile.anchor() != null and tile.token_layer() != null, "tile exposes its cursor anchor and token layer")
	var tile_size: Vector2 = tile.size
	var portrait_before: Rect2 = tile.portrait_area()
	var band_before: Rect2 = tile.name_band_rect()
	tile.set_candidate(true)
	await process_frame
	check(tile.is_candidate(), "tile reports its candidate state")
	check(tile.size == tile_size, "candidate state does not change the tile layout size")
	check(tile.portrait_area() == portrait_before and tile.name_band_rect() == band_before, "candidate state leaves tile geometry untouched")
	var overlay_inside := true
	for node in tile.get_node("CandidateOverlay").get_children():
		var rect := Rect2(node.position, node.size)
		if not Rect2(Vector2.ZERO, tile.size).encloses(rect):
			overlay_inside = false
	check(overlay_inside, "candidate overlay never reaches past the tile bounds")
	tile.set_candidate(false)
	check(not tile.is_candidate(), "tile clears its candidate state")
	tile.set_tile_size(Vector2(140.0, 100.0))
	check(is_equal_approx(tile.size.x, 140.0) and is_equal_approx(tile.size.y, 100.0), "tile lays out at the requested size")
	# The optional floor is the owning surface's rule: Character Select passes
	# its fixed 108x82 reference so roster growth can never shrink a tile, while
	# a surface with its own tighter grid passes no floor (a 90x72 request is
	# honoured as authored).
	tile.set_tile_size(Vector2(60.0, 40.0), Vector2(108.0, 82.0))
	check(is_equal_approx(tile.size.x, 108.0) and is_equal_approx(tile.size.y, 82.0),
		"a tile never shrinks below the floor its surface declares")
	tile.set_tile_size(Vector2(90.0, 72.0))
	check(is_equal_approx(tile.size.x, 90.0) and is_equal_approx(tile.size.y, 72.0),
		"a surface without a floor keeps its authored size (How to Play / Story Briefing)")
	# Back to the widened probe tile the geometry section below measures on.
	tile.set_tile_size(Vector2(140.0, 100.0))
	check(tile.portrait_area().end.x <= tile.size.x + 0.01 and tile.portrait_area().end.y < tile.name_band_rect().position.y + 0.01, "tile keeps portrait above the name band at any size")
	check(tile.name_band_rect().position.x == 0.0 and is_equal_approx(tile.name_band_rect().size.x, tile.size.x), "name band spans the tile width")

	# --- 4. token placement never covers the name band ---------------------
	var band_rect: Rect2 = tile.name_band_rect()
	for count in [1, 2, 3, 4]:
		var slots: Array[Rect2] = tile.token_slots(count)
		check(slots.size() == count, "tile provides %d token slot(s)" % count)
		var clear_of_band := true
		var inside := true
		var disjoint := true
		for i in slots.size():
			if slots[i].intersects(band_rect):
				clear_of_band = false
			if not Rect2(Vector2.ZERO, tile.size).encloses(slots[i]):
				inside = false
			for j in range(i + 1, slots.size()):
				if slots[i].intersects(slots[j]):
					disjoint = false
		check(clear_of_band, "token slots never cover the name band (%d tokens)" % count)
		check(inside, "token slots stay inside the tile (%d tokens)" % count)
		check(disjoint, "token slots never overlap (%d tokens)" % count)
	var token = load("res://scenes/components/PlayerTokenView.tscn").instantiate()
	tile.token_layer().add_child(token)
	tile.place_token_view(token, 0, 1)
	await process_frame
	var token_rect: Rect2 = token.get_global_rect()
	var band_global: Rect2 = tile.get_node("NameBand").get_global_rect()
	check(not token_rect.intersects(band_global), "a placed token does not cover the name band")
	tile.queue_free()

	# --- 5. PlayerBay --------------------------------------------------------
	var bay = load("res://scenes/components/PlayerBay.tscn").instantiate()
	root.add_child(bay)
	await process_frame
	check(bay is Control and not (bay is BaseButton), "PlayerBay is a Control, never one big Button")
	check(bay.get_node("PlayerHeader/KindControl") is BaseButton, "kind control is a distinct semantic control")
	check(bay.get_node("SecondaryControls/DifficultyRow/DifficultyControl") is BaseButton, "difficulty control is a distinct semantic control")
	check(bay.anchor() != null, "bay exposes its cursor anchor")
	bay.setup(0)
	bay.set_slot_state("bot", "teknium", "Teknium", "normal", 0, 0)
	check(bay.difficulty_row_visible(), "CPU bay shows the difficulty row")
	check(not bay.team_control_visible(), "free-for-all hides the team control")
	check(bay.get_node("PlayerHeader/PlayerLabel").text == "P1", "bay header carries the player identity")
	bay.set_slot_state("human", "teknium", "Teknium", "normal", 0, 0)
	check(not bay.difficulty_row_visible(), "HMN bay hides the difficulty row")
	check(not bay.team_control_visible(), "HMN bay hides the team control in free-for-all")
	bay.set_slot_state("human", "teknium", "Teknium", "normal", 0, 1)
	check(bay.team_control_visible(), "team mode shows the team control")
	check(not bay.difficulty_row_visible(), "team mode without CPU keeps the difficulty row hidden")
	bay.set_slot_state("bot", "teknium", "Teknium", "hard", 1, 1)
	check(bay.difficulty_row_visible() and bay.team_control_visible(), "CPU in team mode shows both secondary controls")
	check(bay.get_node("SecondaryControls/TeamControl").text == "TEAM B", "team control reflects the team value")
	var name_hits := 0
	for node in bay.find_children("*", "Label", true, false):
		if node.text == "TEKNIUM":
			name_hits += 1
	check(name_hits == 1, "fighter name appears exactly once in the bay")
	bay.set_slot_state("empty", "", "", "normal", 0, 1)
	check(not bay.difficulty_row_visible() and not bay.team_control_visible(), "EMPTY bay shows no secondary controls")
	check(bay.render_view().get_subject_count() == 0, "EMPTY bay hosts no fighter model")
	check(bay.render_view().update_mode() != SubViewport.UPDATE_ALWAYS, "bay render view is never permanently live")
	bay.set_slot_state("human", "ggb", "GGB", "normal", 0, 0)
	for i in 4: await process_frame
	check(bay.render_view().get_subject_count() == 1, "bay renders the committed fighter")
	var rendered: Array[String] = bay.render_view().subjects()
	check(rendered.size() == 1 and rendered[0] == "ggb", "bay render view swaps to the newly committed fighter")
	bay.set_active(false)
	check(not bay.get_node("ActiveNotch").visible, "inactive bay shows no warm notch")
	bay.set_active(true)
	check(bay.is_active() and bay.get_node("ActiveNotch").visible, "active bay shows ONE small warm notch")
	var bay_rect := Rect2(Vector2.ZERO, bay.size)
	var bay_inside := true
	for node in bay.get_children():
		if node is Control and not bay_rect.grow(1.0).encloses(Rect2(node.position, node.size)):
			bay_inside = false
	check(bay_inside, "no bay child control extends outside the bay")
	bay.queue_free()

	# --- 6. ReadyBand --------------------------------------------------------
	var band = load("res://scenes/components/ReadyBand.tscn").instantiate()
	root.add_child(band)
	await process_frame
	check(not band.is_shown() and not band.visible, "ready band starts hidden (invalid state shows nothing)")
	check(band.size.x >= Tokens.DESIGN.x * 0.82 and band.size.x <= Tokens.DESIGN.x * 0.90, "ready band spans 82-90%% of the reference width (%.0f px)" % band.size.x)
	check(band.mouse_filter == Control.MOUSE_FILTER_STOP, "ready band is ONE mouse target")
	check(band.entrance_frames() >= 12 and band.entrance_frames() <= 16, "ready entrance is a short 1-shot (12-16 frames)")
	var clicks := [0]
	band.ready_pressed.connect(func() -> void: clicks[0] += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	band._gui_input(click)
	check(clicks[0] == 1, "a click on the band emits ready_pressed once")
	band.show_band()
	check(band.is_shown() and band.visible, "show_band displays the ready state")
	for i in band.entrance_frames() + 3: await process_frame
	check(is_equal_approx(band.modulate.a, 1.0), "ready entrance settles fully visible")
	check(not band.is_processing(), "ready band stops processing after the 1-shot entrance (no pulsing)")
	check(band.anchor() != null, "ready band exposes its cursor anchor")
	band.hide_band()
	check(not band.is_shown() and not band.visible, "hide_band returns to the invalid state")
	band.queue_free()

	# --- 7. PlayerTokenView variants ----------------------------------------
	var seen_colors: Array[Color] = []
	for i in 4:
		var t = load("res://scenes/components/PlayerTokenView.tscn").instantiate()
		root.add_child(t)
		await process_frame
		t.set_player(i)
		check(t.token_size() >= 22.0 and t.token_size() <= 28.0, "token %d keeps the 22-28 px reference size" % i)
		check(t.get_node("TokenLabel").text == "P" + str(i + 1), "token %d shows its P number" % i)
		check(t.player_color().is_equal_approx(Tokens.PLAYER_COLORS[i]), "token %d uses its player color" % i)
		check(not seen_colors.has(t.player_color()), "token %d color is distinct from the other variants" % i)
		seen_colors.append(t.player_color())
		for state in 5:
			t.set_state(state)
		check(t.state_name() == "PLACING", "token state setter drives its presentation states")
		t.squash(Vector2(1.1, 0.9))
		t.settle()
		check(t.scale.is_equal_approx(Vector2.ONE), "token settle restores its neutral scale")
		t.queue_free()
	await process_frame

	if failures == 0:
		print("PASS: css components (render view profiles/subjects, portraits, tile, bay, ready band, tokens)")
	quit(1 if failures else 0)

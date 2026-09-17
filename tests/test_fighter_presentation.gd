extends SceneTree
# WP-3 presentation contract (corrective Doc 07 §2-§9, Doc 04 §12-13, Doc 09
# WP-3; ledger RC-D, C-045, C-046, C-048, C-049, S-003).
#
# The assertions intentionally measure BEHAVIOUR, not implementation shape:
#   * FighterPresentationFactory resolution (roster ids, specialized encounter
#     Bobo, unknown ids never crash);
#   * measured silhouettes = the live build's posed bounds (probe:
#     tools/silhouette_probe.gd);
#   * per-fighter optical framing + destination-aspect fit (no cover crop);
#   * STATIC_POSE / LIVE_IDLE lifecycle — deterministic pose before the first
#     visible frame, live only while deliberately allowed, and NO stop path
#     may leave a mid-animation frame frozen;
#   * adaptive render density (destination aspect + displayed physical pixels);
#   * deterministic portrait generation (same input -> same output).
#
# The measurement method (posed bounds of the rendered build) is shared with
# the factory's table source, so a model/rig change that invalidates the table
# fails HERE first.
const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")
const View = preload("res://scripts/frontend/fighter_render_view.gd")
const Roster = preload("res://scripts/roster.gd")
const Bounds = preload("res://tests/posed_character_bounds.gd")

const BAY_AREA := Vector2(267.0, 296.0)   # PlayerBay render area at 1280x720, 1 occupied row (measured from the review-state capture geometry)
const HEIGHT_TOLERANCE := 0.05
const WIDTH_TOLERANCE := 0.06

var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func run():
	await _factory_resolution()
	await _measured_silhouettes()
	_optical_framing()
	await _lifecycle()
	await _bobo_presentation()
	_density()
	await _portrait_determinism()

	if failures == 0:
		print("PASS: fighter presentation (factory, measured framing, STATIC_POSE/LIVE_IDLE, density, deterministic portraits)")
	quit(1 if failures else 0)

# --- 1. factory resolution ---------------------------------------------------

func _factory_resolution() -> void:
	var roster: Array[String] = Roster.ids()
	check(Factory.roster_ids() == roster, "factory roster ids mirror roster.gd")
	check(Factory.has("bobo") and Factory.is_encounter("bobo"), "bobo resolves as a specialized encounter subject")
	check(not Factory.is_encounter("teknium") and Factory.has("teknium"), "roster ids are not encounters")
	check(not Factory.has("") and not Factory.has("not_a_fighter"), "unknown or empty ids never claim resolution")
	var bobo := Factory.resolve("bobo")
	check(bobo["kind"] == "encounter" and bobo["script_path"] == "res://scripts/bobo_fighter.gd",
		"bobo resolves to the encounter rig script, not the generic fighter")
	check(bobo["ui_idle_clip"] == "Idle" and bobo["display_name"] == "Bobo",
		"bobo carries its approved UI idle clip and encounter display name")
	check(str(bobo["palette_policy"]["policy"]) == "visual_owned",
		"encounter subjects own their painted materials (no slot tint)")
	var tek := Factory.resolve("teknium")
	check(tek["kind"] == "roster" and tek["script_path"] == "res://scripts/fighter.gd",
		"roster ids resolve to the shared fighter script")
	check(str(tek["portrait_path"]) != "" and tek["presentation_key"] == "teknium",
		"roster resolution carries the portrait path and presentation key")
	var unknown := Factory.resolve("not_a_fighter")
	check(unknown["kind"] == "unknown" and unknown["script_path"] == "res://scripts/fighter.gd",
		"unknown ids fall back to the generic fighter + canonical silhouette (never a crash)")
	var script := Factory.subject_script("bobo")
	check(script != null and str(script.resource_path) == "res://scripts/bobo_fighter.gd",
		"subject_script loads the encounter rig")
	check(Factory.subject_script("not_a_fighter") == Factory.subject_script("teknium"),
		"unknown ids build the generic fighter script")
	# Fresh data on every read: callers can never poison the factory.
	var first := Factory.resolve("bobo")
	first["display_name"] = "Mutated"
	check(Factory.resolve("bobo")["display_name"] == "Bobo", "resolution returns fresh dictionaries")
	var cfg := Factory.profile_config("PORTRAIT")
	cfg["fit_margin"] = 99.0
	check(is_equal_approx(float(Factory.profile_config("PORTRAIT")["fit_margin"]), 1.10),
		"profile configs are fresh copies")
	check(Factory.all_ids().size() == roster.size() + 1 and Factory.all_ids().has("bobo"),
		"all_ids() offers roster ids plus encounters exactly once")

# --- 2. measured silhouettes = build truth ----------------------------------

func _silhouette_ids() -> Array[String]:
	return ["teknium", "doge_man", "ggb", "turbofit", "ice_mage", "witcheer", "mephisto", "bobo"]

func _measured_silhouettes() -> void:
	var roster_size := Roster.ids().size()
	var all: Array = Roster.ids()
	all.append("bobo")
	var heights := {}
	var presence := {}
	for id in _silhouette_ids():
		var sil := Factory.silhouette(id)
		check(sil.has("top") and sil.has("sole") and sil.has("half_width"),
			"silhouette table has bounds for " + id)
		var measured := await _measure(id)
		check(int(measured["meshes"]) >= 1, "%s builds real meshes to measure" % id)
		if int(measured["meshes"]) == 0:
			continue
		var lo: Vector3 = measured["lo"]
		var hi: Vector3 = measured["hi"]
		var height := hi.y - lo.y
		check(absf(hi.y - float(sil["top"])) <= HEIGHT_TOLERANCE,
			"%s measured top %.3f matches the presentation table %.3f" % [id, hi.y, float(sil["top"])])
		check(absf(lo.y - float(sil["sole"])) <= HEIGHT_TOLERANCE,
			"%s measured sole %.3f matches the presentation table %.3f" % [id, lo.y, float(sil["sole"])])
		check(absf((hi.x - lo.x) * 0.5 - float(sil["half_width"])) <= WIDTH_TOLERANCE,
			"%s measured half width %.3f matches the presentation table %.3f" % [id, (hi.x - lo.x) * 0.5, float(sil["half_width"])])
		heights[id] = height
		presence[id] = Factory.presence(id, Factory.PROFILE_PLAYER_BAY)
		if id != "bobo":
			# CSS configures LIVE_IDLE before spawning its candidate. This must
			# begin from the same native t=0 pose as static-first view creation.
			var direct_live := await _measure(id, true)
			check(lo.distance_to(direct_live["lo"]) < 0.02 and hi.distance_to(direct_live["hi"]) < 0.02,
				"%s direct LIVE_IDLE spawn uses the measured deterministic pose" % id)
			direct_live["subject"].queue_free()
		measured["subject"].queue_free()
		await process_frame
	check(heights.size() == _silhouette_ids().size(), "every subject produced a measurement")
	# Bobo is a real 3D body, not a nameplate geometry.
	check(float(heights.get("bobo", 0.0)) >= 2.0 and Factory.silhouette("bobo")["top"] > 2.5,
		"bobo measures as a real 3D model (%.2f units tall)" % float(heights.get("bobo", 0.0)))
	# Comparable optical presence across the roster (Doc 07 §6): not equal AABB
	# math, but no fighter is framed as the tiny one either.
	var lo_p := 2.0
	var hi_p := 0.0
	for id in presence.keys():
		lo_p = minf(lo_p, float(presence[id]))
		hi_p = maxf(hi_p, float(presence[id]))
	check(lo_p >= 0.84, "every fighter's measured silhouette fills at least 84%% of its frame (worst %.3f)" % lo_p)
	check(hi_p - lo_p <= 0.12, "optical presence spread stays within 0.12 (%.3f..%.3f)" % [lo_p, hi_p])

func _measure(id: String, direct_live := false) -> Dictionary:
	# Measure the actual UI STATIC_POSE, not an advancing gameplay animation.
	# In particular the paired Mephisto starter and DefaultSwim are sought to
	# t=0 by FighterRenderView; three unpaused frames are a different contract.
	var rig := _make_view(BAY_AREA)
	var view = rig["view"]
	view.set_sway_enabled(false)
	if direct_live:
		view.set_presentation_mode(Factory.MODE_LIVE_IDLE)
	view.set_subjects([id])
	var subject: Node3D = view.subject_nodes()[0]
	subject.rotation_degrees = Vector3.ZERO
	for i in 3:
		await process_frame
	for sk in subject.find_children("*", "Skeleton3D", true, false):
		sk.force_update_all_bone_transforms()
	var measured: Dictionary = Bounds.new().bounds(subject)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var meshes := 0
	for entry in measured.values():
		lo = lo.min(Vector3(entry.min[0], entry.min[1], entry.min[2]))
		hi = hi.max(Vector3(entry.max[0], entry.max[1], entry.max[2]))
		meshes += 1
	return {"lo": lo, "hi": hi, "meshes": meshes, "subject": rig["host"]}

# --- 3. optical framing (pure math, no view) --------------------------------

func _optical_framing() -> void:
	var ids: Array = Roster.ids()
	ids.append("bobo")
	for raw_id in ids:
		var id := str(raw_id)
		var box := Factory.framed_box(id, Factory.PROFILE_PLAYER_BAY)
		check(is_equal_approx(box.position.y, float(Factory.silhouette(id)["sole"])),
			"%s full-body window starts at its measured sole (including hovering poses)" % id)
		check(box.size.x >= 1.5 - 0.001, "%s full-body window keeps the minimum width" % id)
		var aspect := box.size.x / box.size.y
		check(aspect >= 0.5 and aspect <= 2.4, "%s full-body window stays inside the crop tolerance" % id)
		check(Factory.head_clearance(id, Factory.PROFILE_PLAYER_BAY) <= 0.15,
			"%s keeps head clearance <= 0.15 of the frame" % id)
		var presence := Factory.presence(id, Factory.PROFILE_PLAYER_BAY)
		check(presence >= 0.84 and presence <= 1.0, "%s presence is within the comparable band (%.3f)" % [id, presence])
	# Per-fighter windows are actually different (not one shared AABB).
	check(not is_equal_approx(Factory.framed_box("teknium", Factory.PROFILE_PLAYER_BAY).size.y,
			Factory.framed_box("turbofit", Factory.PROFILE_PLAYER_BAY).size.y),
		"short and tall fighters get different full-body windows")
	check(not is_equal_approx(Factory.framed_box("bobo", Factory.PROFILE_PLAYER_BAY).size.x,
			Factory.framed_box("teknium", Factory.PROFILE_PLAYER_BAY).size.x),
		"bobo's wide silhouette widens his window beyond the canonical min width")
	check(is_equal_approx(Factory.framed_box("bobo", Factory.PROFILE_PLAYER_BAY).size.y,
			2.730 + 0.14),
		"bobo's window is derived from his measured 2.73-unit height")
	# Bust rule for portraits: head top sits the declared clearance below the
	# frame top; the two authored overrides keep their measured windows.
	for id in ["teknium", "doge_man", "turbofit", "witcheer", "mephisto"]:
		var box := Factory.framed_box(str(id), Factory.PROFILE_PORTRAIT)
		check(is_equal_approx(box.size.y, 0.93), "%s portrait window is a 0.93 bust" % str(id))
		check(absf(Factory.head_clearance(str(id), Factory.PROFILE_PORTRAIT) - 0.30) <= 0.005,
			"%s portrait puts the head top 30%% below the frame top (%.3f)" % [str(id), Factory.head_clearance(str(id), Factory.PROFILE_PORTRAIT)])
	var ggb_box := Factory.framed_box("ggb", Factory.PROFILE_PORTRAIT)
	check(ggb_box == AABB(Vector3(-0.72, 0.05, -0.72), Vector3(1.44, 0.93, 1.44)),
		"ggb keeps its authored whole-body portrait window")
	var ice_box := Factory.framed_box("ice_mage", Factory.PROFILE_PORTRAIT)
	check(ice_box == AABB(Vector3(-0.80, 1.47, -0.80), Vector3(1.60, 0.93, 1.60)),
		"ice mage keeps its authored detail-spread portrait window")
	check(Factory.framed_box("ggb", Factory.PROFILE_PORTRAIT) != Factory.framed_box("teknium", Factory.PROFILE_PORTRAIT),
		"portrait overrides are per-fighter, never one shared bust")
	# Team composition: the union spans the offsets; one subject = its window.
	var solo := Factory.box_for(["teknium"], Factory.PROFILE_RESULTS_TEAM)
	check(solo == Factory.framed_box("teknium", Factory.PROFILE_RESULTS_TEAM), "single-subject team box is the subject window")
	var duo := Factory.box_for(["teknium", "ggb"], Factory.PROFILE_RESULTS_TEAM)
	check(duo.size.x > solo.size.x + 1.0, "team box spans the subject offsets")
	check(Factory.team_offset(0, 1) == Vector3.ZERO and Factory.team_offset(0, 2).x < 0.0,
		"team offsets are centered on the group")
	# Camera fit uses the destination aspect (Doc 07 §4): a wider destination
	# never needs MORE distance, so the raw render is never cover-cropped.
	var bay_cfg := Factory.profile_config(Factory.PROFILE_PLAYER_BAY)
	var box := Factory.framed_box("teknium", Factory.PROFILE_PLAYER_BAY)
	check(Factory.fit_distance(box, bay_cfg, 1.0) >= Factory.fit_distance(box, bay_cfg, 1.83) - 0.0001,
		"fit distance relaxes as the destination aspect widens")
	check(is_equal_approx(Factory.camera_forward(bay_cfg).length(), 1.0), "camera forward is normalized")
	# Perspective containment: near corners have less camera depth than the
	# aim plane. Ignoring that depth cropped Bobo's feet despite a green AABB fit.
	for id in ids:
		for profile in [Factory.PROFILE_PLAYER_BAY, Factory.PROFILE_RESULTS_HERO, Factory.PROFILE_RESULTS_TEAM]:
			var cfg := Factory.profile_config(profile)
			var fitted := Factory.framed_box(str(id), profile)
			var forward := Factory.camera_forward(cfg)
			var right := Vector3.UP.cross(forward).normalized()
			var up := forward.cross(right).normalized()
			var tangent := tan(deg_to_rad(float(cfg["fov"])) * 0.5)
			for destination_aspect in [267.0 / 296.0, 267.0 / 146.0]:
				var distance := Factory.fit_distance(fitted, cfg, destination_aspect)
				for corner_index in 8:
					var offset := fitted.get_endpoint(corner_index) - Factory.aim_center(fitted, cfg)
					var depth := distance - offset.dot(forward)
					check(depth > 0.0 and absf(offset.dot(right)) <= depth * tangent * destination_aspect + 0.001
						and absf(offset.dot(up)) <= depth * tangent + 0.001,
						"%s %s perspective fit contains corner %d at aspect %.3f" % [id, profile, corner_index, destination_aspect])
	check(Factory.profile_name("player_bay") == "PLAYER_BAY" and Factory.profile_name(0) == "PORTRAIT"
			and Factory.profile_name("nonsense") == "",
		"profile resolution keeps names, indices and rejects junk")

# --- 4. STATIC_POSE / LIVE_IDLE lifecycle -----------------------------------

func _make_view(view_size: Vector2, scale := 1.0) -> Dictionary:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	root.add_child(host)
	var view = View.new()
	view.size = view_size
	host.add_child(view)
	view.set_content_scale_override(scale)
	view.set_profile(View.PROFILE_PLAYER_BAY)
	return {"host": host, "view": view}

func _lifecycle() -> void:
	var rig := _make_view(BAY_AREA)
	var view = rig["view"]
	var host: Control = rig["host"]
	check(view.presentation_mode() == Factory.MODE_STATIC_POSE and view.presentation_mode_name() == "STATIC_POSE",
		"a fresh view is deliberately posed, never accidentally live")
	view.set_subjects(["teknium"])
	var same_frame: String = JSON.stringify(view.pose_signature())
	check(view.pose_signature()["playing"] == 0 and is_equal_approx(float(view.pose_signature()["yaws"][0]), Factory.BASE_YAW_DEG),
		"STATIC_POSE applies the deterministic pose before the first visible frame")
	for i in 3:
		await process_frame
	var static_sig: String = JSON.stringify(view.pose_signature())
	var static_pose: String = _pose_only(view.pose_signature())
	check(static_sig == same_frame, "the pose is already final when the frame is first presented (no settle animation)")
	check(view.pose_ready(), "the posed presentation is ready to be displayed")
	check(not view.is_animating() and not view.is_live(), "a static view reports no animation")
	check(view.update_mode() != SubViewport.UPDATE_ALWAYS, "a static view never updates every frame")
	# Late-mesh frames of the SAME pose, then total stop (render once/cache).
	for i in 3:
		await process_frame
		check(JSON.stringify(view.pose_signature()) == static_sig, "late-mesh frames never change the pose")
	check(not view.is_processing(), "a settled static view performs no per-frame work")
	check(view.update_mode() != SubViewport.UPDATE_ALWAYS, "a settled static view stops updating the viewport")
	# LIVE_IDLE: deliberate idle only, while visibly presented.
	view.set_presentation_mode(Factory.MODE_LIVE_IDLE)
	for i in 3:
		await process_frame
	check(view.is_live() and view.is_animating(), "LIVE_IDLE updates while the presentation is visible")
	check(view.update_mode() == SubViewport.UPDATE_ALWAYS, "LIVE_IDLE is the only path to UPDATE_ALWAYS")
	var live_start: Dictionary = view.pose_signature()
	for i in 27:
		await process_frame
	var live_now: Dictionary = view.pose_signature()
	check(float(live_now["sway"]) > 0.0, "the approved idle runs on its own clock")
	check(absf(float(live_now["yaws"][0]) - Factory.BASE_YAW_DEG) > 0.2
			and absf(float(live_now["yaws"][0]) - Factory.BASE_YAW_DEG) <= 3.5 + 0.001,
		"the idle sway stays inside the approved amplitude")
	check(not is_equal_approx(float(live_start["yaws"][0]), float(live_now["yaws"][0])), "the idle actually moves the subject")
	# STOP: every stop path must snap the deterministic pose first — a stopped
	# view can never hold a frozen mid-animation frame (RC-D).
	view.set_presentation_mode(Factory.MODE_STATIC_POSE)
	check(JSON.stringify(view.pose_signature()) == static_sig,
		"stopping a live view restores the EXACT deterministic pose (no frozen mid-animation frame)")
	for i in 3:
		await process_frame
	check(JSON.stringify(view.pose_signature()) == static_sig, "the restored pose stays put across frames")
	check(view.update_mode() != SubViewport.UPDATE_ALWAYS, "a stopped view leaves UPDATE_ALWAYS")
	# Hiding (own flag or an ancestor) parks a live view with zero updates.
	view.set_presentation_mode(Factory.MODE_LIVE_IDLE)
	for i in 5:
		await process_frame
	check(view.is_animating(), "live before hiding")
	host.visible = false
	for i in 2:
		await process_frame
	check(not view.is_animating() and view.update_mode() == SubViewport.UPDATE_DISABLED and not view.is_processing(),
		"a hidden live view parks: no updates, no processing")
	check(_pose_only(view.pose_signature()) == static_pose,
		"parking snaps the deterministic pose first (mode intent stays LIVE_IDLE, the pose does not hold an animation frame)")
	host.visible = true
	for i in 2:
		await process_frame
	check(view.is_animating() and view.update_mode() == SubViewport.UPDATE_ALWAYS, "showing the view again resumes the live idle")
	# Legacy component contract: set_live maps to the two modes.
	view.set_live(false)
	check(view.presentation_mode() == Factory.MODE_STATIC_POSE and JSON.stringify(view.pose_signature()) == static_sig,
		"set_live(false) is a deliberate stop with the deterministic pose")
	view.set_live(true)
	check(view.presentation_mode() == Factory.MODE_LIVE_IDLE and view.update_mode() == SubViewport.UPDATE_ALWAYS,
		"set_live(true) is the deliberate live mode")
	view.clear_subjects()
	for i in 2:
		await process_frame
	check(not view.has_subjects() and view.update_mode() == SubViewport.UPDATE_DISABLED, "clearing subjects parks the viewport")
	host.queue_free()
	await process_frame

# --- 5. Bobo: real 3D encounter presentation --------------------------------

func _bobo_presentation() -> void:
	var rig := _make_view(BAY_AREA)
	var view = rig["view"]
	var host: Control = rig["host"]
	view.set_subjects(["bobo"])
	check(view.subject_scripts().size() == 1
			and String(view.subject_scripts()[0]).ends_with("bobo_fighter.gd"),
		"the render view builds Bobo through the encounter rig (not a generic fighter)")
	var subject: Node3D = view.subject_nodes()[0]
	check(subject.find_child("BoboVisual", true, false) != null,
		"Bobo's visual rig is present on the subject (3D model, not a nameplate)")
	check(Factory.ui_idle_clip("bobo") == "Idle" and Factory.ui_idle_clip("teknium") == "",
		"only encounter subjects declare an animation idle clip")
	var players := _players(subject)
	check(players.size() >= 1, "Bobo carries an AnimationPlayer for his GLB idle")
	for player in players:
		check(not player.is_playing(), "STATIC_POSE pauses Bobo's animation before the first visible frame")
		check(is_zero_approx(player.current_animation_position), "STATIC_POSE holds Bobo's animation at t=0")
	for i in 3:
		await process_frame
	check(view.model_aabb().size.length() > 0.05 and view.pose_ready(), "Bobo produces a visible model box and a finished fit")
	var static_sig: String = JSON.stringify(view.pose_signature())
	view.set_presentation_mode(Factory.MODE_LIVE_IDLE)
	for i in 3:
		await process_frame
	var playing := 0
	for player in players:
		if player.is_playing() and String(player.current_animation) == "Idle":
			playing += 1
	check(playing >= 1, "LIVE_IDLE plays Bobo's GLB Idle clip")
	for i in 27:
		await process_frame
	check(players[0].current_animation_position > 0.0, "Bobo's idle actually advances while live")
	view.set_presentation_mode(Factory.MODE_STATIC_POSE)
	for player in players:
		check(not player.is_playing() and is_zero_approx(player.current_animation_position),
			"stopping Bobo returns him to the deterministic t=0 pose (never a frozen mid-animation frame)")
	check(JSON.stringify(view.pose_signature()) == static_sig, "Bobo's stopped presentation equals his original static pose")
	check(view.pose_signature()["playing"] == 0, "no animation player keeps running in STATIC_POSE")
	# Candidate-style subject swap reuses the stage (no viewport/rig churn).
	var stage: Node = view.view().get_node_or_null("RenderStage")
	var swaps := ["ggb", "mephisto", "bobo", "teknium"]
	for id in swaps:
		view.set_subjects([str(id)])
		for i in 2:
			await process_frame
		check(view.has_subjects() and view.get_subject_count() == 1, "swap to %s keeps exactly one subject" % str(id))
	check(view.view().get_node_or_null("RenderStage") == stage,
		"candidate-style swaps reuse the ONE render stage (viewport/rig are not reinstantiated)")
	var lights := 0
	for node in view.view().find_children("*", "DirectionalLight3D", true, false):
		lights += 1
	check(lights == 2, "the reused stage still has its ONE lighting rig")
	check(view.view().own_world_3d, "the presentation keeps its own world")
	host.queue_free()
	await process_frame

func _pose_only(sig: Dictionary) -> String:
	# The pose fields without the mode intent: a parked live view keeps its
	# LIVE_IDLE intent while its pose must be the deterministic one.
	var copy := sig.duplicate()
	copy.erase("mode")
	copy.erase("animating")
	return JSON.stringify(copy)

func _players(subject: Node) -> Array:
	var out: Array = []
	for node in subject.find_children("*", "AnimationPlayer", true, false):
		out.append(node)
	return out

# --- 6. adaptive render density (Doc 07 §5; ledger C-048) -------------------

func _density() -> void:
	var one_to_one := Factory.render_density(Factory.PROFILE_PLAYER_BAY, BAY_AREA, 1.0, 1.0)
	check(one_to_one == Vector2i(267, 296), "at 720p the bay renders 1:1 with its displayed pixels (%s)" % str(one_to_one))
	var scaled := Factory.render_density(Factory.PROFILE_PLAYER_BAY, BAY_AREA, 3.0, 1.0)
	check(scaled == Vector2i(801, 888), "at 3x output scale the bay renders at 3x density (%s)" % str(scaled))
	check(absf(float(scaled.x) / float(scaled.y) - BAY_AREA.x / BAY_AREA.y) <= 0.01,
		"the render target keeps the destination aspect (no cover crop needed)")
	check(Factory.render_density(Factory.PROFILE_PLAYER_BAY, BAY_AREA, 4.0, 2.0).x <= 1440
			and Factory.render_density(Factory.PROFILE_PLAYER_BAY, BAY_AREA, 4.0, 2.0).y <= 960,
		"profile caps bound the extreme scale")
	var capped := Factory.render_density(Factory.PROFILE_RESULTS_HERO, Vector2(600.0, 400.0), 4.0, 2.0)
	check(capped.x <= 1280 and capped.y <= 960 and capped.x * capped.y <= 1228800,
		"the pixel-area cap keeps extreme windows inside the profile budget (%s)" % str(capped))
	check(Factory.render_density(Factory.PROFILE_PORTRAIT, Vector2(320.0, 320.0), 1.0, 1.0) == Vector2i(320, 320),
		"the portrait profile honours a square destination")
	check(not Factory.density_is_material(Vector2i(267, 146), Vector2i(268, 147)),
		"sub-hysteresis wobble never reallocates")
	check(Factory.density_is_material(Vector2i(267, 146), Vector2i(270, 146)),
		"a meaningful size change reallocates")
	# View-level: the SubViewport follows the displayed physical pixels.
	var rig := _make_view(BAY_AREA, 1.0)
	var view = rig["view"]
	view.refresh_density()
	check(view.render_size() == Vector2i(267, 296), "view density at 1x matches the displayed pixels (%s)" % str(view.render_size()))
	view.set_content_scale_override(3.0)
	check(view.render_size() == Vector2i(801, 888), "view reallocates when the output scale changes (%s)" % str(view.render_size()))
	view.set_content_scale_override(1.0)
	check(view.render_size() == Vector2i(267, 296), "returning to 1x restores the 1:1 target")
	view.set_content_scale_override(1.005)
	check(view.render_size() == Vector2i(267, 296), "no reallocation for a sub-hysteresis scale wobble")
	check(view.texture_fit_mode() == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"the texture fit is non-destructive containment (never a cover crop)")
	check(view.texture_fit_mode() != TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"the destructive cover crop is gone (ledger C-045)")
	view.set_render_size(Vector2i(320, 240))
	view.refresh_density()
	check(view.render_size() == Vector2i(320, 240), "an authored size wins over density (portrait inspection runs)")
	rig["host"].queue_free()
	await process_frame

# --- 7. deterministic portrait generation (Doc 07 §8) -----------------------

func _portrait_determinism() -> void:
	var spec_a: String = JSON.stringify(Factory.portrait_spec("ggb"))
	var spec_b: String = JSON.stringify(Factory.portrait_spec("ggb"))
	check(spec_a == spec_b, "the portrait spec is pure data (two reads are identical)")
	var spec := Factory.portrait_spec("ggb")
	check(spec["profile"] == Factory.PROFILE_PORTRAIT and spec["mode"] == Factory.MODE_STATIC_POSE and spec["mode_name"] == "STATIC_POSE",
		"portraits are generated from STATIC_POSE")
	check(is_equal_approx(float(spec["pose_yaw_deg"]), Factory.BASE_YAW_DEG) and is_zero_approx(float(spec["pose_time"])),
		"portrait pose yaw/time are fixed constants (no clock input)")
	check(spec["box"] == Factory.framed_box("ggb", Factory.PROFILE_PORTRAIT), "the spec carries the portrait framing window")
	var specs: Array = Factory.portrait_specs()
	check(specs.size() == Roster.ids().size(), "one portrait spec per roster id")
	for entry in specs:
		check(entry["box"] == Factory.framed_box(str(entry["id"]), Factory.PROFILE_PORTRAIT),
			"portrait spec %s uses its own framed window" % str(entry["id"]))
	# Two independent generations of the same input capture the SAME state.
	var first: String = await _portrait_snapshot("ggb")
	var second: String = await _portrait_snapshot("ggb")
	check(first == second, "same input -> same output: two fresh portrait generations are identical")
	var other: String = await _portrait_snapshot("teknium")
	check(other != first, "different input -> different framing (the snapshot is not a constant)")

func _portrait_snapshot(id: String) -> String:
	var rig := _make_view(Vector2(320.0, 320.0), 1.0)
	var view = rig["view"]
	view.set_profile(View.PROFILE_PORTRAIT)
	view.set_presentation_mode(Factory.MODE_STATIC_POSE)
	view.set_subjects([id])
	var same_frame: Dictionary = view.pose_signature()
	var snapshot := {
		"pose": same_frame,
		"size": [view.render_size().x, view.render_size().y],
		"box": [view.framed_box().position.x, view.framed_box().position.y, view.framed_box().size.x, view.framed_box().size.y],
	}
	for i in 4:
		await process_frame
	snapshot["settled"] = view.pose_signature()
	check(JSON.stringify(snapshot["pose"]) == JSON.stringify(snapshot["settled"]),
		"portrait capture %s: the first presented frame already holds the final pose" % id)
	rig["host"].queue_free()
	await process_frame
	return JSON.stringify(snapshot)

class_name FighterRenderView
extends Control
# FighterRenderView — the ONE reusable fighter-presentation system (Doc 01 §21,
# Doc 09 §16, corrective Doc 07 §2-§9; ledger RC-D, C-045, C-046, C-048, S-003).
# One instance owns exactly one SubViewport with its own world, one Environment
# and one lighting rig. Subjects are resolved and built by
# FighterPresentationFactory, so every screen (PlayerBay, CSS candidate
# preview, Story briefing enemy/selected fighter, How-to-Play, Results hero,
# portrait generation) presents through ONE construction path — including
# specialized enemies (Bobo renders through scripts/bobo_fighter.gd).
#
# Profiles: PORTRAIT (head/upper torso bust), PLAYER_BAY (full body, floor
# line), RESULTS_HERO, RESULTS_TEAM (one camera/light rig, several subjects).
#
# Presentation lifecycle (Doc 07 §2 — deliberate, never a hybrid):
#   STATIC_POSE  deterministic pose applied BEFORE the first visible frame:
#                subject processing disabled, animation players paused at t=0,
#                neutral yaw, sway phase 0; render once, plus at most
#                RENDER_WINDOW late-mesh frames of the SAME pose, then stop.
#   LIVE_IDLE    viewport updates while the presentation is visible; the
#                approved UI idle is the view's own sway clock, plus the
#                declared ui_idle_clip of encounter subjects (Bobo's GLB Idle).
#                Hidden/stopped views freeze back to the deterministic pose.
# The old "animate for 12 rendered frames then stop" behaviour is deleted: a
# view can never stop mid-animation, because every stop path snaps the
# deterministic pose first (asserted by tests/test_fighter_presentation.gd).
#
# Framing: FighterPresentationFactory owns the per-fighter measured silhouette
# windows and the camera-fit math (the hero_rig math lives there once). The
# SubViewport aspect IS the destination Control's aspect and its pixel density
# derives from the displayed physical size, so the raw render and the displayed
# frame are the same composition — the render target is contained, never
# cover-cropped.

const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")

const PROFILE_PORTRAIT := Factory.PROFILE_PORTRAIT
const PROFILE_PLAYER_BAY := Factory.PROFILE_PLAYER_BAY
const PROFILE_RESULTS_HERO := Factory.PROFILE_RESULTS_HERO
const PROFILE_RESULTS_TEAM := Factory.PROFILE_RESULTS_TEAM
const PROFILE_ORDER := Factory.PROFILE_ORDER
const PROFILES := Factory.PROFILES
const FRAME_OVERRIDES := Factory.FRAME_OVERRIDES

const MODE_STATIC_POSE := Factory.MODE_STATIC_POSE
const MODE_LIVE_IDLE := Factory.MODE_LIVE_IDLE

const BASE_YAW_DEG := Factory.BASE_YAW_DEG
const RENDER_WINDOW := 2              # late-mesh frames after a pose change (pose-frozen)
const FIT_ATTEMPTS := 120             # self-healing camera fit bound (as hero_rig)
const SWAY_DEG := 3.5                 # live-only approved idle, own clock
const SWAY_SECONDS := 7.0
const MIN_HONEST_AABB := 0.05         # below this the mesh AABB is not a silhouette

var _profile_name := PROFILE_PLAYER_BAY
var _mode := MODE_STATIC_POSE
var _palette := 0
var _ids: Array[String] = []
var _subjects: Array[Node3D] = []
var _sway := 0.0
var _sway_enabled := true
var _render_window := 0
var _fit_attempts := 0
var _fit_distance := 0.0
var _content_scale_override := 0.0
var _quality_scale := Factory.DEFAULT_QUALITY_SCALE
var _authored_size := false           # explicit set_render_size() wins over density

var _stage: Node3D
var _viewport: SubViewport
var _target: TextureRect
var _camera: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build_stage()
	resized.connect(_on_resized)
	visibility_changed.connect(_refresh_mode)
	# Output-scale changes (window resize / fullscreen switch) reallocate the
	# render density even though the logical Control size did not change
	# (Doc 07 §5: reallocate on output scale/resolution changes; never per
	# frame). Hysteresis in _apply_density rejects sub-pixel wobble.
	var window := get_window()
	if window != null:
		window.size_changed.connect(_on_window_size_changed)

func _build_stage() -> void:
	# Lazy: callers may configure the view in the same frame it is added
	# (before _ready), exactly like hero_rig's on-demand stage build.
	if _viewport != null and is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = "RenderViewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = PROFILES[_profile_name]["render_size"]
	add_child(_viewport)
	_target = TextureRect.new()
	_target.name = "RenderTarget"
	_target.texture = _viewport.get_texture()
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Non-destructive fit (Doc 07 §4): the render already matches the
	# destination aspect, so containment IS the exact composition. A cover crop
	# would compose one frame and display another (ledger C-045).
	_target.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_target)
	var holder := Node3D.new()
	holder.name = "RenderStage"
	_viewport.add_child(holder)
	_stage = holder
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cfe3dd")
	env.ambient_light_energy = 0.72
	_camera = Camera3D.new()
	_camera.name = "RenderCamera"
	_camera.fov = float(PROFILES[_profile_name]["fov"])
	_camera.current = true
	holder.add_child(_camera)
	_key_light = DirectionalLight3D.new()
	_key_light.light_energy = 1.15
	_key_light.rotation_degrees = Vector3(-38.0, 32.0, 0.0)
	holder.add_child(_key_light)
	_fill_light = DirectionalLight3D.new()
	_fill_light.light_energy = 0.45
	_fill_light.light_color = Color("ffd9ae")
	_fill_light.rotation_degrees = Vector3(-14.0, -128.0, 0.0)
	holder.add_child(_fill_light)
	var world := WorldEnvironment.new()
	world.name = "RenderEnvironment"
	world.environment = env
	holder.add_child(world)
	_apply_profile()

# --- profile / configuration ---------------------------------------------

func set_profile(profile) -> void:
	_build_stage()
	var name := Factory.profile_name(profile)
	if name == "":
		push_error("FighterRenderView: unknown profile %s" % str(profile))
		return
	_profile_name = name
	_apply_profile()
	_refresh()

func profile_name() -> String:
	return _profile_name

func profile_config() -> Dictionary:
	return Factory.profile_config(_profile_name)

func _apply_profile() -> void:
	var cfg: Dictionary = PROFILES[_profile_name]
	_camera.fov = float(cfg["fov"])
	if not _authored_size:
		_viewport.size = cfg["render_size"]
	_apply_density()
	_fit_distance = 0.0
	_fit_attempts = 0

func set_render_size(size_px: Vector2i) -> void:
	# Explicit authored size (portrait generation --size): disables density.
	_build_stage()
	_authored_size = true
	_viewport.size = Vector2i(maxi(size_px.x, 8), maxi(size_px.y, 8))
	_fit_distance = 0.0

func render_size() -> Vector2i:
	return _viewport.size if _viewport != null else Vector2i.ZERO

func set_palette(index: int) -> void:
	_palette = index
	for i in _subjects.size():
		if is_instance_valid(_subjects[i]):
			Factory.apply_palette(_subjects[i], _ids[i], _palette)
	_refresh()

func set_subject_palettes(indices: Array) -> void:
	# Per-subject palette identity for multi-subject presentations (Doc 06 §10:
	# "team view supports multiple independently paletted subjects"). Each
	# entry is the resolved presentation variant of that subject's station, so
	# two duplicates of one fighter cannot collapse to one colour. A single
	# value list shorter than the subject list leaves the remaining subjects on
	# the view palette; set_palette() stays the one-palette-for-all entry point.
	var applied := false
	for i in _subjects.size():
		if not is_instance_valid(_subjects[i]):
			continue
		var index := int(indices[i]) if i < indices.size() else _palette
		Factory.apply_palette(_subjects[i], _ids[i], index)
		applied = true
	if not indices.is_empty():
		_palette = int(indices[0])
	if applied:
		_refresh()

func palette_index() -> int:
	return _palette

# --- adaptive render density (Doc 07 §5; ledger C-048) --------------------

func content_scale() -> float:
	# Physical pixels per logical UI unit: the window size against the logical
	# viewport. Tests pin it through set_content_scale_override().
	if _content_scale_override > 0.0:
		return _content_scale_override
	if not is_inside_tree():
		return 1.0
	var window := get_window()
	if window == null:
		return 1.0
	var logical := get_viewport().get_visible_rect().size
	if logical.x <= 0.0:
		return 1.0
	return clampf(float(window.size.x) / logical.x, Factory.CONTENT_SCALE_MIN, Factory.CONTENT_SCALE_MAX)

func set_content_scale_override(value: float) -> void:
	_content_scale_override = maxf(value, 0.0)
	_apply_density()

func set_quality_scale(value: float) -> void:
	_quality_scale = clampf(value, Factory.QUALITY_MIN, Factory.QUALITY_MAX)
	_apply_density()

func quality_scale() -> float:
	return _quality_scale

func refresh_density() -> Vector2i:
	# Public: recompute the render target density now (tests + explicit
	# reallocation after a profile/output change).
	_apply_density()
	return render_size()

func _apply_density() -> void:
	if _viewport == null or _authored_size:
		return
	var displayed := size
	if displayed.x <= 8.0 or displayed.y <= 8.0:
		if _viewport.size != PROFILES[_profile_name]["render_size"]:
			_viewport.size = PROFILES[_profile_name]["render_size"]
		return
	var target := Factory.render_density(_profile_name, displayed, content_scale(), _quality_scale)
	if Factory.density_is_material(_viewport.size, target):
		_viewport.size = target
		_fit_distance = 0.0
		_fit_attempts = 0
		if has_subjects():
			frame_model()
			request_render()

func _on_resized() -> void:
	# Reallocate only on meaningful size changes (never per frame).
	_apply_density()

func _on_window_size_changed() -> void:
	# Output scale changed: the displayed physical pixel footprint of every
	# hero presentation changed with it (Doc 07 §5, ledger C-048).
	_apply_density()

# --- presentation mode (Doc 07 §2) ----------------------------------------

func set_presentation_mode(mode) -> void:
	_build_stage()
	_mode = Factory.normalize_mode(mode)
	_refresh_mode()

func presentation_mode() -> int:
	return _mode

func presentation_mode_name() -> String:
	return Factory.mode_name(_mode)

func is_animating() -> bool:
	# True ONLY while a deliberate LIVE_IDLE presentation is actually updating:
	# no state may stop the viewport while an animation continues.
	return _mode == MODE_LIVE_IDLE and _is_presented() and has_subjects()

func is_live() -> bool:
	# Mode intent (kept for the pre-WP-3 component contract).
	return _mode == MODE_LIVE_IDLE

func set_live(enabled: bool) -> void:
	set_presentation_mode(MODE_LIVE_IDLE if enabled else MODE_STATIC_POSE)

func _is_presented() -> bool:
	return is_inside_tree() and is_visible_in_tree()

func _refresh_mode() -> void:
	_build_stage()
	if not has_subjects() or not _is_presented():
		# No subjects, hidden, or stopped: update nothing and freeze the pose.
		_park()
		return
	if _mode == MODE_LIVE_IDLE:
		_start_live()
	else:
		_freeze_static_pose()
		request_render()

func _start_live() -> void:
	for i in _subjects.size():
		var subject := _subjects[i]
		if not is_instance_valid(subject):
			continue
		subject.process_mode = Node.PROCESS_MODE_INHERIT
		var clip := Factory.ui_idle_clip(_ids[i])
		for player in _animation_players(subject):
			if clip == "":
				player.pause()   # roster views: the approved idle is the view sway
			else:
				player.play(clip, 0.08)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)

func _freeze_static_pose() -> void:
	# Deterministic pose, applied before the presentation becomes visible:
	# processing disabled, animation paused at t=0, neutral yaw, sway phase 0.
	_sway = 0.0
	for subject in _subjects:
		if not is_instance_valid(subject):
			continue
		subject.process_mode = Node.PROCESS_MODE_DISABLED
		subject.rotation_degrees = Vector3(0.0, BASE_YAW_DEG, 0.0)
		for player in _animation_players(subject):
			player.pause()
			player.seek(0.0, true)

func _park() -> void:
	# No subjects, hidden, or over-budget: update nothing, freeze the pose.
	_freeze_static_pose()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_render_window = 0
	set_process(false)

func _animation_players(subject: Node) -> Array:
	var out: Array = []
	if subject == null or not is_instance_valid(subject):
		return out
	for node in subject.find_children("*", "AnimationPlayer", true, false):
		out.append(node)
	return out

# --- subjects --------------------------------------------------------------

func set_subjects(ids: Array) -> void:
	_build_stage()
	clear_subjects()
	var count := ids.size()
	for i in count:
		var id := str(ids[i])
		if id == "":
			continue
		_ids.append(id)
		_subjects.append(_spawn_subject(id, i, count))
	_fit_attempts = 0
	_refresh_mode()
	_refresh()

func clear_subjects() -> void:
	for node in _subjects:
		if is_instance_valid(node):
			node.queue_free()
	_subjects.clear()
	_ids.clear()
	_fit_distance = 0.0
	_render_window = 0
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)

func _spawn_subject(id: String, index: int, count: int) -> Node3D:
	# ONE construction path: FighterPresentationFactory resolves the id (roster
	# fighter or specialized encounter enemy such as Bobo) and builds it.
	var subject: Node3D = Factory.build_subject(id, _palette)
	_stage.add_child(subject)
	Factory.prepare_subject(subject, id)
	subject.position = Factory.team_offset(index, count) if _profile_name == PROFILE_RESULTS_TEAM else Vector3.ZERO
	subject.rotation_degrees = Vector3(0.0, BASE_YAW_DEG, 0.0)
	return subject

func subjects() -> Array[String]:
	return _ids.duplicate()

func subject_nodes() -> Array[Node3D]:
	return _subjects.duplicate()

func subject_scripts() -> Array[String]:
	var out: Array[String] = []
	for subject in _subjects:
		var script: Script = subject.get_script() if is_instance_valid(subject) else null
		out.append(str(script.resource_path) if script != null else "")
	return out

func get_subject_count() -> int:
	return _subjects.size()

func has_subjects() -> bool:
	return not _subjects.is_empty()

# --- rendering -------------------------------------------------------------

func request_render() -> void:
	_build_stage()
	if is_animating():
		return                      # live views already update every frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_render_window = maxi(_render_window, RENDER_WINDOW)
	set_process(true)

func update_mode() -> int:
	return _viewport.render_target_update_mode if _viewport != null else -1

func set_sway_enabled(value: bool) -> void:
	_sway_enabled = value

func render_target() -> Texture2D:
	_build_stage()
	return _viewport.get_texture()

func texture_rect() -> TextureRect:
	_build_stage()
	return _target

func texture_fit_mode() -> int:
	# The image fit mode, asserted by API (Doc 07 §4): containment, never a
	# destructive cover crop.
	_build_stage()
	return _target.stretch_mode

func view() -> SubViewport:
	_build_stage()
	return _viewport

func pose_ready() -> bool:
	# The deterministic pose is presentable: every subject built a visible
	# model and the camera fit has been computed.
	if not has_subjects():
		return false
	if _fit_distance <= 0.01:
		return false
	for subject in _subjects:
		if not is_instance_valid(subject):
			return false
	return model_aabb().size.length() > MIN_HONEST_AABB

func pose_signature() -> Dictionary:
	# Deterministic pose fingerprint: identical across frames for STATIC_POSE
	# (and across stopped states), so "stops mid-animation" is directly
	# assertable. Yaws/positions/sway are rounded to avoid float noise.
	var yaws: Array = []
	var positions: Array = []
	var playing := 0
	for i in _subjects.size():
		var subject := _subjects[i]
		if not is_instance_valid(subject):
			continue
		yaws.append(snappedf(subject.rotation_degrees.y, 0.01))
		positions.append(Vector3(
			snappedf(subject.position.x, 0.01),
			snappedf(subject.position.y, 0.01),
			snappedf(subject.position.z, 0.01)))
		for player in _animation_players(subject):
			if player.is_playing():
				playing += 1
	var box := framed_box()
	return {
		"mode": presentation_mode_name(),
		"animating": is_animating(),
		"sway": snappedf(_sway, 0.001),
		"yaws": yaws,
		"positions": positions,
		"playing": playing,
		"fit": snappedf(_fit_distance, 0.001),
		"size": [render_size().x, render_size().y],
		"box": [snappedf(box.position.x, 0.01), snappedf(box.position.y, 0.01), snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01)],
	}

func _refresh() -> void:
	if not has_subjects():
		_fit_distance = 0.0
		return
	_fit_attempts = 0
	frame_model()
	request_render()

# --- framing (factory math: measured silhouette windows) -------------------

func model_aabb() -> AABB:
	# Only REAL visible meshes count: fighters carry hidden helper subtrees
	# (frozen shell, sphere shell, wave rings) whose boxes are far larger than
	# the silhouette. The old local `visible` check was fooled by helpers whose
	# own flag stayed true while an ancestor hid them (probe: sphere shell /
	# wave rings), which polluted every measurement — the ancestor walk fixes
	# it. Skinned GLB meshes report their bind AABB, which is not a silhouette:
	# when the measured box is degenerate, the factory's measured silhouette
	# box is the honest result.
	var result := _visible_mesh_aabb()
	if result.size.length() < MIN_HONEST_AABB and not _ids.is_empty():
		return Factory.silhouette_box(_ids[0])
	return result

func _visible_mesh_aabb() -> AABB:
	var result := AABB()
	var first := true
	for subject in _subjects:
		if not is_instance_valid(subject):
			continue
		for node in subject.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node
			if mesh.mesh == null or not mesh.visible:
				continue
			if not _effective_visible(mesh, subject):
				continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if first:
				result = box
				first = false
			else:
				result = result.merge(box)
	return result

func _effective_visible(node: Node, stop: Node) -> bool:
	# Ancestor-aware visibility (SubViewport-safe): the node and every ancestor
	# up to the subject must be visible.
	var current: Node = node
	while current != null and current != stop:
		if current is Node3D and not (current as Node3D).visible:
			return false
		current = current.get_parent()
	return true

func frame_model() -> void:
	if not has_subjects():
		return
	var cfg := profile_config()
	var box: AABB = framed_box()
	var center := Factory.aim_center(box, cfg)
	var vp := render_size()
	var aspect := maxf(float(vp.x) / maxf(float(vp.y), 1.0), 0.5)
	var forward := Factory.camera_forward(cfg)
	_fit_distance = Factory.fit_distance(box, cfg, aspect)
	_camera.position = center + forward * _fit_distance
	_camera.look_at(center, Vector3.UP)

func framed_box() -> AABB:
	# Single subject: its own measured window. RESULTS_TEAM: union of each
	# subject's window placed at its offset.
	return Factory.box_for(_ids, _profile_name)

func _fighter_box(id: String) -> AABB:
	return Factory.framed_box(id, _profile_name)

func get_fit_distance() -> float:
	return _fit_distance

# --- per-frame (only while fitting / pose arrival / live) ------------------

func _process(delta: float) -> void:
	# A live presentation that is no longer visible — including an ancestor
	# hiding it, which fires no visibility_changed on this node — parks itself:
	# no updates, pose frozen. Hidden views cost nothing (Doc 07 §2/§3).
	if _mode == MODE_LIVE_IDLE and not _is_presented():
		_park()
		return
	var working := false
	# Self-healing fit: a character's meshes can arrive a frame after the
	# instance (deferred visual setup), so retry until the camera is placed.
	if has_subjects() and _fit_distance <= 0.01 and _fit_attempts < FIT_ATTEMPTS:
		_fit_attempts += 1
		frame_model()
		request_render()
		working = true
	if is_animating():
		if _sway_enabled and has_subjects():
			_sway += delta
			var wave := sin(TAU * _sway / SWAY_SECONDS)
			for subject in _subjects:
				if is_instance_valid(subject):
					subject.rotation_degrees = Vector3(0.0, BASE_YAW_DEG + wave * SWAY_DEG, 0.0)
		set_process(true)
		return
	if _render_window > 0:
		# Late-mesh frames of the SAME frozen pose (never an animation settle).
		_render_window -= 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		working = true
	if not working:
		# Static view settled: zero per-frame cost until the next change.
		if not is_animating():
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)

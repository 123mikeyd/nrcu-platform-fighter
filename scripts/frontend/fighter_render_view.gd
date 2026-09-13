class_name FighterRenderView
extends Control
# FighterRenderView — the ONE reusable fighter-presentation system (Doc 01 §21,
# Doc 09 §16), generalizing the proven hero_rig.gd camera-fit math instead of
# duplicating it. One instance owns exactly one SubViewport with its own world,
# one Environment and one lighting rig; subjects are real Fighter instances
# with physics/controls disabled and HUD Label3Ds hidden (same instantiation
# rules as hero_rig.gd).
#
# Profiles (Doc 09 §16):
#   PORTRAIT      head/upper torso bust, tight, square target (offline portrait
#                 generation source — Doc 04 §7);
#   PLAYER_BAY    full body, consistent floor line (the four lower stations);
#   RESULTS_HERO  one large winner presentation;
#   RESULTS_TEAM  group shot: several fighters on small horizontal offsets,
#                 framed on the combined AABB with ONE camera/light rig.
#
# Update policy (Doc 01 §21/§28, Doc 04 §11): render-on-change. The SubViewport
# is UPDATE_ONCE (one frame, then Godot parks it at UPDATE_DISABLED); the view
# keeps requesting frames for a short settle window so late-arriving meshes are
# captured, then stops processing entirely. UPDATE_ALWAYS happens ONLY through
# set_live(true) — reserved for a deliberate animated hero, never a roster of
# live viewports.
#
# Framing is computed from the canonical silhouette box (measured once for the
# shared skeleton), so every fighter gets the same confident composition and
# floor line without per-fighter coordinate tables. FRAME_OVERRIDES holds only
# the entries a rendered silhouette proved necessary (Doc 01 §21).

const FighterScript = preload("res://scripts/fighter.gd")
const Roster = preload("res://scripts/roster.gd")

const PROFILE_PORTRAIT := "PORTRAIT"
const PROFILE_PLAYER_BAY := "PLAYER_BAY"
const PROFILE_RESULTS_HERO := "RESULTS_HERO"
const PROFILE_RESULTS_TEAM := "RESULTS_TEAM"
const PROFILE_ORDER := [PROFILE_PORTRAIT, PROFILE_PLAYER_BAY, PROFILE_RESULTS_HERO, PROFILE_RESULTS_TEAM]

# Canonical silhouette box, measured from the rendered build (feet ~0.19,
# head/detail top ~2.79 units; every fighter shares the capsule+head skeleton).
const MODEL_BOX := AABB(Vector3(-0.75, 0.15, -0.75), Vector3(1.5, 2.7, 1.5))
# Head + upper torso crop for PORTRAIT (bust identity, Doc 04 §6.1).
const PORTRAIT_BOX := AABB(Vector3(-0.75, 1.42, -0.75), Vector3(1.5, 1.43, 1.5))
# Per-fighter framing override: only entries a rendered silhouette PROVED
# necessary (Doc 01 §21). Two measured facts drove this table:
#  1. The six humanoids do NOT share a silhouette top: measured bust tops run
#     1.88 (teknium) to 2.36 (turbofit) world units, so one canonical PORTRAIT
#     box framed a small head at the bottom of the tile with ~60% empty space.
#  2. GGB is off the shared skeleton entirely: ~0.91 units tall (posed height,
#     tests/test_character_grounding_scale.gd) and ~1.4 units wide with wings.
# PORTRAIT windows are measured bust crops (window 0.93 units tall — head plus
# upper torso — with the silhouette top ~30% below the frame top, so the tile's
# cover-crop keeps the whole head clear of the frame edge). Numbers are
# calibrated offline against a PLAYER_BAY render pass and the posed-bounds
# heights (the calibration reproduced the four known heights within ±0.02).
# The other profiles keep the canonical boxes; only GGB needs a structural
# override there.
const FRAME_OVERRIDES := {
	"teknium": {PROFILE_PORTRAIT: AABB(Vector3(-0.62, 1.23, -0.62), Vector3(1.24, 0.93, 1.24))},
	"doge_man": {PROFILE_PORTRAIT: AABB(Vector3(-0.62, 1.34, -0.62), Vector3(1.24, 0.93, 1.24))},
	"witcheer": {PROFILE_PORTRAIT: AABB(Vector3(-0.62, 1.34, -0.62), Vector3(1.24, 0.93, 1.24))},
	"mephisto": {PROFILE_PORTRAIT: AABB(Vector3(-0.62, 1.47, -0.62), Vector3(1.24, 0.93, 1.24))},
	"ice_mage": {PROFILE_PORTRAIT: AABB(Vector3(-0.80, 1.47, -0.80), Vector3(1.60, 0.93, 1.60))},
	"turbofit": {PROFILE_PORTRAIT: AABB(Vector3(-0.62, 1.71, -0.62), Vector3(1.24, 0.93, 1.24))},
	"ggb": {
		# Whole mascot: its face IS the body, so the portrait frames the full cube.
		PROFILE_PORTRAIT: AABB(Vector3(-0.72, 0.05, -0.72), Vector3(1.44, 0.93, 1.44)),
		PROFILE_PLAYER_BAY: AABB(Vector3(-0.72, 0.00, -0.72), Vector3(1.44, 0.98, 1.44)),
		PROFILE_RESULTS_HERO: AABB(Vector3(-0.72, 0.00, -0.72), Vector3(1.44, 0.98, 1.44)),
		PROFILE_RESULTS_TEAM: AABB(Vector3(-0.72, 0.00, -0.72), Vector3(1.44, 0.98, 1.44)),
	},
}
const BASE_YAW_DEG := -22.0
const TEAM_SPACING := 1.7          # horizontal offset between team subjects
const SETTLE_FRAMES := 12          # render-requests after a change (late meshes)
const FIT_ATTEMPTS := 120          # self-healing camera fit bound (as hero_rig)
const SWAY_DEG := 3.5              # live-only ambient motion, own clock
const SWAY_SECONDS := 7.0

const PROFILES := {
	PROFILE_PORTRAIT: {
		"box": PORTRAIT_BOX, "fit_margin": 1.10, "aim_offset_y": 0.0,
		"render_size": Vector2i(320, 240), "angle_deg": 14.0, "elev_deg": 6.0, "fov": 32.0,
	},
	PROFILE_PLAYER_BAY: {
		"box": MODEL_BOX, "fit_margin": 1.12, "aim_offset_y": 0.07,
		"render_size": Vector2i(512, 384), "angle_deg": 18.0, "elev_deg": 12.0, "fov": 32.0,
	},
	PROFILE_RESULTS_HERO: {
		"box": MODEL_BOX, "fit_margin": 1.04, "aim_offset_y": 0.07,
		"render_size": Vector2i(640, 540), "angle_deg": 20.0, "elev_deg": 10.0, "fov": 30.0,
	},
	PROFILE_RESULTS_TEAM: {
		"box": MODEL_BOX, "fit_margin": 1.08, "aim_offset_y": 0.07,
		"render_size": Vector2i(1024, 512), "angle_deg": 10.0, "elev_deg": 10.0, "fov": 30.0,
	},
}

var _profile_name := PROFILE_PLAYER_BAY
var _palette := 0
var _ids: Array[String] = []
var _subjects: Array[Node3D] = []
var _live := false
var _sway_enabled := true
var _sway := 0.0
var _settle_frames := 0
var _fit_attempts := 0
var _fit_distance := 0.0

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
	_target.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	var name := _profile_key(profile)
	if name == "":
		push_error("FighterRenderView: unknown profile %s" % str(profile))
		return
	_profile_name = name
	_apply_profile()
	_refresh()

func profile_name() -> String:
	return _profile_name

func _profile_key(profile) -> String:
	if typeof(profile) == TYPE_STRING:
		var key := String(profile).to_upper()
		return key if PROFILES.has(key) else ""
	if typeof(profile) == TYPE_INT and int(profile) >= 0 and int(profile) < PROFILE_ORDER.size():
		return PROFILE_ORDER[int(profile)]
	return ""

func _apply_profile() -> void:
	var cfg: Dictionary = PROFILES[_profile_name]
	_camera.fov = float(cfg["fov"])
	_viewport.size = cfg["render_size"]
	_fit_distance = 0.0
	_fit_attempts = 0

func set_render_size(size_px: Vector2i) -> void:
	_build_stage()
	_viewport.size = Vector2i(maxi(size_px.x, 8), maxi(size_px.y, 8))

func render_size() -> Vector2i:
	return _viewport.size if _viewport != null else Vector2i.ZERO

func set_palette(index: int) -> void:
	_palette = index
	for i in _subjects.size():
		if is_instance_valid(_subjects[i]):
			_subjects[i].body_color = Roster.palette(_ids[i], _palette)
	_refresh()

func palette_index() -> int:
	return _palette

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
	_refresh()

func clear_subjects() -> void:
	for node in _subjects:
		if is_instance_valid(node):
			node.queue_free()
	_subjects.clear()
	_ids.clear()
	_fit_distance = 0.0

func _spawn_subject(id: String, index: int, count: int) -> Node3D:
	var fighter = FighterScript.new()
	fighter.character_id = id
	fighter.fighter_name = Roster.display_name(id).to_upper()
	fighter.body_color = Roster.palette(id, _palette)
	fighter.controls_enabled = false
	_stage.add_child(fighter)
	# UI subjects never participate in gameplay: out of the fighters group,
	# no collision, no physics.
	fighter.remove_from_group("fighters")
	fighter.collision_layer = 0
	fighter.collision_mask = 0
	fighter.set_physics_process(false)
	# HUD-only children (player tag, move-status text) never belong on a UI model.
	for node in fighter.find_children("*", "Label3D", true, false):
		var label: Label3D = node
		label.hide()
	fighter.position = _team_offset(index, count) if _profile_name == PROFILE_RESULTS_TEAM else Vector3.ZERO
	fighter.rotation_degrees = Vector3(0.0, BASE_YAW_DEG, 0.0)
	return fighter

func _team_offset(index: int, count: int) -> Vector3:
	if count <= 1:
		return Vector3.ZERO
	return Vector3((index - (count - 1) * 0.5) * TEAM_SPACING, 0.0, 0.0)

func subjects() -> Array[String]:
	return _ids.duplicate()

func subject_nodes() -> Array[Node3D]:
	return _subjects.duplicate()

func get_subject_count() -> int:
	return _subjects.size()

func has_subjects() -> bool:
	return not _subjects.is_empty()

# --- rendering -------------------------------------------------------------

func request_render() -> void:
	_build_stage()
	if _live:
		return                      # live views already update every frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	set_process(true)

func set_live(enabled: bool) -> void:
	_build_stage()
	_live = enabled
	if enabled:
		# Deliberate animated presentation only (Doc 01 §21). Never the default.
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		set_process(true)
	else:
		_sway = 0.0
		_settle_frames = maxi(_settle_frames, SETTLE_FRAMES)
		request_render()

func is_live() -> bool:
	return _live

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

func view() -> SubViewport:
	_build_stage()
	return _viewport

func _refresh() -> void:
	if not has_subjects():
		_fit_distance = 0.0
		return
	_fit_attempts = 0
	_settle_frames = maxi(_settle_frames, SETTLE_FRAMES)
	frame_model()
	request_render()

# --- framing (hero_rig camera-fit math, parameterized by profile) ---------

func model_aabb() -> AABB:
	# Only VISIBLE meshes count: fighters carry hidden helpers (attack flash,
	# frozen shell, wave rings) whose boxes are far larger than the silhouette.
	var result := AABB()
	if not has_subjects():
		return result
	var first := true
	for subject in _subjects:
		if not is_instance_valid(subject):
			continue
		for node in subject.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node
			if mesh.mesh == null or not mesh.visible:
				continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if first:
				result = box
				first = false
			else:
				result = result.merge(box)
	return result

func frame_model() -> void:
	if not has_subjects():
		return
	var box: AABB = framed_box()
	var cfg: Dictionary = PROFILES[_profile_name]
	var center := box.get_center() + Vector3(0.0, float(cfg["aim_offset_y"]), 0.0)
	var vfov := deg_to_rad(_camera.fov)
	var vp := render_size()
	var aspect := maxf(float(vp.x) / maxf(float(vp.y), 1.0), 0.5)
	var forward := Vector3(
		sin(deg_to_rad(float(cfg["angle_deg"]))),
		sin(deg_to_rad(float(cfg["elev_deg"]))),
		cos(deg_to_rad(float(cfg["angle_deg"])))).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	var half_w := 0.0
	var half_h := 0.0
	for xi in 2:
		for yi in 2:
			for zi in 2:
				var corner := box.position + Vector3(
					box.size.x * xi, box.size.y * yi, box.size.z * zi)
				var offset := corner - center
				half_w = maxf(half_w, absf(offset.dot(right)))
				half_h = maxf(half_h, absf(offset.dot(up)))
	var dist_v := half_h / tan(vfov * 0.5)
	var dist_h := half_w / (tan(vfov * 0.5) * aspect)
	_fit_distance = maxf(dist_v, dist_h) * float(cfg["fit_margin"])
	_camera.position = center + forward * _fit_distance
	_camera.look_at(center, Vector3.UP)

func framed_box() -> AABB:
	# Single subject: canonical box (per-fighter override if one exists).
	# RESULTS_TEAM: union of each subject's box placed at its offset.
	var box: AABB = _fighter_box(_ids[0] if _ids.size() > 0 else "")
	if _ids.size() == 1:
		return box
	var combined := AABB()
	var first := true
	for i in _ids.size():
		var per: AABB = _fighter_box(_ids[i])
		var moved := AABB(per.position + _team_offset(i, _ids.size()), per.size)
		if first:
			combined = moved
			first = false
		else:
			combined = combined.merge(moved)
	return combined

func _fighter_box(id: String) -> AABB:
	var base: AABB = PROFILES[_profile_name]["box"]
	var table = FRAME_OVERRIDES.get(id, null)
	if typeof(table) == TYPE_DICTIONARY and table.has(_profile_name):
		return table[_profile_name]
	return base

func get_fit_distance() -> float:
	return _fit_distance

# --- per-frame (only while settling / fitting / live) ----------------------

func _process(delta: float) -> void:
	var working := false
	if has_subjects() and _fit_distance <= 0.01 and _fit_attempts < FIT_ATTEMPTS:
		_fit_attempts += 1
		frame_model()
		request_render()
		working = true
	if _settle_frames > 0:
		_settle_frames -= 1
		request_render()
		working = true
	if _live and _sway_enabled and has_subjects():
		_sway += delta
		var wave := sin(TAU * _sway / SWAY_SECONDS)
		for subject in _subjects:
			if is_instance_valid(subject):
				subject.rotation_degrees = Vector3(0.0, BASE_YAW_DEG + wave * SWAY_DEG, 0.0)
		working = true
	if not working:
		# Static view settled: zero per-frame cost until the next change.
		set_process(false)

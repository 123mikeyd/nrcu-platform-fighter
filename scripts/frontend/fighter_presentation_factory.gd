class_name FighterPresentationFactory
extends RefCounted
# FighterPresentationFactory — corrective package WP-3 (Doc 07 §2/§4/§5/§6/§7,
# Doc 09 WP-3; ledger RC-D, C-045, C-046, C-048, S-003).
#
# THE one place that resolves a fighter id into a presentation subject and
# everything the presentation paths need to render it:
#   * subject resolution  (roster fighter OR specialized encounter enemy, e.g.
#                         Bobo builds scripts/bobo_fighter.gd's BoboVisual rig);
#   * rig construction    (build_subject/prepare_subject: the ONE construction
#                         path shared by PlayerBay, CSS candidate preview,
#                         Story briefing, Results hero and portrait generation —
#                         no screen grows its own fighter-construction logic);
#   * palette policy      (read from FighterCatalog for roster ids; encounter
#                         subjects own their visuals);
#   * per-fighter optical framing (measured silhouette table + profile window
#                         rules — the hero_rig camera-fit math lives here once);
#   * presentation modes  (STATIC_POSE / LIVE_IDLE — deliberate, never a
#                         settle/freeze hybrid);
#   * render density      (destination aspect + displayed physical pixels ->
#                         SubViewport size within profile caps);
#   * live-viewport budget (how many views may update at once, measured policy);
#   * portrait spec       (deterministic STATIC_POSE inputs for tools/portrait_gen.gd).
#
# Contract: static functions only, no scene access, no side effects, and every
# read returns fresh data (never shared mutable state — same rule as the
# catalogs). Unknown ids resolve to the generic roster fighter and the
# canonical silhouette, so a future id can never crash a screen.

const Roster = preload("res://scripts/roster.gd")
const Catalog = preload("res://scripts/catalogs/fighter_catalog.gd")
const FighterScript = preload("res://scripts/fighter.gd")

const FIGHTER_SCRIPT_PATH := "res://scripts/fighter.gd"
const ENCOUNTER_SCRIPT_PATH := "res://scripts/bobo_fighter.gd"

# --- presentation modes (Doc 07 §2) ----------------------------------------
# Only two production modes exist. There is no third "settle" state: a view is
# either deliberately posed (STATIC_POSE, rendered once, tree frozen) or
# deliberately alive (LIVE_IDLE, updates while visible). The old
# "animate for 12 rendered frames then stop" hybrid is deleted.
enum Mode { STATIC_POSE, LIVE_IDLE }
const MODE_STATIC_POSE := Mode.STATIC_POSE
const MODE_LIVE_IDLE := Mode.LIVE_IDLE

const PROFILE_PORTRAIT := "PORTRAIT"
const PROFILE_PLAYER_BAY := "PLAYER_BAY"
const PROFILE_RESULTS_HERO := "RESULTS_HERO"
const PROFILE_RESULTS_TEAM := "RESULTS_TEAM"
const PROFILE_ORDER := [PROFILE_PORTRAIT, PROFILE_PLAYER_BAY, PROFILE_RESULTS_HERO, PROFILE_RESULTS_TEAM]

const BASE_YAW_DEG := -22.0        # neutral stance toward the camera
const TEAM_SPACING := 1.7          # horizontal offset between team subjects

# --- measured silhouettes (Doc 07 §6) ---------------------------------------
# Posed silhouette bounds per subject in fighter-local units (x=half width,
# y=sole..top), measured from the rendered build via the shared posed-bounds
# method (tests/posed_character_bounds.gd; probe: tools/silhouette_probe.gd).
# These are the "own measured silhouette" the camera fits: each subject fills
# the SAME share of the frame instead of sharing one AABB that over-frames
# short fighters (GGB) and under-frames tall ones (TurboFit).
const SILHOUETTE := {
	"teknium": {"top": 1.896, "sole": 0.003, "half_width": 0.649},
	"doge_man": {"top": 1.993, "sole": 0.077, "half_width": 0.637},
	"ggb": {"top": 0.916, "sole": 0.010, "half_width": 0.676},
	"turbofit": {"top": 2.381, "sole": 0.057, "half_width": 0.343},
	"ice_mage": {"top": 2.335, "sole": 0.065, "half_width": 0.723},
	"witcheer": {"top": 2.001, "sole": 0.058, "half_width": 0.618},
	"mephisto": {"top": 2.118, "sole": 0.056, "half_width": 0.503},
	"bobo": {"top": 2.730, "sole": 0.000, "half_width": 1.171},
}
# Fallback for ids with no measurement yet (future encounters): the canonical
# capsule+head skeleton window the original renderer composed against.
const CANONICAL_SILHOUETTE := {"top": 2.79, "sole": 0.19, "half_width": 0.75}

# --- profiles (framing rules + camera + density caps, Doc 07 §5) -----------
# "box" is the canonical fallback window for unmeasured ids; measured ids are
# derived from SILHOUETTE + the profile's "window" rule:
#   bust  -> fixed bust height, the head top sits top_clearance of the window
#            below the frame top (head clearance, Doc 07 §6);
#   full  -> sole floor line..head top + head_clearance (consistent floor line);
# every window is widened to min_width and kept inside [min_aspect, max_aspect]
# (crop tolerance: a very wide box would waste frame, a very narrow one would
# clip arms).
const PROFILES := {
	PROFILE_PORTRAIT: {
		"box": AABB(Vector3(-0.75, 1.42, -0.75), Vector3(1.5, 1.43, 1.5)),
		"window": {"mode": "bust", "height": 0.93, "top_clearance": 0.30,
			"min_width": 1.24, "min_aspect": 0.55, "max_aspect": 2.60},
		"fit_margin": 1.10, "aim_offset_y": 0.0,
		"angle_deg": 14.0, "elev_deg": 6.0, "fov": 32.0,
		"render_size": Vector2i(320, 240),
		"min_size": Vector2i(160, 96), "max_size": Vector2i(1024, 1024), "max_area": 786432,
	},
	PROFILE_PLAYER_BAY: {
		"box": AABB(Vector3(-0.75, 0.15, -0.75), Vector3(1.5, 2.7, 1.5)),
		"window": {"mode": "full", "floor": 0.0, "head_clearance": 0.14,
			"min_width": 1.5, "min_aspect": 0.50, "max_aspect": 2.40},
		"fit_margin": 1.12, "aim_offset_y": 0.07,
		"angle_deg": 18.0, "elev_deg": 12.0, "fov": 32.0,
		"render_size": Vector2i(512, 384),
		"min_size": Vector2i(256, 144), "max_size": Vector2i(1440, 960), "max_area": 1024000,
	},
	PROFILE_RESULTS_HERO: {
		"box": AABB(Vector3(-0.75, 0.15, -0.75), Vector3(1.5, 2.7, 1.5)),
		"window": {"mode": "full", "floor": 0.0, "head_clearance": 0.14,
			"min_width": 1.5, "min_aspect": 0.50, "max_aspect": 2.40},
		"fit_margin": 1.04, "aim_offset_y": 0.07,
		"angle_deg": 20.0, "elev_deg": 10.0, "fov": 30.0,
		"render_size": Vector2i(640, 540),
		"min_size": Vector2i(256, 192), "max_size": Vector2i(1280, 960), "max_area": 1228800,
	},
	PROFILE_RESULTS_TEAM: {
		"box": AABB(Vector3(-0.75, 0.15, -0.75), Vector3(1.5, 2.7, 1.5)),
		"window": {"mode": "full", "floor": 0.0, "head_clearance": 0.14,
			"min_width": 1.5, "min_aspect": 0.50, "max_aspect": 2.40},
		"fit_margin": 1.08, "aim_offset_y": 0.07,
		"angle_deg": 10.0, "elev_deg": 10.0, "fov": 30.0,
		"render_size": Vector2i(1024, 512),
		"min_size": Vector2i(384, 192), "max_size": Vector2i(2048, 1024), "max_area": 2097152,
	},
}

# Measured framing overrides: only the entries a rendered silhouette PROVED
# necessary (Doc 01 §21). Two measured facts drove this table:
#  1. GGB's face IS the body, so its portrait frames the whole cube, not a
#     humanoid bust window;
#  2. Ice Mage's detail spread (hat/staff) needs a wider, higher window than
#     the derived bust rule produces.
# The other six windows are derived from each fighter's own measured
# silhouette (the derivation reproduces the shipped calibrated windows within
# +/-0.02, verified by tests/test_fighter_presentation.gd).
const FRAME_OVERRIDES := {
	"ggb": {
		PROFILE_PORTRAIT: AABB(Vector3(-0.72, 0.05, -0.72), Vector3(1.44, 0.93, 1.44)),
	},
	"ice_mage": {
		PROFILE_PORTRAIT: AABB(Vector3(-0.80, 1.47, -0.80), Vector3(1.60, 0.93, 1.60)),
	},
}

# --- specialized encounter subjects (Doc 07 §7; ledger S-003) --------------
# Every frontend subject is NOT a generic Fighter. Bobo is the first
# specialized enemy: his id resolves to scripts/bobo_fighter.gd, whose
# _build_visuals installs BoboVisual (assets/bobo/bobo.glb), so the shared
# FighterRenderView renders him in 3D instead of falling back to a nameplate.
# The nameplate stays ONLY as a defensive fallback path and is asserted not to
# trigger in the Story briefing (tests/test_fighter_presentation.gd).
const ENCOUNTERS := {
	"bobo": {
		"id": "bobo",
		"kind": "encounter",
		"display_name": "Bobo",
		"script_path": ENCOUNTER_SCRIPT_PATH,
		"visual_module": "res://scripts/bobo_visual.gd",
		"presentation_key": "bobo",
		# Approved UI idle clip (LIVE_IDLE only): BoboVisual drives his GLB
		# AnimationPlayer; STATIC_POSE freezes it at t=0 instead.
		"ui_idle_clip": "Idle",
		# Encounter subjects own their visuals: no slot palette is applied
		# (Roster.palette has no hue for an encounter id; assigning one would
		# tint a painted GLB).
		"palette_policy": {
			"policy": "visual_owned",
			"source": "res://scripts/bobo_visual.gd",
			"preserves_painted_materials": true,
			"slot_variants": 1,
		},
	},
}

# --- live-viewport budget (Doc 07 §3/§9; ledger C-046/C-048) ---------------
# Production policy, until the parent's windowed performance matrix (720p/
# 1080p/1440p, 4 occupied bays) proves headroom for more:
#   CSS      active bay viewport updates; every other occupied bay is
#            STATIC_POSE (the documented performance fallback, Doc 04 §12);
#   Story    enemy hero + selected fighter (2) update while the briefing is
#            visible; hidden views stop;
#   Results  ONE viewport (team = one viewport with N subjects);
#   HowTo    ONE inspected-fighter viewport;
#   roster   static 2D PNGs, never a live viewport.
# => at most LIVE_VIEW_BUDGET viewports update at once on a production screen.
const LIVE_VIEW_BUDGET := 2

const DEFAULT_QUALITY_SCALE := 1.0
const QUALITY_MIN := 0.5
const QUALITY_MAX := 2.0
const CONTENT_SCALE_MIN := 0.25
const CONTENT_SCALE_MAX := 4.0
const ASPECT_MIN := 0.5
const ASPECT_MAX := 4.0
const DENSITY_HYSTERESIS_PX := 2   # reallocate only on meaningful size changes

# --- resolution -------------------------------------------------------------

static func roster_ids() -> Array[String]:
	return Roster.ids()

static func encounter_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ENCOUNTERS.keys():
		out.append(str(id))
	return out

static func all_ids() -> Array[String]:
	var out: Array[String] = roster_ids()
	for id in encounter_ids():
		if not out.has(id):
			out.append(id)
	return out

static func has(id: String) -> bool:
	return id != "" and (Catalog.has(id) or ENCOUNTERS.has(id))

static func is_encounter(id: String) -> bool:
	return ENCOUNTERS.has(id)

static func resolve(id: String) -> Dictionary:
	# fighter id -> presentation subject. Roster ids keep their FighterCatalog
	# identity; encounter ids resolve to their specialized rig script.
	if id == "":
		return {}
	var encounter = ENCOUNTERS.get(id, null)
	if typeof(encounter) == TYPE_DICTIONARY:
		var entry: Dictionary = encounter
		return {
			"id": id,
			"kind": "encounter",
			"display_name": str(entry["display_name"]),
			"script_path": str(entry["script_path"]),
			"visual_module": str(entry.get("visual_module", "")),
			"presentation_key": str(entry.get("presentation_key", id)),
			"ui_idle_clip": str(entry.get("ui_idle_clip", "")),
			"portrait_path": "",
			"palette_policy": entry["palette_policy"].duplicate(true),
		}
	var catalog_entry: Dictionary = Catalog.by_id(id)
	if not catalog_entry.is_empty():
		var presentation: Dictionary = catalog_entry["presentation"]
		return {
			"id": id,
			"kind": "roster",
			"display_name": str(catalog_entry["display_name"]),
			"script_path": FIGHTER_SCRIPT_PATH,
			"visual_module": str(presentation["visual_module"]),
			"presentation_key": str(presentation["key"]),
			"ui_idle_clip": "",   # roster views use the view-owned approved idle
			"portrait_path": str(catalog_entry["portrait_path"]),
			"palette_policy": catalog_entry["palette_policy"].duplicate(true),
		}
	# Unknown id: the generic roster fighter + canonical silhouette (never a
	# screen-local fallback, never a crash).
	return {
		"id": id,
		"kind": "unknown",
		"display_name": Roster.display_name(id),
		"script_path": FIGHTER_SCRIPT_PATH,
		"visual_module": "",
		"presentation_key": id,
		"ui_idle_clip": "",
		"portrait_path": "",
		"palette_policy": {"policy": "roster_slot_hue", "source": "res://scripts/roster.gd#palette"},
	}

static func subject_script(id: String) -> GDScript:
	var resolution := resolve(id)
	var path := str(resolution.get("script_path", FIGHTER_SCRIPT_PATH))
	var script := load(path)
	return script if script is GDScript else FighterScript

static func display_name(id: String) -> String:
	var resolution := resolve(id)
	return str(resolution.get("display_name", Roster.display_name(id)))

static func ui_idle_clip(id: String) -> String:
	var resolution := resolve(id)
	return str(resolution.get("ui_idle_clip", ""))

static func palette_policy(id: String) -> Dictionary:
	var resolution := resolve(id)
	var policy = resolution.get("palette_policy", {})
	return policy if typeof(policy) == TYPE_DICTIONARY else {}

# --- palette identity (Doc 04 §14 / Doc 02 §8 palette policy) ---------------

static func palette_for(id: String, slot_index: int) -> Color:
	# Roster ids keep roster.gd as the single live colour source (the catalog's
	# palette_policy records the same numbers as provenance); encounter subjects
	# own their painted visuals, so no slot colour is applied.
	var policy := palette_policy(id)
	if str(policy.get("policy", "")) == "visual_owned":
		return Color(1, 1, 1, 1)
	return Roster.palette(id, slot_index)

static func apply_palette(subject: Node, id: String, slot_index: int) -> void:
	if subject == null or not is_instance_valid(subject):
		return
	var policy := palette_policy(id)
	if str(policy.get("policy", "")) == "visual_owned":
		return   # the subject's own visual module owns its painted materials
	if subject.get("body_color") == null:
		return
	subject.set("body_color", palette_for(id, slot_index))

# --- rig construction (the ONE construction path) ---------------------------

static func build_subject(id: String, palette_index := 0) -> Node3D:
	# Constructs the resolved presentation subject with its identity applied.
	# The caller owns where it lives (a render stage / SubViewport world).
	var resolution := resolve(id)
	var node: Node3D = subject_script(id).new()
	if node.get("character_id") != null:
		node.set("character_id", id)
	if node.get("fighter_name") != null:
		node.set("fighter_name", str(resolution.get("display_name", id)).to_upper())
	if node.get("controls_enabled") != null:
		node.set("controls_enabled", false)
	apply_palette(node, id, palette_index)
	return node

static func prepare_subject(node: Node3D, id: String) -> void:
	# UI subjects never participate in gameplay and never carry HUD layers.
	if node == null or not is_instance_valid(node):
		return
	node.remove_from_group("fighters")
	node.collision_layer = 0
	node.collision_mask = 0
	node.set_physics_process(false)
	for child in node.find_children("*", "Label3D", true, false):
		var label: Label3D = child
		label.hide()
	node.rotation_degrees = Vector3(0.0, BASE_YAW_DEG, 0.0)

# --- framing (measured silhouette -> profile window -> camera fit) ----------

static func silhouette(id: String) -> Dictionary:
	var measured = SILHOUETTE.get(id, null)
	if typeof(measured) == TYPE_DICTIONARY:
		return (measured as Dictionary).duplicate(true)
	return CANONICAL_SILHOUETTE.duplicate(true)

static func silhouette_box(id: String) -> AABB:
	# Honest local-space bounds of the measured silhouette (used when a skinned
	# mesh cannot report a real AABB — GLB meshes report their bind box).
	var sil := silhouette(id)
	var half := float(sil["half_width"])
	var sole := float(sil["sole"])
	var top := float(sil["top"])
	return AABB(Vector3(-half, sole, -half), Vector3(half * 2.0, top - sole, half * 2.0))

static func profile_config(profile: String) -> Dictionary:
	var cfg = PROFILES.get(profile, null)
	return (cfg as Dictionary).duplicate(true) if typeof(cfg) == TYPE_DICTIONARY else {}

static func profile_name(value) -> String:
	if typeof(value) == TYPE_STRING:
		var key := String(value).to_upper()
		return key if PROFILES.has(key) else ""
	if typeof(value) == TYPE_INT and int(value) >= 0 and int(value) < PROFILE_ORDER.size():
		return str(PROFILE_ORDER[int(value)])
	return ""

static func framed_box(id: String, profile: String) -> AABB:
	# The composition window for one subject in one profile: measured
	# override first, else the profile window rule applied to the subject's own
	# measured silhouette.
	var cfg := profile_config(profile)
	if cfg.is_empty():
		return AABB()
	var overrides = FRAME_OVERRIDES.get(id, null)
	if typeof(overrides) == TYPE_DICTIONARY and (overrides as Dictionary).has(profile):
		return overrides[profile]
	var sil := silhouette(id)
	var window: Dictionary = cfg["window"]
	var top := 0.0
	var height := 0.0
	if str(window["mode"]) == "bust":
		height = float(window["height"])
		top = float(sil["top"]) + float(window["top_clearance"]) * height
	else:
		top = float(sil["top"]) + float(window["head_clearance"])
		height = top - float(window["floor"])
	var width := maxf(float(sil["half_width"]) * 2.0, float(window["min_width"]))
	width = maxf(width, height * float(window["min_aspect"]))
	width = minf(width, height * float(window["max_aspect"]))
	height = maxf(height, 0.01)
	return AABB(Vector3(-width * 0.5, top - height, -width * 0.5), Vector3(width, height, width))

static func team_offset(index: int, count: int) -> Vector3:
	if count <= 1:
		return Vector3.ZERO
	return Vector3((index - (count - 1) * 0.5) * TEAM_SPACING, 0.0, 0.0)

static func box_for(ids: Array, profile: String) -> AABB:
	# One subject: its own window. Several (RESULTS_TEAM): the union of each
	# subject's window placed at its team offset.
	if ids.is_empty():
		return AABB()
	var first := framed_box(str(ids[0]), profile)
	if ids.size() == 1:
		return first
	var combined := AABB()
	var started := false
	for i in ids.size():
		var per := framed_box(str(ids[i]), profile)
		var moved := AABB(per.position + team_offset(i, ids.size()), per.size)
		if not started:
			combined = moved
			started = true
		else:
			combined = combined.merge(moved)
	return combined

static func camera_forward(cfg: Dictionary) -> Vector3:
	return Vector3(
		sin(deg_to_rad(float(cfg["angle_deg"]))),
		sin(deg_to_rad(float(cfg["elev_deg"]))),
		cos(deg_to_rad(float(cfg["angle_deg"])))).normalized()

static func aim_center(box: AABB, cfg: Dictionary) -> Vector3:
	return box.get_center() + Vector3(0.0, float(cfg["aim_offset_y"]), 0.0)

static func fit_distance(box: AABB, cfg: Dictionary, aspect: float) -> float:
	# The hero_rig camera-fit math, in ONE place: project the box onto the
	# camera's right/up axes against the ACTUAL destination aspect, so the raw
	# render and the displayed frame represent the same composition (Doc 07 §4).
	var center := aim_center(box, cfg)
	var vfov := deg_to_rad(float(cfg["fov"]))
	var forward := camera_forward(cfg)
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
	var safe_aspect := maxf(aspect, 0.01)
	var dist_v := half_h / tan(vfov * 0.5)
	var dist_h := half_w / (tan(vfov * 0.5) * safe_aspect)
	return maxf(dist_v, dist_h) * float(cfg["fit_margin"])

static func presence(id: String, profile: String) -> float:
	# Optical presence: the share of the framed window the subject's own
	# measured silhouette occupies. Comparable across the roster by
	# construction (Doc 07 §6: comparable optical presence, not equal AABB math).
	var box := framed_box(id, profile)
	if box.size.y <= 0.0:
		return 0.0
	var sil := silhouette(id)
	return (float(sil["top"]) - float(sil["sole"])) / box.size.y

static func head_clearance(id: String, profile: String) -> float:
	# Share of the window between the frame top and the measured head top.
	var box := framed_box(id, profile)
	if box.size.y <= 0.0:
		return 0.0
	var sil := silhouette(id)
	return (box.position.y + box.size.y - float(sil["top"])) / box.size.y

# --- render density (Doc 07 §5; ledger C-048) -------------------------------

static func render_density(profile: String, displayed_size: Vector2, content_scale := 1.0, quality_scale := -1.0) -> Vector2i:
	# target_render_px = displayed_physical_px x quality_scale, clamped by the
	# profile's min/max and pixel-area caps. The aspect is the DESTINATION
	# aspect, so the TextureRect never needs a destructive cover crop.
	var cfg := profile_config(profile)
	if cfg.is_empty():
		return Vector2i(8, 8)
	var quality := clampf(quality_scale if quality_scale > 0.0 else DEFAULT_QUALITY_SCALE, QUALITY_MIN, QUALITY_MAX)
	var scale := clampf(content_scale, CONTENT_SCALE_MIN, CONTENT_SCALE_MAX) * quality
	var display := Vector2(maxf(displayed_size.x, 1.0), maxf(displayed_size.y, 1.0))
	var aspect := clampf(display.x / display.y, ASPECT_MIN, ASPECT_MAX)
	var min_size: Vector2i = cfg["min_size"]
	var max_size: Vector2i = cfg["max_size"]
	var target_h := display.y * scale
	target_h = clampf(target_h, float(min_size.y), float(max_size.y))
	var target_w := target_h * aspect
	target_w = clampf(target_w, float(min_size.x), float(max_size.x))
	target_h = target_w / aspect
	var area := target_w * target_h
	var cap := float(cfg["max_area"])
	if area > cap:
		var shrink := sqrt(cap / area)
		target_w *= shrink
		target_h *= shrink
	return Vector2i(maxi(int(round(target_w)), 8), maxi(int(round(target_h)), 8))

static func density_is_material(current: Vector2i, target: Vector2i) -> bool:
	# Reallocate only on meaningful size/profile/output changes (Doc 07 §5):
	# never per frame, and never for a sub-pixel-relayout wobble.
	return absi(current.x - target.x) > DENSITY_HYSTERESIS_PX or absi(current.y - target.y) > DENSITY_HYSTERESIS_PX

# --- lifecycle / budget policy ----------------------------------------------

static func mode_name(mode: int) -> String:
	return "STATIC_POSE" if mode == MODE_STATIC_POSE else "LIVE_IDLE"

static func normalize_mode(mode) -> int:
	if typeof(mode) == TYPE_STRING:
		return MODE_LIVE_IDLE if String(mode).to_upper() == "LIVE_IDLE" else MODE_STATIC_POSE
	return MODE_LIVE_IDLE if int(mode) == MODE_LIVE_IDLE else MODE_STATIC_POSE

static func bay_mode(is_active: bool) -> int:
	# PlayerBay presentation policy (Doc 07 §3 performance fallback, Doc 04
	# §12): the active/candidate bay stays LIVE_IDLE, every other occupied bay
	# is deliberately STATIC_POSE. A hidden bay view stops updating entirely
	# (the view owns that rule).
	return MODE_LIVE_IDLE if is_active else MODE_STATIC_POSE

# --- portrait generation spec (Doc 07 §8; ledger C-034) ---------------------

static func portrait_spec(id: String) -> Dictionary:
	# Deterministic inputs for tools/portrait_gen.gd: resolve -> STATIC_POSE ->
	# portrait framing -> render -> export. The spec is pure data, so two reads
	# are identical and two generations capture the same pose/time.
	var cfg := profile_config(PROFILE_PORTRAIT)
	return {
		"id": id,
		"profile": PROFILE_PORTRAIT,
		"mode": MODE_STATIC_POSE,
		"mode_name": mode_name(MODE_STATIC_POSE),
		"pose_yaw_deg": BASE_YAW_DEG,
		"pose_time": 0.0,
		"box": framed_box(id, PROFILE_PORTRAIT),
		"render_size": cfg["render_size"],
		"deterministic": has(id),
	}

static func portrait_specs() -> Array:
	var out: Array = []
	for id in roster_ids():
		out.append(portrait_spec(str(id)))
	return out
